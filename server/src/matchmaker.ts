import { DurableObject } from 'cloudflare:workers';
import { DevContentProvider } from './content/devContentProvider';
import type { Question } from './engine';
import { parseMatchmakerMessage, type MatchmakerServerMessage } from './protocol';
import type { Env } from './index';

export interface QueueEntry {
  readonly uid: string;
  readonly name: string;
  readonly joinedAt: number;
}

function shuffleQuestions(questions: readonly Question[]): string[] {
  const arr = [...questions];
  if (arr.length <= 1) return arr.map((q) => q.id);

  const randomBuffer = new Uint32Array(arr.length);
  crypto.getRandomValues(randomBuffer);
  for (let i = arr.length - 1; i > 0; i--) {
    const j = randomBuffer[i] % (i + 1);
    const tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
  return arr.slice(0, 8).map((q) => q.id);
}

export class Matchmaker extends DurableObject<Env> {
  private queue: QueueEntry[] = [];
  private contentProvider = new DevContentProvider();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
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
      // Aynı uid varsa güncelle, yoksa ekle (FIFO)
      const existingIdx = this.queue.findIndex((e) => e.uid === uid);
      const newEntry: QueueEntry = {
        uid,
        name: parsed.name,
        joinedAt: Date.now(),
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

  private async tryMatch(): Promise<void> {
    while (this.queue.length >= 2) {
      const p1 = this.queue[0];
      const p2 = this.queue[1];

      // Kendi kendisiyle eşleşmeyi önle
      if (p1.uid === p2.uid) {
        this.queue.splice(1, 1);
        await this.ctx.storage.put('queue', this.queue);
        continue;
      }

      // İki oyuncuyu kuyruktan çıkar
      this.queue.splice(0, 2);
      await this.ctx.storage.put('queue', this.queue);

      const matchId = crypto.randomUUID();
      const allQuestions = await this.contentProvider.getQuestions();
      const questionOrder = shuffleQuestions(allQuestions);

      // MatchRoom'u başlat
      const roomStub = this.env.MATCH_ROOM.get(this.env.MATCH_ROOM.idFromName(matchId));
      await roomStub.initMatch({
        matchId,
        p1: { uid: p1.uid, name: p1.name },
        p2: { uid: p2.uid, name: p2.name },
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

