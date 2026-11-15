import { describe, expect, it, vi, beforeEach } from 'vitest';
import { DatabaseSync } from 'node:sqlite';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

import { UserProfile } from '../src/userProfile';
import worker, { type Env } from '../src/index';
import { mockIdFromString } from './testHelpers';

function createMockSocket(tag: string, sent: any[] = []) {
  let attachment: any = null;
  let closed = false;
  let closeCode: number | null = null;
  let closeReason: string | null = null;

  return {
    tag,
    sent,
    get readyState() {
      return closed ? 2 : 1;
    },
    send: (data: string) => sent.push(JSON.parse(data)),
    deserializeAttachment: () => attachment,
    serializeAttachment: (val: any) => {
      attachment = val;
    },
    close: (code = 1000, reason = '') => {
      closed = true;
      closeCode = code;
      closeReason = reason;
    },
    get isClosed() {
      return closed;
    },
    get closeCode() {
      return closeCode;
    },
    get closeReason() {
      return closeReason;
    },
  } as unknown as WebSocket & {
    tag: string;
    sent: any[];
    isClosed: boolean;
    closeCode: number | null;
    closeReason: string | null;
  };
}

function createMockProfileCtx(uid: string) {
  const db = new DatabaseSync(':memory:');
  const sockets: any[] = [];
  let alarmTime: number | null = null;

  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      const upper = trimmed.toUpperCase();
      if (
        upper.startsWith('BEGIN') ||
        upper.startsWith('COMMIT') ||
        upper.startsWith('ROLLBACK') ||
        upper.startsWith('SAVEPOINT')
      ) {
        throw new Error(
          'Manual transactions not allowed. Use transactionSync instead.'
        );
      }
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('PRAGMA')
      ) {
        const stmt = db.prepare(trimmed);
        const rows = stmt.all(...bindings) as T[];
        return {
          toArray: () => rows,
          one: () => rows[0],
          [Symbol.iterator]: () => rows[Symbol.iterator](),
        };
      } else {
        if (bindings.length > 0) {
          const stmt = db.prepare(trimmed);
          stmt.run(...bindings);
        } else {
          db.exec(trimmed);
        }
        return {
          toArray: () => [],
          one: () => undefined as any,
          [Symbol.iterator]: () => [][Symbol.iterator](),
        };
      }
    },
  };

  return {
    ctx: {
      id: { name: uid, toString: () => uid },
      storage: {
        sql,
        async setAlarm(time: number) {
          alarmTime = time;
        },
        async getAlarm() {
          return alarmTime;
        },
        async deleteAlarm() {
          alarmTime = null;
        },
        async deleteAll() {
          try {
            const tables = sql
              .exec<{ name: string }>(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
              )
              .toArray();
            for (const t of tables) {
              db.exec(`DROP TABLE IF EXISTS ${t.name}`);
            }
          } catch {}
        },
        transactionSync<T>(closure: () => T): T {
          db.exec('BEGIN TRANSACTION');
          try {
            const res = closure();
            db.exec('COMMIT');
            return res;
          } catch (err) {
            try {
              db.exec('ROLLBACK');
            } catch {}
            throw err;
          }
        },
      },
      blockConcurrencyWhile(fn: () => Promise<void>) {
        return fn();
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets.filter((s) => !s.isClosed);
        return sockets.filter((s) => !s.isClosed && s.tag === tag);
      },
      getTags(ws: any) {
        return ws.tag ? [ws.tag] : [];
      },
      acceptWebSocket(ws: any, tags?: string[]) {
        if (tags && tags[0]) ws.tag = tags[0];
        sockets.push(ws);
      },
    } as unknown as DurableObjectState,
    sockets,
    getAlarm: () => alarmTime,
  };
}

describe('Maç İsteği (Match Request) & /ws/user Sistemi', () => {
  let profileDOs: Map<string, { profile: UserProfile; ctxObj: ReturnType<typeof createMockProfileCtx> }>;
  let env: Env;
  let directMatchResult: any;
  let rematchValidationResult: any;

  function getEntry(uid: string) {
    let entry = profileDOs.get(uid);
    if (!entry) {
      const ctxObj = createMockProfileCtx(uid);
      const profile = new UserProfile(ctxObj.ctx, env);
      entry = { profile, ctxObj };
      profileDOs.set(uid, entry);
    }
    return entry;
  }

  async function initUser(uid: string) {
    const entry = getEntry(uid);
    await entry.profile.getProfile(uid);
    return entry;
  }

  beforeEach(() => {
    profileDOs = new Map();
    directMatchResult = {
      ok: true,
      matchId: 'new-match-123',
      isFriendly: true,
      matchType: 'friendly',
    };
    rematchValidationResult = {
      ok: true,
      matchType: 'ranked',
    };

    env = {
      USER_PROFILE: {
        idFromName: (uid: string) => ({ name: uid, toString: () => uid }) as any,
        get: (id: any) => getEntry(id.name).profile as any,
      } as any,
      MATCHMAKER: {
        idFromName: (_name: string) => ({ name: 'global' }) as any,
        get: (_id: any) =>
          ({
            createDirectMatch: async (params: any) => {
              if (typeof directMatchResult === 'function') {
                return directMatchResult(params);
              }
              return directMatchResult;
            },
          }) as any,
      } as any,
      MATCH_ROOM: {
        idFromString: mockIdFromString as any,
        idFromName: (_name: string) => ({ name: _name }) as any,
        get: (_id: any) =>
          ({
            validateRematchRequest: async (senderUid: string, receiverUid: string) => {
              if (typeof rematchValidationResult === 'function') {
                return rematchValidationResult(senderUid, receiverUid);
              }
              return rematchValidationResult;
            },
            markRematchRequestCreated: async () => {},
          }) as any,
      } as any,
      START_COINS: '100',
      ENERGY_ENABLED: 'false',
      ALLOW_DEV_AUTH: 'true',
    } as any;
  });

  it('1. HTTP rotaları: /ws/user yetkilendirme ve WebSocket yükseltmesi', async () => {
    // A) Upgrade header olmadan istek 400 döner
    const req1 = new Request('http://localhost/ws/user', {
      method: 'GET',
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(400);

    // B) Yetkilendirme jetonu olmadan istek 401 döner
    const req2 = new Request('http://localhost/ws/user', {
      method: 'GET',
      headers: { Upgrade: 'websocket' },
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(401);

    // C) Silinmiş hesap 410 döner
    const uEntry = profileDOs.get('deleted-user') ?? (() => {
      const c = createMockProfileCtx('deleted-user');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('deleted-user', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await uEntry.profile.deleteProfile('deleted-user');

    const req3 = new Request('http://localhost/ws/user?token=dev:deleted-user', {
      method: 'GET',
      headers: { Upgrade: 'websocket' },
    });
    const res3 = await worker.fetch(req3, env);
    expect(res3.status).toBe(410);
  });

  it('2. Ping / Pong mesajlaşması', async () => {
    const { profile, ctxObj } = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await profile.getProfile('u1');

    const socket = createMockSocket('u1');
    ctxObj.ctx.acceptWebSocket(socket, ['u1']);

    await profile.webSocketMessage(socket as any, JSON.stringify({ t: 'ping' }));
    expect(socket.sent).toEqual([{ t: 'pong' }]);
  });

  it('3. Durum (Presence) yönetimi: idle ve busy', async () => {
    const { profile, ctxObj } = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await profile.getProfile('u1');

    const socket = createMockSocket('u1');
    ctxObj.ctx.acceptWebSocket(socket, ['u1']);

    // Varsayılan bağlı kullanıcı müsait olmalı
    let avail = await profile.isAvailableForMatchRequest('other');
    expect(avail).toBe(true);

    // Busy mesajı gönder
    await profile.webSocketMessage(socket as any, JSON.stringify({ t: 'presence', state: 'busy' }));
    avail = await profile.isAvailableForMatchRequest('other');
    expect(avail).toBe(false);

    // Idle mesajı gönder
    await profile.webSocketMessage(socket as any, JSON.stringify({ t: 'presence', state: 'idle' }));
    avail = await profile.isAvailableForMatchRequest('other');
    expect(avail).toBe(true);
  });

  it('4. Çevrimdışı ve gizlilik kuralları: Alıcı müsait değilse yalnızca "unavailable" döner', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    // u2'nin açık soketi yok (çevrimdışı)
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(u1Socket.sent).toEqual([
      { t: 'match_request_error', code: 'offline' },
    ]);
  });

  it('5. Profil üzerinden dostluk maçı isteği: Gönderme, alma, kabul etme', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // u1 -> u2 istek gönderir
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(u1Socket.sent.length).toBe(1);
    expect(u1Socket.sent[0].t).toBe('match_request_sent');
    expect(u1Socket.sent[0].toUid).toBe('u2');
    expect(u1Socket.sent[0].type).toBe('friendly');

    expect(u2Socket.sent.length).toBe(1);
    expect(u2Socket.sent[0].t).toBe('match_request_received');
    expect(u2Socket.sent[0].fromUid).toBe('u1');
    expect(u2Socket.sent[0].type).toBe('friendly');

    const requestId = u2Socket.sent[0].id;
    expect(requestId).toBeDefined();

    // u2 isteği kabul eder
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: requestId })
    );

    // Her iki tarafa matched mesajı gitmeli
    const u1Matched = u1Socket.sent.find((m) => m.t === 'matched');
    const u2Matched = u2Socket.sent.find((m) => m.t === 'matched');

    expect(u1Matched).toBeDefined();
    expect(u1Matched.matchId).toBe('new-match-123');
    expect(u1Matched.isFriendly).toBe(true);

    expect(u2Matched).toBeDefined();
    expect(u2Matched.matchId).toBe('new-match-123');
    expect(u2Matched.isFriendly).toBe(true);
  });

  it('6. İstek reddetme ve 45 sn bekleme süresi (cooldown)', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // u1 -> u2 istek atar
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const requestId = u2Socket.sent[0].id;

    // u2 reddeder
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'decline_match_request', id: requestId })
    );

    expect(u2Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'declined',
    });
    expect(u1Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'declined',
    });

    // u1 hemen u2'ye tekrar istek atmaya çalışır -> cooldown_active hatası
    u1Socket.sent.length = 0;
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(u1Socket.sent.length).toBe(1);
    expect(u1Socket.sent[0].t).toBe('match_request_error');
    expect(u1Socket.sent[0].code).toBe('cooldown_active');
    expect(u1Socket.sent[0].retryAfterSec).toBeGreaterThan(0);
  });

  it('7. Gönderenin isteği iptal etmesi (cancel_match_request)', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const requestId = u1Socket.sent[0].id;

    // Gönderen iptal eder
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'cancel_match_request', id: requestId })
    );

    expect(u1Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'cancelled',
    });
    expect(u2Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'cancelled',
    });
  });

  it('8. İstek zaman aşımı (alarm ile 45 sn expire) ve cooldown tetiklenmesi', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    const now = Date.now();
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const requestId = u1Socket.sent[0].id;

    // Alıcı tarafında 45 saniye sonra alarm tetiklenir
    vi.setSystemTime(now + 46_000);
    await u2Entry.profile.alarm();

    expect(u2Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'expired',
    });
    expect(u1Socket.sent).toContainEqual({
      t: 'match_request_status',
      id: requestId,
      status: 'expired',
    });

    // Zaman aşımı sonrasında da 45 saniye cooldown aktif olmalı
    u1Socket.sent.length = 0;
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u1Socket.sent[0].t).toBe('match_request_error');
    expect(u1Socket.sent[0].code).toBe('cooldown_active');

    vi.useRealTimers();
  });

  it('9. Hız sınırı (Rate limit): Dakikada 3 istekten fazlası rate_limited döner', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    // 3 farklı kullanıcıya istek atıp hemen iptal edelim (aynı anda en fazla 1 aktif giden istek kuralı için)
    for (let i = 1; i <= 3; i++) {
      const targetUid = `target_${i}`;
      const targetEntry = profileDOs.get(targetUid) ?? (() => {
        const c = createMockProfileCtx(targetUid);
        const p = new UserProfile(c.ctx, env);
        profileDOs.set(targetUid, { profile: p, ctxObj: c });
        return { profile: p, ctxObj: c };
      })();
      await targetEntry.profile.getProfile(targetUid);
      const tSocket = createMockSocket(targetUid);
      targetEntry.ctxObj.ctx.acceptWebSocket(tSocket, [targetUid]);

      await u1Entry.profile.webSocketMessage(
        u1Socket as any,
        JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: targetUid })
      );

      const sentMsg = u1Socket.sent[u1Socket.sent.length - 1];
      expect(sentMsg.t).toBe('match_request_sent');

      // İptal et ki yeni istek atabilsin
      await u1Entry.profile.webSocketMessage(
        u1Socket as any,
        JSON.stringify({ t: 'cancel_match_request', id: sentMsg.id })
      );
    }

    // 4. istek: dakikada 3 kuralı aşılır
    const target4 = 'target_4';
    const target4Entry = profileDOs.get(target4) ?? (() => {
      const c = createMockProfileCtx(target4);
      const p = new UserProfile(c.ctx, env);
      profileDOs.set(target4, { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await target4Entry.profile.getProfile(target4);
    const t4Socket = createMockSocket(target4);
    target4Entry.ctxObj.ctx.acceptWebSocket(t4Socket, [target4]);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: target4 })
    );

    const lastMsg = u1Socket.sent[u1Socket.sent.length - 1];
    expect(lastMsg.t).toBe('match_request_error');
    expect(lastMsg.code).toBe('rate_limited');
    expect(lastMsg.retryAfterSec).toBeGreaterThan(0);
  });

  it('10. Karşılıklı eşzamanlı istek (Cross-request): İki oyuncu birbirine istek atarsa anında kabul edilir', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // u1, u2'ye istek atar
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    // u2 henüz kabul etmeden, kendisi de u1'e istek atar
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u1' })
    );

    // Her iki tarafa da anında matched mesajı gitmelidir!
    const u1Matched = u1Socket.sent.find((m) => m.t === 'matched');
    const u2Matched = u2Socket.sent.find((m) => m.t === 'matched');

    expect(u1Matched).toBeDefined();
    expect(u2Matched).toBeDefined();
    expect(u1Matched.matchId).toBe(u2Matched.matchId);
  });

  it('11. Rövanş isteği (origin: rematch): MatchRoom doğrulaması ve rankli maç türünün devralınması', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // A) Geçersiz/yabancı maç için rövanş isteği -> unavailable
    rematchValidationResult = { ok: false, error: 'invalid_players' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-bad' })
    );
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'unavailable' });

    // B) Geçerli normal bitmiş rankli maç için rövanş isteği
    u1Socket.sent.length = 0;
    rematchValidationResult = { ok: true, matchType: 'ranked' };
    directMatchResult = { ok: true, matchId: 'rematch-match-999', isFriendly: false, matchType: 'ranked' };

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-good' })
    );

    expect(u1Socket.sent[0].t).toBe('match_request_sent');
    expect(u1Socket.sent[0].type).toBe('ranked');
    expect(u2Socket.sent[0].t).toBe('match_request_received');
    expect(u2Socket.sent[0].type).toBe('ranked');

    // u2 kabul edince rankli matched mesajı gider
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: u2Socket.sent[0].id })
    );

    const u1Matched = u1Socket.sent.find((m) => m.t === 'matched');
    expect(u1Matched).toBeDefined();
    expect(u1Matched.isFriendly).toBe(false);
  });

  it('12. Ayarlar: PUT /me/settings ile "Maç isteklerini kapat" anahtarı', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await u1Entry.profile.getProfile('u1');

    // Varsayılan true
    const prof1 = await u1Entry.profile.getProfile('u1');
    expect(prof1.allowMatchRequests).toBe(true);

    // Kapat
    const req1 = new Request('http://localhost/me/settings?token=dev:u1', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ allowMatchRequests: false }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);
    const body1 = (await res1.json()) as any;
    expect(body1.ok).toBe(true);
    expect(body1.allowMatchRequests).toBe(false);

    const prof2 = await u1Entry.profile.getProfile('u1');
    expect(prof2.allowMatchRequests).toBe(false);

    // Başka kullanıcı istek atarsa u1 artık müsait görünmez
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await u2Entry.profile.getProfile('u2');
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u1' })
    );

    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'requests_disabled' });
  });

  it('13. Engelleme (Block) kuralları: Karşılıklı hiçbir yönde istek gitmez', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    // u1, u2'yi engeller
    await u1Entry.profile.blockUser({ blockedUid: 'u2', blockedNickname: 'U2' });

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // u1 -> u2 istek atmayı dener: unavailable
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'offline' });

    // u2 -> u1 istek atmayı dener: unavailable
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u1' })
    );
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'offline' });
  });

  it('14. Hesap silme: deleteProfile tüm açık soketleri 4001, "account_deleted" koduyla kapatır', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await u1Entry.profile.getProfile('u1');

    const s1 = createMockSocket('u1');
    const s2 = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(s1, ['u1']);
    u1Entry.ctxObj.ctx.acceptWebSocket(s2, ['u1']);

    await u1Entry.profile.deleteProfile('u1');

    expect(s1.isClosed).toBe(true);
    expect(s1.closeCode).toBe(4001);
    expect(s1.closeReason).toBe('account_deleted');

    expect(s2.isClosed).toBe(true);
    expect(s2.closeCode).toBe(4001);
    expect(s2.closeReason).toBe('account_deleted');
  });

  it('15. Çoklu cihaz yayını: Aynı hesaba bağlı tüm soketlere olaylar iletilir', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    // u2'nin 2 farklı soketi bağlı
    const u2SocketA = createMockSocket('u2');
    const u2SocketB = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2SocketA, ['u2']);
    u2Entry.ctxObj.ctx.acceptWebSocket(u2SocketB, ['u2']);

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(u2SocketA.sent[0].t).toBe('match_request_received');
    expect(u2SocketB.sent[0].t).toBe('match_request_received');
  });

  it('16. Mesaj boyutu sınırı: 4 KB üzerindeki mesaj soketi 1009 ile kapatır', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    await u1Entry.profile.getProfile('u1');

    const socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(socket, ['u1']);

    const largePayload = JSON.stringify({ t: 'ping', pad: 'a'.repeat(5000) });
    await u1Entry.profile.webSocketMessage(socket as any, largePayload);

    expect(socket.isClosed).toBe(true);
    expect(socket.closeCode).toBe(1009);
    expect(socket.closeReason).toBe('message_too_big');
  });

  it('17. Rankli maç kabulünde enerji yetersizliği: Teklif edenin enerjisi yoksa', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    rematchValidationResult = { ok: true, matchType: 'ranked' };
    directMatchResult = { ok: false, error: 'no_energy', errorTargetUid: 'u1' };

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-ranked' })
    );

    const requestId = u2Socket.sent[0].id;
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: requestId })
    );

    // Gönderene no_energy, alıcıya opponent_no_energy gitmeli
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'no_energy' });
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'opponent_no_energy' });
  });

  it('18. Rankli maç kabulünde enerji yetersizliği: Kabul edenin enerjisi yoksa', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    rematchValidationResult = { ok: true, matchType: 'ranked' };
    directMatchResult = { ok: false, error: 'opponent_no_energy', errorTargetUid: 'u2' };

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-ranked-2' })
    );

    const requestId = u2Socket.sent[0].id;
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: requestId })
    );

    // Kabul edene (u2) no_energy, gönderene (u1) opponent_no_energy gitmeli
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'no_energy' });
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'opponent_no_energy' });
  });

  it('19. Bağlantı anında anlık durum (snapshot recovery) kurtarma', async () => {
    const u1Entry = profileDOs.get('u1') ?? (() => {
      const c = createMockProfileCtx('u1');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u1', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();
    const u2Entry = profileDOs.get('u2') ?? (() => {
      const c = createMockProfileCtx('u2');
      const p = new UserProfile(c.ctx, env);
      profileDOs.set('u2', { profile: p, ctxObj: c });
      return { profile: p, ctxObj: c };
    })();

    await u1Entry.profile.getProfile('u1');
    await u2Entry.profile.getProfile('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    // Şimdi u2 yeni bir cihazdan / sekmeden bağlansın
    const u2NewSocket = createMockSocket('u2');
    u2Entry.profile.sendInitialSnapshots(u2NewSocket as any, 'u2');

    expect(u2NewSocket.sent.length).toBe(1);
    expect(u2NewSocket.sent[0].t).toBe('match_request_received');
    expect(u2NewSocket.sent[0].fromUid).toBe('u1');

    // u1 de yeni bir cihazdan / sekmeden bağlansın
    const u1NewSocket = createMockSocket('u1');
    u1Entry.profile.sendInitialSnapshots(u1NewSocket as any, 'u1');

    expect(u1NewSocket.sent.length).toBe(1);
    expect(u1NewSocket.sent[0].t).toBe('match_request_sent');
    expect(u1NewSocket.sent[0].toUid).toBe('u2');
  });

  it('20. Rövanş kaynağı (origin=rematch) doğrulama: bitmemiş, hükmen, yabancı oyuncu ve tekillik', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // A) Henüz bitmemiş maç
    rematchValidationResult = { ok: false, error: 'not_finished' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-unfinished' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });

    // B) Hükmen/terk/kopma/void ile biten maç
    rematchValidationResult = { ok: false, error: 'not_normal_end' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-forfeit' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });

    // C) Maçın oyuncusu olmayan gönderen/alıcı
    rematchValidationResult = { ok: false, error: 'invalid_players' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-foreign' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });

    // D) Aynı maç için ikinci rövanş isteği (already_requested)
    rematchValidationResult = { ok: false, error: 'already_requested' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-dup' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });
  });

  it('21. Rövanş kaynağı (origin=rematch): Tür mirası (friendly maç -> friendly, ranked maç -> ranked)', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // Friendly maç rövanşı
    rematchValidationResult = { ok: true, matchType: 'friendly' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-friendly' })
    );

    const sentMsg = u1Socket.sent.find((m) => m.t === 'match_request_sent');
    expect(sentMsg.type).toBe('friendly');
    const recMsg = u2Socket.sent.find((m) => m.t === 'match_request_received');
    expect(recMsg.type).toBe('friendly');

    // Temizle
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'cancel_match_request', id: sentMsg.id })
    );
    u1Socket.sent.length = 0;
    u2Socket.sent.length = 0;

    // Ranked maç rövanşı
    rematchValidationResult = { ok: true, matchType: 'ranked' };
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'rematch', toUid: 'u2', matchId: 'm-ranked' })
    );

    const sentRanked = u1Socket.sent.find((m) => m.t === 'match_request_sent');
    expect(sentRanked.type).toBe('ranked');
    const recRanked = u2Socket.sent.find((m) => m.t === 'match_request_received');
    expect(recRanked.type).toBe('ranked');
  });

  it('22. Kabul anında göndericinin soketinin kapanmış olması (çevrimdışı)', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const reqId = u2Socket.sent.find((m) => m.t === 'match_request_received').id;

    // Göndericinin soketi kapansın
    u1Socket.close(1000, 'navigated_away');
    await u1Entry.profile.webSocketClose(u1Socket as any, 1000, 'navigated_away');

    // Alıcı kabul etmeyi dener
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );

    // Alıcıya unavailable hatası ve cancelled durum bildirimi gitmeli, maç kurulmamalı
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'unavailable' });
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_status', id: reqId, status: 'cancelled' });
    expect(u2Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();
  });

  it('23. Kabul anında göndericinin presence "busy" olması', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const reqId = u2Socket.sent.find((m) => m.t === 'match_request_received').id;

    // Gönderici presence busy olsun (başka maça girdi)
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'presence', state: 'busy' })
    );

    // Alıcı kabul etmeyi dener
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );

    // Alıcıya unavailable ve cancelled gitmeli
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_error', code: 'unavailable' });
    expect(u2Socket.sent).toContainEqual({ t: 'match_request_status', id: reqId, status: 'cancelled' });

    // Göndericiye de isteğin sonlandığı bildirilmiş olmalı
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_status', id: reqId, status: 'cancelled' });
    expect(u2Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();
  });

  it('24. Süresi dolmuş isteği kabul etme denemesi: maç kurulmaz, expired durumu döner', async () => {
    vi.useFakeTimers();
    const now = 1000000000;
    vi.setSystemTime(now);

    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const reqId = u2Socket.sent.find((m) => m.t === 'match_request_received').id;

    // 46 sn sonraya geçelim (alarm tetiklenmemiş olsa dahi accept çağrısı süreyi kontrol eder)
    vi.setSystemTime(now + 46_000);

    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );

    expect(u2Socket.sent).toContainEqual({ t: 'match_request_status', id: reqId, status: 'expired' });
    expect(u2Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();

    vi.useRealTimers();
  });

  it('25. Çift kabul (idempotent accept): İkinci kabul yeni maç kurmaz', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    let directMatchCount = 0;
    directMatchResult = () => {
      directMatchCount++;
      return { ok: true, matchId: `match-${directMatchCount}`, isFriendly: true };
    };

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const reqId = u2Socket.sent.find((m) => m.t === 'match_request_received').id;

    // İlk kabul
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );
    expect(directMatchCount).toBe(1);

    // İkinci ardışık kabul
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );
    expect(directMatchCount).toBe(1); // Tekrar çağrılmamalı!
  });

  it('26. Gönderenin kendi isteğini kabul etmeye çalışması engellenir', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const reqId = u1Socket.sent.find((m) => m.t === 'match_request_sent').id;

    // Gönderen (u1) kendi attığı isteğin id'si ile accept göndermeyi dener
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: reqId })
    );

    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'invalid' });
    expect(u1Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();
  });

  it('27. Başkasının isteğine accept/decline/cancel göndermek: invalid hatası, durum değişmez', async () => {
    const u1Entry = await initUser('u1');
    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);

    // Var olmayan / yetkisiz ID ile accept
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'accept_match_request', id: 'fake-id-123' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'invalid' });

    // Var olmayan / yetkisiz ID ile decline
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'decline_match_request', id: 'fake-id-123' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'invalid' });

    // Var olmayan / yetkisiz ID ile cancel
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'cancel_match_request', id: 'fake-id-123' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'invalid' });
  });

  it('28. Kullanıcı başına tek bekleyen gelen ve giden isteği kuralı', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');
    const u3Entry = await initUser('u3');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);
    const u3Socket = createMockSocket('u3');
    u3Entry.ctxObj.ctx.acceptWebSocket(u3Socket, ['u3']);

    // A) u1 -> u2 istek gönderir (u2'nin bekleyen gelen isteği olur)
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u1Socket.sent.find((m) => m.t === 'match_request_sent')).toBeDefined();

    // B) u1 henüz bekleyen isteği varken u3'e yeni istek atmaya çalışır -> unavailable döner
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u3' })
    );
    expect(u1Socket.sent[u1Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });

    // C) u3 de u2'ye istek atmaya çalışır (u2 zaten meşgul/gelen isteği var) -> u3'e yalnızca unavailable döner
    await u3Entry.profile.webSocketMessage(
      u3Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u3Socket.sent[u3Socket.sent.length - 1]).toEqual({ t: 'match_request_error', code: 'unavailable' });
  });

  it('29. Cross-request: Alıcının allow_match_requests kapalı olduğu veya engelli olduğu durumda otomatik kabul OLMAMALI', async () => {
    const u1Entry = await initUser('u1');
    const u2Entry = await initUser('u2');

    const u1Socket = createMockSocket('u1');
    u1Entry.ctxObj.ctx.acceptWebSocket(u1Socket, ['u1']);
    const u2Socket = createMockSocket('u2');
    u2Entry.ctxObj.ctx.acceptWebSocket(u2Socket, ['u2']);

    // A) u2, u1'e istek atar
    await u2Entry.profile.webSocketMessage(
      u2Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u1' })
    );
    expect(u2Socket.sent.find((m) => m.t === 'match_request_sent')).toBeDefined();

    // Şimdi u2 maç isteklerini kapatsın
    await u2Entry.profile.updateSettings({ allowMatchRequests: false });

    // u1, u2'ye istek atmayı dener -> allowMatchRequests kapalı olduğu için cross-request auto-accept OLMAMALI!
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'requests_disabled' });
    expect(u1Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();

    // B) Engelleme durumu: u2 ayarları açsın ama u2, u1'i engellesin
    await u2Entry.profile.updateSettings({ allowMatchRequests: true });
    await u2Entry.profile.blockUser({ blockedUid: 'u1', blockedNickname: 'U1' });

    u1Socket.sent.length = 0;
    await u1Entry.profile.webSocketMessage(
      u1Socket as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(u1Socket.sent).toContainEqual({ t: 'match_request_error', code: 'offline' });
    expect(u1Socket.sent.find((m) => m.t === 'matched')).toBeUndefined();
  });

  it('30. user_presence yaşam döngüsü: Son soket kapanınca presence temizlenir, soketsiz kullanıcı her zaman unavailable sayılır', async () => {
    const u1Entry = await initUser('u1');
    const s1 = createMockSocket('u1');
    const s2 = createMockSocket('u1');

    u1Entry.ctxObj.ctx.acceptWebSocket(s1, ['u1']);
    u1Entry.ctxObj.ctx.acceptWebSocket(s2, ['u1']);

    expect(await u1Entry.profile.isAvailableForMatchRequest('stranger')).toBe(true);

    // İlk soket kapandı, ikinci soket açık -> hâlâ müsait
    s1.close();
    await u1Entry.profile.webSocketClose(s1 as any, 1000, 'tab_close');
    expect(await u1Entry.profile.isAvailableForMatchRequest('stranger')).toBe(true);

    // İkinci (son) soket kapandı -> presence temizlenir ve kullanıcı unavailable olur
    s2.close();
    await u1Entry.profile.webSocketClose(s2 as any, 1000, 'tab_close');
    expect(await u1Entry.profile.isAvailableForMatchRequest('stranger')).toBe(false);

    // Hibernation sonrası SQLite'ta eski "idle" kalmış olsa dahi (açık soket 0 iken) müsait sayılmaz
    u1Entry.ctxObj.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO user_presence (key, state) VALUES ('current', 'idle')"
    );
    expect(await u1Entry.profile.isAvailableForMatchRequest('stranger')).toBe(false);
  });

  it('31. pruneExpiredRecords: Sonuçlanmış isteklerin 5 dakika sonra, süresi dolan cooldown ve rate limit satırlarının temizlenmesi', async () => {
    const u1Entry = await initUser('u1');
    const now = Date.now();

    // Test verileri ekle
    u1Entry.ctxObj.ctx.storage.sql.exec(`
      INSERT INTO incoming_requests (id, from_uid, from_nickname, from_frame, type, origin, created_at, expires_at, status)
      VALUES ('inc-old', 'u2', 'U2', 'classic', 'friendly', 'profile', ${now - 10 * 60 * 1000}, ${now - 6 * 60 * 1000}, 'declined');

      INSERT INTO incoming_requests (id, from_uid, from_nickname, from_frame, type, origin, created_at, expires_at, status)
      VALUES ('inc-recent', 'u2', 'U2', 'classic', 'friendly', 'profile', ${now - 2 * 60 * 1000}, ${now - 1 * 60 * 1000}, 'declined');

      INSERT INTO match_request_cooldowns (target_uid, cooldown_until) VALUES ('u2', ${now - 1000});
      INSERT INTO match_request_cooldowns (target_uid, cooldown_until) VALUES ('u3', ${now + 30000});

      INSERT INTO match_request_rate_limits (created_at) VALUES (${now - 70000});
      INSERT INTO match_request_rate_limits (created_at) VALUES (${now - 10000});
    `);

    // Prune çalıştır
    u1Entry.profile.pruneExpiredRecords(now);

    // 5 dakikadan eski inc-old silinmiş olmalı, 1 dakikalık inc-recent korunmalı
    const incRows = u1Entry.ctxObj.ctx.storage.sql
      .exec<{ id: string }>('SELECT id FROM incoming_requests')
      .toArray();
    expect(incRows.map((r) => r.id)).toEqual(['inc-recent']);

    // Süresi dolmuş u2 cooldown silinmiş, u3 korunmuş olmalı
    const cdRows = u1Entry.ctxObj.ctx.storage.sql
      .exec<{ target_uid: string }>('SELECT target_uid FROM match_request_cooldowns')
      .toArray();
    expect(cdRows.map((r) => r.target_uid)).toEqual(['u3']);

    // 1 dakikadan eski rate limit silinmiş, yeni olan korunmuş olmalı
    const rlRows = u1Entry.ctxObj.ctx.storage.sql
      .exec<{ created_at: number }>('SELECT created_at FROM match_request_rate_limits')
      .toArray();
    expect(rlRows.length).toBe(1);
  });
});
