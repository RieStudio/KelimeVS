import { DurableObject } from 'cloudflare:workers';
import {
  type ContentProvider,
  DevContentProvider,
  RealtimeDbContentProvider,
  inspectSecretB64,
  logContentError,
} from './content';
import type { Question } from './engine';
import { parseMatchmakerMessage, type MatchmakerServerMessage } from './protocol';
import type { Env } from './index';

export interface QueueEntry {
  readonly uid: string;
  readonly name: string;
  readonly joinedAt: number;
  readonly blockedUids?: readonly string[];
}

export function selectAndShuffleEightQuestions(questions: readonly Question[]): Question[] {
  const arr = [...questions];
  if (arr.length <= 1) return arr;

  const randomBuffer = new Uint32Array(arr.length);
  crypto.getRandomValues(randomBuffer);
  for (let i = arr.length - 1; i > 0; i--) {
    const j = randomBuffer[i] % (i + 1);
    const tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
  return arr.slice(0, 8);
}

export function createContentProvider(env: Env): ContentProvider {
  // CONTENT_SOURCE yalnızca "dev" olabilir ve YALNIZCA ALLOW_DEV_AUTH === "true" iken dikkate alınır
  if (env.ALLOW_DEV_AUTH === 'true' && env.CONTENT_SOURCE === 'dev') {
    return new DevContentProvider();
  }

  const dbUrl = env.FIREBASE_DATABASE_URL?.trim();
  const serviceAccountB64 = env.FIREBASE_SERVICE_ACCOUNT_B64?.trim();
  const diag = inspectSecretB64(serviceAccountB64);

  if (!dbUrl || dbUrl === 'REPLACE_WITH_FIREBASE_DATABASE_URL') {
    logContentError({
      event: 'content_error',
      stage: 'secret_missing',
      errorName: 'ConfigError',
      detail: 'FIREBASE_DATABASE_URL is missing or placeholder',
      ...diag,
    });
    throw new Error(
      'RealtimeDbContentProvider configuration error: FIREBASE_DATABASE_URL is missing or placeholder.'
    );
  }

  if (!serviceAccountB64) {
    logContentError({
      event: 'content_error',
      stage: 'secret_missing',
      errorName: 'ConfigError',
      detail: 'FIREBASE_SERVICE_ACCOUNT_B64 is missing',
      ...diag,
    });
    throw new Error(
      'RealtimeDbContentProvider configuration error: FIREBASE_SERVICE_ACCOUNT_B64 is missing.'
    );
  }

  const ttlSeconds = parseInt(env.CONTENT_TTL_SECONDS ?? '3600', 10);
  return new RealtimeDbContentProvider({
    databaseUrl: dbUrl,
    serviceAccountB64,
    ttlSeconds: Number.isFinite(ttlSeconds) && ttlSeconds > 0 ? ttlSeconds : 3600,
  });
}

export class Matchmaker extends DurableObject<Env> {
  private queue: QueueEntry[] = [];
  private contentProvider: ContentProvider;

  constructor(ctx: DurableObjectState, env: Env, customProvider?: ContentProvider) {
    super(ctx, env);
    this.contentProvider = customProvider ?? createContentProvider(env);
    this.ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<QueueEntry[]>('queue');
      if (stored) {
        this.queue = stored;
      }
    });
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected WebSocket Upgrade', { status: 400 });
    }

    const uid = request.headers.get('X-User-Id');
    if (!uid) {
      return new Response('Unauthorized', { status: 401 });
    }

    // Varsa eski bağlantıyı temizle
    const existing = this.ctx.getWebSockets(uid);
    for (const ws of existing) {
      try {
        ws.close(4000, 'replaced');
      } catch {
        // yoksay
      }
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server, [uid]);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid) return;

    const parsed = parseMatchmakerMessage(
      typeof message === 'string' ? message : new TextDecoder().decode(message)
    );
    if (!parsed) return;

    if (parsed.t === 'queue') {
      // İçerik önbelleği geçerli değilse arka planda yüklemeye başla (önden ısıt)
      this.prewarmContent();

      // Kullanıcının engel listesini UserProfile'dan çek
      // NOT: Kuyruktayken eklenen engelin o kuyruk oturumunda geçerli olmayabileceği kabul edilen bir sınırlamadır.
      let blockedUids: string[] = [];
      try {
        if (this.env.USER_PROFILE) {
          const profileStub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(uid));
          blockedUids = await profileStub.getBlockedUids();
        }
      } catch {
        // Hata durumunda boş engel listesiyle devam et
      }

      // Aynı uid varsa güncelle, yoksa ekle (FIFO)
      const existingIdx = this.queue.findIndex((e) => e.uid === uid);
      const newEntry: QueueEntry = {
        uid,
        name: parsed.name,
        joinedAt: Date.now(),
        blockedUids,
      };

      if (existingIdx !== -1) {
        this.queue[existingIdx] = newEntry;
      } else {
        this.queue.push(newEntry);
      }

      await this.ctx.storage.put('queue', this.queue);

      const queuedMsg: MatchmakerServerMessage = { t: 'queued' };
      try {
        ws.send(JSON.stringify(queuedMsg));
      } catch {
        // yoksay
      }

      await this.tryMatch();
    } else if (parsed.t === 'cancel') {
      this.queue = this.queue.filter((e) => e.uid !== uid);
      await this.ctx.storage.put('queue', this.queue);

      const cancelMsg: MatchmakerServerMessage = { t: 'cancelled' };
      try {
        ws.send(JSON.stringify(cancelMsg));
        ws.close(1000, 'cancelled');
      } catch {
        // yoksay
      }
    }
  }

  /**
   * Kullanıcıyı kuyruktan çıkarır ve varsa açık WebSocket bağlantısını kapatır.
   */
  async removeFromQueue(uid: string): Promise<void> {
    const beforeLen = this.queue.length;
    this.queue = this.queue.filter((e) => e.uid !== uid);
    if (this.queue.length !== beforeLen) {
      await this.ctx.storage.put('queue', this.queue);
    }

    const sockets = this.ctx.getWebSockets(uid);
    for (const ws of sockets) {
      try {
        ws.close(4001, 'account_deleted');
      } catch {
        // yoksay
      }
    }
  }

  async webSocketClose(
    ws: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean
  ): Promise<void> {
    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid) return;

    const beforeLen = this.queue.length;
    this.queue = this.queue.filter((e) => e.uid !== uid);
    if (this.queue.length !== beforeLen) {
      await this.ctx.storage.put('queue', this.queue);
    }
  }

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid) return;

    this.queue = this.queue.filter((e) => e.uid !== uid);
    await this.ctx.storage.put('queue', this.queue);
  }

  private prewarmContent(): void {
    try {
      const prewarmPromise = this.contentProvider.getQuestions().catch(() => {
        // Hata istemciye iletilmez, yalnızca içerik sağlayıcının logContentError'ı ile günlüğe düşer
      });
      if (this.ctx && typeof this.ctx.waitUntil === 'function') {
        this.ctx.waitUntil(prewarmPromise);
      }
    } catch {
      // yoksay
    }
  }

  private async tryMatch(): Promise<void> {
    while (this.queue.length >= 2) {
      // Kuyruktaki eşleşebilir ilk ikiliyi bul
      let matchIdx1 = -1;
      let matchIdx2 = -1;

      for (let i = 0; i < this.queue.length - 1; i++) {
        const candidate1 = this.queue[i];
        for (let j = i + 1; j < this.queue.length; j++) {
          const candidate2 = this.queue[j];

          // Kendi kendisiyle eşleşmeyi önle
          if (candidate1.uid === candidate2.uid) {
            this.queue.splice(j, 1);
            await this.ctx.storage.put('queue', this.queue);
            j--;
            continue;
          }

          // Karşılıklı engelleme kontrolü (iki taraftan biri engellediyse eşleştirme)
          const b1 = candidate1.blockedUids ? new Set(candidate1.blockedUids) : null;
          const b2 = candidate2.blockedUids ? new Set(candidate2.blockedUids) : null;

          if (b1?.has(candidate2.uid) || b2?.has(candidate1.uid)) {
            continue;
          }

          matchIdx1 = i;
          matchIdx2 = j;
          break;
        }
        if (matchIdx1 !== -1) break;
      }

      if (matchIdx1 === -1 || matchIdx2 === -1) {
        // Kuyrukta birbirini engellememiş uyumlu çift yok.
        // Oyuncular kuyrukta kalır ve kendi bekleme süreleri (10 sn) dolunca bot maçına geçerler.
        break;
      }

      const p1 = this.queue[matchIdx1];
      const p2 = this.queue[matchIdx2];

      // İki oyuncuyu kuyruktan çıkar (önce büyük indeksi sil)
      this.queue.splice(matchIdx2, 1);
      this.queue.splice(matchIdx1, 1);
      await this.ctx.storage.put('queue', this.queue);

      let allQuestions: Question[];
      let fetchFailed = false;
      try {
        allQuestions = await this.contentProvider.getQuestions();
      } catch {
        allQuestions = [];
        fetchFailed = true;
      }

      if (!allQuestions || allQuestions.length < 8) {
        if (!fetchFailed) {
          logContentError({
            event: 'content_error',
            stage: 'parse',
            errorName: 'InsufficientQuestionsError',
            detail: `Matchmaker received fewer than 8 questions (found: ${allQuestions ? allQuestions.length : 0})`,
          });
        }
        // İçerik alınamazsa veya 8'den az soru varsa:
        // Kuyruktaki iki oyuncuya {"t":"error","code":"content_unavailable"} gönder,
        // kuyruktan çıkar, bağlantıyı kapat.
        const p1Sockets = this.ctx.getWebSockets(p1.uid);
        const p2Sockets = this.ctx.getWebSockets(p2.uid);
        const errMsg: MatchmakerServerMessage = {
          t: 'error',
          code: 'content_unavailable',
        };
        const errJson = JSON.stringify(errMsg);

        for (const s of [...p1Sockets, ...p2Sockets]) {
          try {
            s.send(errJson);
            s.close(1008, 'content_unavailable');
          } catch {
            // yoksay
          }
        }
        continue;
      }

      const matchId = crypto.randomUUID();
      const selectedQuestions = selectAndShuffleEightQuestions(allQuestions);
      const questionOrder = selectedQuestions.map((q) => q.id);

      // MatchRoom'u başlat (yalnızca seçilen 8 soru tam verisiyle aktarılır)
      const roomStub = this.env.MATCH_ROOM.get(this.env.MATCH_ROOM.idFromName(matchId));
      await roomStub.initMatch({
        matchId,
        p1: { uid: p1.uid, name: p1.name },
        p2: { uid: p2.uid, name: p2.name },
        questions: selectedQuestions,
        questionOrder,
      });

      // İki oyuncuya bildirim gönder ve bağlantılarını kapat
      const p1Sockets = this.ctx.getWebSockets(p1.uid);
      const p2Sockets = this.ctx.getWebSockets(p2.uid);

      const p1Matched: MatchmakerServerMessage = {
        t: 'matched',
        matchId,
        opponentName: p2.name,
      };
      const p2Matched: MatchmakerServerMessage = {
        t: 'matched',
        matchId,
        opponentName: p1.name,
      };

      for (const s of p1Sockets) {
        try {
          s.send(JSON.stringify(p1Matched));
          s.close(1000, 'matched');
        } catch {
          // yoksay
        }
      }

      for (const s of p2Sockets) {
        try {
          s.send(JSON.stringify(p2Matched));
          s.close(1000, 'matched');
        } catch {
          // yoksay
        }
      }
    }
  }
}

