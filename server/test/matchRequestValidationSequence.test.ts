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
import { type Env } from '../src/index';
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

describe('Match Request Validation Sequence (Madde 3 & Madde 2 Doğrulaması)', () => {
  let profileDOs: Map<string, { profile: UserProfile; ctxObj: ReturnType<typeof createMockProfileCtx> }>;
  let env: Env;
  let markRematchCalled: boolean;

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

  function connectSocket(uid: string) {
    const entry = getEntry(uid);
    const ws = createMockSocket(uid);
    entry.ctxObj.ctx.acceptWebSocket(ws as any, [uid]);
    return ws;
  }

  beforeEach(() => {
    profileDOs = new Map();
    markRematchCalled = false;

    env = {
      USER_PROFILE: {
        idFromName: (uid: string) => ({ name: uid, toString: () => uid }) as any,
        get: (id: any) => getEntry(id.name).profile as any,
      } as any,
      MATCHMAKER: {
        idFromName: (_name: string) => ({ name: 'global' }) as any,
        get: (_id: any) =>
          ({
            createDirectMatch: async () => ({
              ok: true,
              matchId: 'new-match-123',
              isFriendly: true,
              matchType: 'friendly',
            }),
          }) as any,
      } as any,
      MATCH_ROOM: {
        idFromString: mockIdFromString as any,
        idFromName: (_name: string) => ({ name: _name }) as any,
        get: (_id: any) =>
          ({
            validateRematchRequest: async () => ({
              ok: true,
              matchType: 'ranked',
            }),
            markRematchRequestCreated: async () => {
              markRematchCalled = true;
            },
          }) as any,
      } as any,
      START_COINS: '100',
      ENERGY_ENABLED: 'false',
      ALLOW_DEV_AUTH: 'true',
    } as any;
  });

  it('Adım 1: Kendine maç isteği gönderme -> invalid', async () => {
    await initUser('u1');
    const ws1 = connectSocket('u1');

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u1' })
    );

    expect(ws1.sent).toHaveLength(1);
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'invalid',
    });
  });

  it('Adım 2: Engelleme veya silinmiş hesap -> offline (gizlilik garantisi)', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    connectSocket('u2'); // u2 online!

    // u2 blocks u1
    await getEntry('u2').profile.blockUser({ uid: 'u2', blockedUid: 'u1', blockedNickname: 'u1' });

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(ws1.sent).toHaveLength(1);
    // Even though u2 is online and settings are on, block results in 'offline' (not revealing block)
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'offline',
    });
  });

  it('Adım 2b: u1 u2yi engellediğinde de offline döner', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    connectSocket('u2');

    // u1 blocks u2
    await getEntry('u1').profile.blockUser({ uid: 'u1', blockedUid: 'u2', blockedNickname: 'u2' });

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(ws1.sent).toHaveLength(1);
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'offline',
    });
  });

  it('Adım 3: Alıcının maç istekleri kapalıysa -> requests_disabled (offline olsa bile online durumu sızdırılmaz)', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');

    // u2 is OFFLINE (no socket connected)
    // u2 has allowMatchRequests = false
    await getEntry('u2').profile.updateSettings({ allowMatchRequests: false });

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(ws1.sent).toHaveLength(1);
    // Must return 'requests_disabled', NOT 'offline' (settings_off is evaluated before online check)
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'requests_disabled',
    });
  });

  it('Adım 4: Alıcının istekleri açık ama çevrimdışı (soketi yok) -> offline', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    // u2 has no socket

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(ws1.sent).toHaveLength(1);
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'offline',
    });
  });

  it('Adım 5: Alıcı meşgul (presence: busy) -> unavailable', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    const ws2 = connectSocket('u2');
    await getEntry('u2').profile.webSocketMessage(
      ws2 as any,
      JSON.stringify({ t: 'presence', state: 'busy' })
    );

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    expect(ws1.sent).toHaveLength(1);
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'unavailable',
    });
  });

  it('Adım 5b: Alıcının bekleyen başka bir gelen isteği varsa -> unavailable', async () => {
    await initUser('u1');
    await initUser('u2');
    await initUser('u3');
    const ws1 = connectSocket('u1');
    connectSocket('u2');
    const ws3 = connectSocket('u3');

    // u3 sends request to u2 first -> delivered
    await getEntry('u3').profile.webSocketMessage(
      ws3 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(ws3.sent).toHaveLength(1);
    expect(ws3.sent[0].t).toBe('match_request_sent');

    // Now u1 sends request to u2 -> u2 already has pending incoming -> unavailable
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(ws1.sent).toHaveLength(1);
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'unavailable',
    });
  });

  it('Adım 6: Gönderenin kendi cooldown durumu -> cooldown_active', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    const ws2 = connectSocket('u2');

    // u1 sends to u2
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    const reqId = ws1.sent[0].id;

    // u2 declines
    await getEntry('u2').profile.webSocketMessage(
      ws2 as any,
      JSON.stringify({ t: 'decline_match_request', id: reqId })
    );

    // u1 immediately tries to send to u2 again -> cooldown_active (45s cooldown)
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );

    const lastMsg = ws1.sent[ws1.sent.length - 1];
    expect(lastMsg).toMatchObject({
      t: 'match_request_error',
      code: 'cooldown_active',
    });
  });

  it('Madde 2: Soket açıkken ayarı hızlı kapatıp açma (reconnect gerekmez, anında teslim edilir)', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    const ws2 = connectSocket('u2');

    // u2 toggles allowMatchRequests = false
    const resOff = await getEntry('u2').profile.updateSettings({ allowMatchRequests: false });
    expect(resOff).toEqual({ allowMatchRequests: false });

    // u1 sends -> requests_disabled
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'requests_disabled',
    });

    // u2 immediately toggles allowMatchRequests = true without reconnecting socket
    const resOn = await getEntry('u2').profile.updateSettings({ allowMatchRequests: true });
    expect(resOn).toEqual({ allowMatchRequests: true });

    // u1 sends to u2 again
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({ t: 'send_match_request', origin: 'profile', toUid: 'u2' })
    );
    const sentMsg = ws1.sent[1];
    expect(sentMsg.t).toBe('match_request_sent');

    // u2 received it directly via the existing open socket
    const receivedMsg = ws2.sent.find((m) => m.t === 'match_request_received');
    expect(receivedMsg).toBeDefined();
    expect(receivedMsg.fromUid).toBe('u1');
  });

  it('Rematch kotası yalnızca istek başarıyla teslim edilirse yakılır (markRematchRequestCreated)', async () => {
    await initUser('u1');
    await initUser('u2');
    const ws1 = connectSocket('u1');
    // u2 is offline

    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({
        t: 'send_match_request',
        origin: 'rematch',
        toUid: 'u2',
        matchId: 'mock-match-999',
      })
    );

    expect(ws1.sent[0]).toMatchObject({
      t: 'match_request_error',
      code: 'offline',
    });
    // markRematchRequestCreated was NOT called because request failed delivery
    expect(markRematchCalled).toBe(false);

    // Now connect u2
    connectSocket('u2');
    await getEntry('u1').profile.webSocketMessage(
      ws1 as any,
      JSON.stringify({
        t: 'send_match_request',
        origin: 'rematch',
        toUid: 'u2',
        matchId: 'mock-match-999',
      })
    );

    expect(ws1.sent[1].t).toBe('match_request_sent');
    // markRematchRequestCreated WAS called when successfully delivered
    expect(markRematchCalled).toBe(true);
  });
});
