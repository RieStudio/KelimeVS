import { DurableObject } from 'cloudflare:workers';
import {
  type ContentProvider,
  DevContentProvider,
  RealtimeDbContentProvider,
  inspectSecretB64,
  logContentError,
} from './content';
import type { Question } from './engine';
import {
  parseMatchmakerMessage,
  type MatchmakerServerMessage,
  generateFriendCode,
  sanitizePlayerName,
} from './protocol';
import { isEnergyEnabledForUser, getEnergyCostPerMatch, getEnergyMax } from './energy';
import type { Env } from './index';

export interface PendingEnergyRefund {
  readonly uid: string;
  readonly matchId: string;
  readonly amount: number;
  attempts: number;
  nextRetryAt: number;
}

export interface QueueEntry {
  readonly uid: string;
  readonly name: string;
  readonly frame?: string;
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

export interface StoredFriendRoom {
  readonly code: string;
  readonly hostUid: string;
  readonly hostName: string;
  readonly hostFrame?: string;
  readonly createdAt: number;
  readonly expiresAt: number;
  status: 'waiting_for_guest' | 'matched' | 'expired';
  matchedMatchId?: string;
  matchedOpponentName?: string;
  matchedOpponentFrame?: string;
}

interface RateLimitEntry {
  count: number;
  resetAt: number;
  hourCount: number;
  hourResetAt: number;
}

interface IpRateLimitEntry {
  count: number;
  resetAt: number;
}

const MAX_ACTIVE_FRIEND_ROOMS = 1000;
const IP_RATE_LIMIT_PER_MINUTE = 30;
const UID_RATE_LIMIT_PER_MINUTE = 5;
const UID_RATE_LIMIT_PER_HOUR = 15;

export class Matchmaker extends DurableObject<Env> {
  private queue: QueueEntry[] = [];
  private friendRooms = new Map<string, StoredFriendRoom>();
  private matchedPendingByHostUid = new Map<
    string,
    { matchId: string; opponentName: string; opponentFrame?: string; expiresAt: number }
  >();
  private failedAttemptsByUid = new Map<string, RateLimitEntry>();
  private failedAttemptsByIp = new Map<string, IpRateLimitEntry>();
  private pendingEnergyRefunds: PendingEnergyRefund[] = [];
  private contentProvider: ContentProvider;

  constructor(ctx: DurableObjectState, env: Env, customProvider?: ContentProvider) {
    super(ctx, env);
    this.contentProvider = customProvider ?? createContentProvider(env);
    this.ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<QueueEntry[]>('queue');
      if (stored) {
        this.queue = stored;
      }
      const storedRooms = await this.ctx.storage.get<StoredFriendRoom[]>('friend_rooms');
      if (storedRooms) {
        const now = Date.now();
        for (const r of storedRooms) {
          if (r.expiresAt > now) {
            this.friendRooms.set(r.code, r);
          }
        }
      }
      const storedRefunds = await this.ctx.storage.get<PendingEnergyRefund[]>('pending_energy_refunds');
      if (storedRefunds) {
        this.pendingEnergyRefunds = storedRefunds;
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

    const ip =
      request.headers.get('cf-connecting-ip') ??
      request.headers.get('x-forwarded-for') ??
      'unknown';

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

    this.ctx.acceptWebSocket(server, [uid, `ip:${ip}`]);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid) return;

    const ipTag = tags.find((t) => t.startsWith('ip:'));
    const ip = ipTag ? ipTag.slice(3) : 'unknown';

    const parsed = parseMatchmakerMessage(
      typeof message === 'string' ? message : new TextDecoder().decode(message)
    );
    if (!parsed) return;

    if (parsed.t === 'queue') {
      // İçerik önbelleği geçerli değilse arka planda yüklemeye başla (önden ısıt)
      this.prewarmContent();

      // Kullanıcının profil bilgilerini, enerji durumunu ve engel listesini çek
      // NOT: Kuyruktayken eklenen engelin o kuyruk oturumunda geçerli olmayabileceği kabul edilen bir sınırlamadır.
      let blockedUids: string[] = [];
      let playerInfo = { name: parsed.name, frame: 'classic' };
      try {
        if (this.env.USER_PROFILE) {
          const profileStub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(uid));
          if (isEnergyEnabledForUser(this.env, uid)) {
            const cost = getEnergyCostPerMatch(this.env);
            const energyState = await profileStub.getEnergyState(uid);
            if (energyState.current < cost) {
              try {
                ws.send(
                  JSON.stringify({
                    t: 'error',
                    code: 'no_energy',
                    message: 'Enerjin bitti',
                  })
                );
                ws.close(1008, 'no_energy');
              } catch {}
              return;
            }
          }
          blockedUids = await profileStub.getBlockedUids();
          playerInfo = await this.getPlayerInfo(uid, parsed.name);
        }
      } catch {
        // Hata durumunda varsayılanlarla devam et
      }

      // Aynı uid varsa güncelle, yoksa ekle (FIFO)
      const existingIdx = this.queue.findIndex((e) => e.uid === uid);
      const newEntry: QueueEntry = {
        uid,
        name: playerInfo.name,
        frame: playerInfo.frame,
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
    } else if (parsed.t === 'create_room') {
      await this.handleCreateRoom(ws, uid, ip, parsed);
    } else if (parsed.t === 'resume_room') {
      await this.handleResumeRoom(ws, uid, ip, parsed);
    } else if (parsed.t === 'join_room') {
      await this.handleJoinRoom(ws, uid, ip, parsed);
    } else if (parsed.t === 'cancel_room') {
      await this.handleCancelRoom(ws, uid, parsed);
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

    // Kullanıcının açık arkadaş odasını da temizle
    await this.cancelFriendRoomByHost(uid);

    const sockets = this.ctx.getWebSockets(uid);
    for (const ws of sockets) {
      try {
        ws.close(4001, 'account_deleted');
      } catch {
        // yoksay
      }
    }
  }

  async alarm(): Promise<void> {
    await this.pruneExpiredFriendRooms();
    await this.processPendingEnergyRefunds();
    await this.scheduleCombinedAlarm();
  }

  private async handleCreateRoom(
    ws: WebSocket,
    uid: string,
    _ip: string,
    parsed: { name?: string }
  ): Promise<void> {
    // 1. Kullanıcının önceki açık arkadaş odalarını temizle
    await this.cancelFriendRoomByHost(uid);

    // 2. Kapasite kontrolü
    if (this.friendRooms.size >= MAX_ACTIVE_FRIEND_ROOMS) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'lobby_busy',
          message: 'Lobi şu anda yoğun. Lütfen birkaç dakika sonra tekrar deneyin.',
        })
      );
      return;
    }

    // 3. Hesap silinmiş mi (Tombstone)?
    if (await this.isAccountDeleted(uid)) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'account_deleted',
          message: 'Hesap silinmiş',
        })
      );
      return;
    }

    // 4. Oyuncu adını ve çerçevesini profile güvenerek al
    const hostInfo = await this.getPlayerInfo(uid, parsed.name);
    this.prewarmContent();

    // 5. Çakışmayan 6 karakterlik davet kodu üret
    let code = generateFriendCode();
    let attempts = 0;
    while (this.friendRooms.has(code) && attempts < 10) {
      code = generateFriendCode();
      attempts++;
    }

    const now = Date.now();
    const expiresAt = now + 5 * 60 * 1000;
    const room: StoredFriendRoom = {
      code,
      hostUid: uid,
      hostName: hostInfo.name,
      hostFrame: hostInfo.frame,
      createdAt: now,
      expiresAt,
      status: 'waiting_for_guest',
    };

    this.friendRooms.set(code, room);
    await this.persistFriendRooms();
    await this.scheduleCombinedAlarm();

    try {
      ws.send(
        JSON.stringify({
          t: 'room_created',
          code,
          expiresAt,
        })
      );
    } catch {
      // yoksay
    }
  }

  private async handleResumeRoom(
    ws: WebSocket,
    uid: string,
    _ip: string,
    parsed: { code: string }
  ): Promise<void> {
    if (await this.isAccountDeleted(uid)) {
      ws.send(JSON.stringify({ t: 'error', code: 'account_deleted' }));
      return;
    }

    // Kurucu dışarıdayken (WhatsApp vb.) katılım gerçekleşmiş mi kontrol et
    const pendingMatched = this.matchedPendingByHostUid.get(uid);
    if (pendingMatched && pendingMatched.expiresAt > Date.now()) {
      this.matchedPendingByHostUid.delete(uid);
      try {
        ws.send(
          JSON.stringify({
            t: 'matched',
            matchId: pendingMatched.matchId,
            opponentName: pendingMatched.opponentName,
            opponentFrame: pendingMatched.opponentFrame || 'classic',
            isFriendly: true,
          })
        );
      } catch {}
      return;
    }

    const room = this.friendRooms.get(parsed.code);
    const now = Date.now();
    if (!room || room.expiresAt <= now) {
      if (room) {
        this.friendRooms.delete(parsed.code);
        await this.persistFriendRooms();
      }
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'room_not_found',
          message: 'Bu oda bulunamadı veya süresi dolmuş.',
        })
      );
      return;
    }

    if (room.hostUid !== uid) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'room_not_found',
          message: 'Bu oda bulunamadı.',
        })
      );
      return;
    }

    if (room.status === 'matched' && room.matchedMatchId && room.matchedOpponentName) {
      this.friendRooms.delete(parsed.code);
      await this.persistFriendRooms();
      try {
        ws.send(
          JSON.stringify({
            t: 'matched',
            matchId: room.matchedMatchId,
            opponentName: room.matchedOpponentName,
            opponentFrame: room.matchedOpponentFrame || 'classic',
            isFriendly: true,
          })
        );
      } catch {}
      return;
    }

    try {
      ws.send(
        JSON.stringify({
          t: 'room_resumed',
          code: room.code,
          expiresAt: room.expiresAt,
        })
      );
    } catch {}
  }

  private async handleJoinRoom(
    ws: WebSocket,
    uid: string,
    ip: string,
    parsed: { code: string; name?: string }
  ): Promise<void> {
    // 1. Hız sınırı (brute force) kontrolü
    const rl = this.checkRateLimit(uid, ip);
    if (!rl.allowed) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'rate_limited',
          message: 'Çok fazla hatalı deneme yaptın. Lütfen biraz bekle.',
          ...(rl.retryAfterSeconds ? { retryAfterSeconds: rl.retryAfterSeconds } : {}),
        })
      );
      return;
    }

    // 2. Tombstone kontrolü
    if (await this.isAccountDeleted(uid)) {
      ws.send(JSON.stringify({ t: 'error', code: 'account_deleted' }));
      return;
    }

    // 3. Oda varlığı ve geçerlilik süresi kontrolü
    const room = this.friendRooms.get(parsed.code);
    const now = Date.now();
    if (!room || room.expiresAt <= now) {
      if (room) {
        this.friendRooms.delete(parsed.code);
        await this.persistFriendRooms();
      }
      this.recordFailedAttempt(uid, ip);
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'room_not_found',
          message: 'Bu oda bulunamadı veya süresi dolmuş.',
        })
      );
      return;
    }

    // 4. Oda durumu kontrolü
    if (room.status !== 'waiting_for_guest') {
      this.recordFailedAttempt(uid, ip);
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'room_full',
          message: 'Bu odaya zaten başka bir oyuncu katılmış.',
        })
      );
      return;
    }

    // 5. Kendi odasına katılmayı engelle
    if (room.hostUid === uid) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'cannot_join_own_room',
          message: 'Kendi oluşturduğun odaya katılamazsın.',
        })
      );
      return;
    }

    // 6. Karşılıklı engelleme kontrolü
    let hostBlocked: string[] = [];
    let guestBlocked: string[] = [];
    try {
      if (this.env.USER_PROFILE) {
        const hostProfileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(room.hostUid)
        );
        hostBlocked = await hostProfileStub.getBlockedUids();
        const guestProfileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(uid)
        );
        guestBlocked = await guestProfileStub.getBlockedUids();
      }
    } catch {}

    if (hostBlocked.includes(uid) || guestBlocked.includes(room.hostUid)) {
      this.recordFailedAttempt(uid, ip);
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'room_unavailable',
          message: 'Bu odaya şu anda katılınamıyor.',
        })
      );
      return;
    }

    // 7. Soru havuzu kontrolü
    let allQuestions: Question[];
    try {
      allQuestions = await this.contentProvider.getQuestions();
    } catch {
      allQuestions = [];
    }
    if (!allQuestions || allQuestions.length < 8) {
      ws.send(
        JSON.stringify({
          t: 'error',
          code: 'content_unavailable',
          message: 'Soru havuzu şu anda kullanılamıyor.',
        })
      );
      return;
    }

    // Başarılı katılım: Hatalı deneme sayacını temizle
    this.clearFailedAttempts(uid);

    const guestInfo = await this.getPlayerInfo(uid, parsed.name);
    const matchId = crypto.randomUUID();
    const selectedQuestions = selectAndShuffleEightQuestions(allQuestions);
    const questionOrder = selectedQuestions.map((q) => q.id);

    // MatchRoom oluştur ve başlat (matchType: 'friendly')
    const roomStub = this.env.MATCH_ROOM.get(this.env.MATCH_ROOM.idFromName(matchId));
    await roomStub.initMatch({
      matchId,
      p1: { uid: room.hostUid, name: room.hostName, frame: room.hostFrame || 'classic' },
      p2: { uid, name: guestInfo.name, frame: guestInfo.frame || 'classic' },
      questions: selectedQuestions,
      questionOrder,
      matchType: 'friendly',
    });

    room.status = 'matched';
    room.matchedMatchId = matchId;
    room.matchedOpponentName = guestInfo.name;
    room.matchedOpponentFrame = guestInfo.frame;

    // Katılana matched mesajı gönder
    try {
      ws.send(
        JSON.stringify({
          t: 'matched',
          matchId,
          opponentName: room.hostName,
          opponentFrame: room.hostFrame || 'classic',
          isFriendly: true,
        })
      );
    } catch {}

    // Kurucuya matched mesajı gönder
    const hostSockets = this.ctx.getWebSockets(room.hostUid);
    let hostNotified = false;
    for (const hs of hostSockets) {
      try {
        hs.send(
          JSON.stringify({
            t: 'matched',
            matchId,
            opponentName: guestInfo.name,
            opponentFrame: guestInfo.frame || 'classic',
            isFriendly: true,
          })
        );
        hostNotified = true;
      } catch {}
    }

    // Kurucu soketi o anda kapalıysa (örn. WhatsApp'ta ise) döndüğünde alabilmesi için sakla
    if (!hostNotified) {
      this.matchedPendingByHostUid.set(room.hostUid, {
        matchId,
        opponentName: guestInfo.name,
        opponentFrame: guestInfo.frame || 'classic',
        expiresAt: Date.now() + 2 * 60 * 1000,
      });
    }

    // Odayı tek kullanımlık olarak kaldır
    this.friendRooms.delete(parsed.code);
    await this.persistFriendRooms();
  }

  private async handleCancelRoom(
    ws: WebSocket,
    uid: string,
    parsed: { code?: string }
  ): Promise<void> {
    let changed = false;
    for (const [code, r] of this.friendRooms.entries()) {
      if (r.hostUid === uid && (!parsed.code || parsed.code === code)) {
        this.friendRooms.delete(code);
        changed = true;
      }
    }
    this.matchedPendingByHostUid.delete(uid);
    if (changed) {
      await this.persistFriendRooms();
    }
    try {
      ws.send(JSON.stringify({ t: 'cancelled' }));
    } catch {}
  }

  async cancelFriendRoomByHost(uid: string): Promise<void> {
    let changed = false;
    for (const [code, r] of this.friendRooms.entries()) {
      if (r.hostUid === uid) {
        this.friendRooms.delete(code);
        changed = true;
      }
    }
    this.matchedPendingByHostUid.delete(uid);
    if (changed) {
      await this.persistFriendRooms();
    }
  }

  private async pruneExpiredFriendRooms(): Promise<void> {
    const now = Date.now();
    let changed = false;
    for (const [code, room] of this.friendRooms.entries()) {
      if (room.expiresAt <= now) {
        const sockets = this.ctx.getWebSockets(room.hostUid);
        for (const s of sockets) {
          try {
            s.send(JSON.stringify({ t: 'room_expired' }));
          } catch {}
        }
        this.friendRooms.delete(code);
        changed = true;
      }
    }
    for (const [uid, pending] of this.matchedPendingByHostUid.entries()) {
      if (pending.expiresAt <= now) {
        this.matchedPendingByHostUid.delete(uid);
      }
    }
    if (changed) {
      await this.persistFriendRooms();
    }
  }

  private async refundEnergyWithRetry(
    uid: string,
    matchId: string,
    amount: number
  ): Promise<void> {
    try {
      if (this.env.USER_PROFILE) {
        const profileStub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(uid));
        const res = await profileStub.refundEnergy({ matchId, amount, uid });
        if (res.ok) return;
      }
    } catch (err) {
      console.error('Immediate refundEnergy failed, scheduling persistent retry:', err);
    }

    const now = Date.now();
    this.pendingEnergyRefunds.push({
      uid,
      matchId,
      amount,
      attempts: 1,
      nextRetryAt: now + 5000,
    });
    await this.ctx.storage.put('pending_energy_refunds', this.pendingEnergyRefunds);
    await this.scheduleCombinedAlarm();
  }

  private async processPendingEnergyRefunds(): Promise<void> {
    if (this.pendingEnergyRefunds.length === 0) return;
    const now = Date.now();
    const remaining: PendingEnergyRefund[] = [];

    for (const item of this.pendingEnergyRefunds) {
      if (item.nextRetryAt > now) {
        remaining.push(item);
        continue;
      }

      let succeeded = false;
      try {
        if (this.env.USER_PROFILE) {
          const profileStub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(item.uid));
          const res = await profileStub.refundEnergy({
            matchId: item.matchId,
            amount: item.amount,
            uid: item.uid,
          });
          if (res.ok) succeeded = true;
        }
      } catch (err) {
        console.error('Retry refundEnergy failed:', err);
      }

      if (!succeeded) {
        if (item.attempts < 10) {
          const delayMs = Math.min(300_000, 5000 * Math.pow(2, item.attempts));
          remaining.push({
            ...item,
            attempts: item.attempts + 1,
            nextRetryAt: now + delayMs,
          });
        } else {
          console.error('Giving up on energy refund after 10 attempts:', item);
        }
      }
    }

    this.pendingEnergyRefunds = remaining;
    await this.ctx.storage.put('pending_energy_refunds', this.pendingEnergyRefunds);
  }

  private async scheduleCombinedAlarm(): Promise<void> {
    const now = Date.now();
    let earliest = Infinity;
    for (const room of this.friendRooms.values()) {
      if (room.expiresAt > now && room.expiresAt < earliest) {
        earliest = room.expiresAt;
      }
    }
    for (const refund of this.pendingEnergyRefunds) {
      if (refund.nextRetryAt < earliest) {
        earliest = refund.nextRetryAt;
      }
    }
    if (earliest !== Infinity) {
      await this.ctx.storage.setAlarm(earliest);
    }
  }

  private async persistFriendRooms(): Promise<void> {
    const list = Array.from(this.friendRooms.values());
    await this.ctx.storage.put('friend_rooms', list);
  }

  private checkRateLimit(
    uid: string,
    ip: string
  ): { allowed: boolean; retryAfterSeconds?: number } {
    const now = Date.now();
    // IP kontrolü (dakikada 30)
    const ipEntry = this.failedAttemptsByIp.get(ip);
    if (ipEntry) {
      if (now < ipEntry.resetAt) {
        if (ipEntry.count >= IP_RATE_LIMIT_PER_MINUTE) {
          return {
            allowed: false,
            retryAfterSeconds: Math.ceil((ipEntry.resetAt - now) / 1000),
          };
        }
      } else {
        this.failedAttemptsByIp.delete(ip);
      }
    }

    // UID kontrolü (dakikada 5, saatte 15)
    const uidEntry = this.failedAttemptsByUid.get(uid);
    if (uidEntry) {
      if (now < uidEntry.hourResetAt) {
        if (uidEntry.hourCount >= UID_RATE_LIMIT_PER_HOUR) {
          return {
            allowed: false,
            retryAfterSeconds: Math.ceil((uidEntry.hourResetAt - now) / 1000),
          };
        }
      } else {
        uidEntry.hourCount = 0;
        uidEntry.hourResetAt = now + 3600_000;
      }

      if (now < uidEntry.resetAt) {
        if (uidEntry.count >= UID_RATE_LIMIT_PER_MINUTE) {
          return {
            allowed: false,
            retryAfterSeconds: Math.ceil((uidEntry.resetAt - now) / 1000),
          };
        }
      } else {
        uidEntry.count = 0;
        uidEntry.resetAt = now + 60_000;
      }
    }

    return { allowed: true };
  }

  private recordFailedAttempt(uid: string, ip: string): void {
    const now = Date.now();
    const ipEntry = this.failedAttemptsByIp.get(ip) ?? {
      count: 0,
      resetAt: now + 60_000,
    };
    if (now >= ipEntry.resetAt) {
      ipEntry.count = 1;
      ipEntry.resetAt = now + 60_000;
    } else {
      ipEntry.count++;
    }
    this.failedAttemptsByIp.set(ip, ipEntry);

    const uidEntry = this.failedAttemptsByUid.get(uid) ?? {
      count: 0,
      resetAt: now + 60_000,
      hourCount: 0,
      hourResetAt: now + 3600_000,
    };
    if (now >= uidEntry.resetAt) {
      uidEntry.count = 1;
      uidEntry.resetAt = now + 60_000;
    } else {
      uidEntry.count++;
    }
    if (now >= uidEntry.hourResetAt) {
      uidEntry.hourCount = 1;
      uidEntry.hourResetAt = now + 3600_000;
    } else {
      uidEntry.hourCount++;
    }
    this.failedAttemptsByUid.set(uid, uidEntry);
  }

  private clearFailedAttempts(uid: string): void {
    this.failedAttemptsByUid.delete(uid);
  }

  private async getPlayerInfo(
    uid: string,
    fallbackName?: string
  ): Promise<{ name: string; frame: string }> {
    try {
      if (this.env.USER_PROFILE) {
        const profileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(uid)
        );
        const profile = await profileStub.getProfile(uid);
        if (profile) {
          const name = profile.nickname
            ? sanitizePlayerName(profile.nickname)
            : sanitizePlayerName(fallbackName);
          const frame = profile.equippedFrame || 'classic';
          return { name, frame };
        }
      }
    } catch {}
    return { name: sanitizePlayerName(fallbackName), frame: 'classic' };
  }

  private async getPlayerNickname(uid: string, fallbackName?: string): Promise<string> {
    const info = await this.getPlayerInfo(uid, fallbackName);
    return info.name;
  }

  private async isAccountDeleted(uid: string): Promise<boolean> {
    try {
      if (this.env.USER_PROFILE) {
        const profileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(uid)
        );
        return await profileStub.isDeleted();
      }
    } catch {}
    return false;
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

      // Enerji kesintisi (Karışık durum: yalnızca enerjisi açık olan oyuncudan düşülür)
      const p1EnergyEnabled = isEnergyEnabledForUser(this.env, p1.uid);
      const p2EnergyEnabled = isEnergyEnabledForUser(this.env, p2.uid);
      const energyCost = getEnergyCostPerMatch(this.env);

      let p1EnergySpent = false;
      let p2EnergySpent = false;
      let p1EnergyData: { current: number; max: number; nextEnergyAtMs: number | null } | undefined;
      let p2EnergyData: { current: number; max: number; nextEnergyAtMs: number | null } | undefined;

      if (p1EnergyEnabled && this.env.USER_PROFILE) {
        const p1Profile = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(p1.uid));
        const res1 = await p1Profile.spendEnergy({ matchId, amount: energyCost, uid: p1.uid });
        if (!res1.success) {
          const p1Sockets = this.ctx.getWebSockets(p1.uid);
          for (const s of p1Sockets) {
            try {
              s.send(JSON.stringify({ t: 'error', code: 'no_energy', message: 'Enerjin bitti' }));
              s.close(1008, 'no_energy');
            } catch {}
          }
          // p2'yi kuyruğun başına geri koy
          this.queue.unshift(p2);
          await this.ctx.storage.put('queue', this.queue);
          continue;
        }
        p1EnergySpent = true;
        p1EnergyData = {
          current: res1.energy,
          max: res1.max ?? getEnergyMax(this.env),
          nextEnergyAtMs: res1.nextEnergyAtMs ?? null,
        };
      }

      if (p2EnergyEnabled && this.env.USER_PROFILE) {
        const p2Profile = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(p2.uid));
        const res2 = await p2Profile.spendEnergy({ matchId, amount: energyCost, uid: p2.uid });
        if (!res2.success) {
          if (p1EnergySpent) {
            await this.refundEnergyWithRetry(p1.uid, matchId, energyCost);
          }
          const p2Sockets = this.ctx.getWebSockets(p2.uid);
          for (const s of p2Sockets) {
            try {
              s.send(JSON.stringify({ t: 'error', code: 'no_energy', message: 'Enerjin bitti' }));
              s.close(1008, 'no_energy');
            } catch {}
          }
          // p1'i kuyruğun başına geri koy
          this.queue.unshift(p1);
          await this.ctx.storage.put('queue', this.queue);
          continue;
        }
        p2EnergySpent = true;
        p2EnergyData = {
          current: res2.energy,
          max: res2.max ?? getEnergyMax(this.env),
          nextEnergyAtMs: res2.nextEnergyAtMs ?? null,
        };
      }

      const selectedQuestions = selectAndShuffleEightQuestions(allQuestions);
      const questionOrder = selectedQuestions.map((q) => q.id);

      // MatchRoom'u başlat (yalnızca seçilen 8 soru tam verisiyle aktarılır)
      const roomStub = this.env.MATCH_ROOM.get(this.env.MATCH_ROOM.idFromName(matchId));
      const energyChargedUids: string[] = [];
      if (p1EnergySpent) energyChargedUids.push(p1.uid);
      if (p2EnergySpent) energyChargedUids.push(p2.uid);

      try {
        await roomStub.initMatch({
          matchId,
          p1: { uid: p1.uid, name: p1.name, frame: p1.frame || 'classic' },
          p2: { uid: p2.uid, name: p2.name, frame: p2.frame || 'classic' },
          questions: selectedQuestions,
          questionOrder,
          energyChargedUids,
        });
      } catch (initErr) {
        console.error('roomStub.initMatch failed:', initErr);
        if (p1EnergySpent) {
          await this.refundEnergyWithRetry(p1.uid, matchId, energyCost);
        }
        if (p2EnergySpent) {
          await this.refundEnergyWithRetry(p2.uid, matchId, energyCost);
        }
        const p1Sockets = this.ctx.getWebSockets(p1.uid);
        const p2Sockets = this.ctx.getWebSockets(p2.uid);
        for (const s of [...p1Sockets, ...p2Sockets]) {
          try {
            s.send(JSON.stringify({ t: 'error', code: 'match_failed' }));
            s.close(1011, 'match_failed');
          } catch {}
        }
        continue;
      }

      // İki oyuncuya bildirim gönder ve bağlantılarını kapat
      const p1Sockets = this.ctx.getWebSockets(p1.uid);
      const p2Sockets = this.ctx.getWebSockets(p2.uid);
      const nowMs = Date.now();

      const p1Matched: MatchmakerServerMessage = {
        t: 'matched',
        matchId,
        opponentName: p2.name,
        opponentFrame: p2.frame || 'classic',
        ...(p1EnergyData ? { energy: p1EnergyData, serverNowMs: nowMs } : {}),
      };
      const p2Matched: MatchmakerServerMessage = {
        t: 'matched',
        matchId,
        opponentName: p1.name,
        opponentFrame: p1.frame || 'classic',
        ...(p2EnergyData ? { energy: p2EnergyData, serverNowMs: nowMs } : {}),
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

