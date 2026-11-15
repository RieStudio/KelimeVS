import { describe, expect, it, vi } from 'vitest';
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
import { MatchRoom } from '../src/matchRoom';
import { deserializeMatchState, serializeMatchState } from '../src/storage';
import type { Question, MatchState } from '../src/engine';
import type { Env } from '../src/index';
import { mockIdFromString } from './testHelpers';

function createMockSocket(tag: string, sent: any[] = []) {
  let attachment: any = null;
  let closed = false;
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
    close: () => {
      closed = true;
    },
  } as unknown as WebSocket & { sent: any[] };
}

function createMockProfileCtx(uid: string) {
  const db = new DatabaseSync(':memory:');
  const sockets: any[] = [];
  return {
    ctx: {
      storage: {
        sql: {
          exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
            const trimmed = query.trim();
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
          transactionSync<T>(fn: () => T): T {
            return fn();
          },
        },
        async setAlarm() {},
        async getAlarm() {
          return null;
        },
        async deleteAlarm() {},
      },
      acceptWebSocket(ws: any, tags?: string[]) {
        if (tags && tags[0]) ws.tag = tags[0];
        sockets.push(ws);
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets;
        return sockets.filter((s) => s.tag === tag);
      },
    } as unknown as DurableObjectState,
    db,
    sockets,
  };
}

function createMockRoomCtx() {
  const store = new Map<string, any>();
  const sockets: any[] = [];
  return {
    ctx: {
      storage: {
        async get(key: string) {
          return store.get(key);
        },
        async put(key: string, val: any) {
          store.set(key, val);
        },
        async setAlarm() {},
        async getAlarm() {
          return null;
        },
        async deleteAlarm() {},
        async deleteAll() {
          store.clear();
        },
      },
      blockConcurrencyWhile(fn: () => Promise<void>) {
        return fn();
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets;
        return sockets.filter((s) => s.tag === tag);
      },
      getTags(ws: any) {
        return ws.tag ? [ws.tag] : [];
      },
      acceptWebSocket(ws: any, tags?: string[]) {
        if (tags && tags[0]) ws.tag = tags[0];
        sockets.push(ws);
      },
    } as unknown as DurableObjectState,
    store,
    sockets,
  };
}

const sampleQuestions: Question[] = Array.from({ length: 8 }, (_, i) => ({
  id: `q${i + 1}`,
  categoryId: 'c1',
  text: `Soru ${i + 1}`,
  answers: [
    { id: `a${i + 1}_1`, display: 'Cevap 1', aliases: ['cevap1'] },
  ],
}));

describe('Gerçek MatchRoom ve UserProfile ile Rövanş Entegrasyonu', () => {
  it('İki gerçek kullanıcı maçı normal bitirip /ws/user bağlıyken rövanş teklifi gönderildiğinde', async () => {
    const userA_Uid = 'user_alice_123';
    const userB_Uid = 'user_bob_456';
    const matchId = crypto.randomUUID(); // Gerçek maçlarda matchmaker crypto.randomUUID() üretir

    // 1. UserProfile DO'ları
    const pA = createMockProfileCtx(userA_Uid);
    const pB = createMockProfileCtx(userB_Uid);

    // 2. MatchRoom DO
    const rCtx = createMockRoomCtx();

    const roomInstances = new Map<string, MatchRoom>();
    const profileInstances = new Map<string, UserProfile>();

    const env: Partial<Env> = {
      FAST_TIMERS: 'false',
      MATCH_ROOM: {
        // Matchmaker ve index.ts MATCH_ROOM nesnesini idFromName(matchId) ile çağırır:
        idFromName: (name: string) => ({ name, type: 'name' } as any),
        // Cloudflare Workers runtime'ın gerçek idFromString davranışı:
        idFromString: mockIdFromString as any,
        get: (id: any) => {
          return roomInstances.get(id.name);
        },
      } as any,
      USER_PROFILE: {
        idFromName: (name: string) => ({ name } as any),
        get: (id: any) => profileInstances.get(id.name),
      } as any,
      MATCHMAKER: {
        idFromName: () => ({ name: 'global' } as any),
        get: () => ({
          createDirectMatch: vi.fn(async () => ({
            ok: true,
            matchId: crypto.randomUUID(),
            p1: { uid: userA_Uid, name: 'Alice', frame: 'classic' },
            p2: { uid: userB_Uid, name: 'Bob', frame: 'classic' },
            isFriendly: false,
          })),
        }),
      } as any,
    };

    const userProfileA = new UserProfile(pA.ctx, env as Env);
    const userProfileB = new UserProfile(pB.ctx, env as Env);
    profileInstances.set(userA_Uid, userProfileA);
    profileInstances.set(userB_Uid, userProfileB);

    const room = new MatchRoom(rCtx.ctx, env as Env);
    // MatchRoom, matchmaker tarafından idFromName(matchId) ile atanır:
    roomInstances.set(matchId, room);

    // İki kullanıcının profillerini hazırla
    await userProfileA.getProfile(userA_Uid);
    await userProfileB.getProfile(userB_Uid);

    // İki kullanıcı /ws/user soketlerini bağlar
    const wsUserA = createMockSocket('userA');
    const wsUserB = createMockSocket('userB');
    (pA.ctx as any).acceptWebSocket(wsUserA as any, [userA_Uid]);
    (pB.ctx as any).acceptWebSocket(wsUserB as any, [userB_Uid]);

    // İki kullanıcı da presence: idle (maç sonu ekranında presence boştadır)
    await userProfileA.webSocketMessage(
      wsUserA as any,
      JSON.stringify({ t: 'presence', state: 'idle' })
    );
    await userProfileB.webSocketMessage(
      wsUserB as any,
      JSON.stringify({ t: 'presence', state: 'idle' })
    );

    // Maçı başlat
    await room.initMatch({
      matchId,
      p1: { uid: userA_Uid, name: 'Alice', frame: 'classic' },
      p2: { uid: userB_Uid, name: 'Bob', frame: 'classic' },
      questions: sampleQuestions,
      questionOrder: sampleQuestions.map((q) => q.id),
      matchType: 'ranked',
    });

    // Oyuncular odaya bağlanır
    const roomWsA = createMockSocket(userA_Uid);
    const roomWsB = createMockSocket(userB_Uid);
    (rCtx.ctx as any).acceptWebSocket(roomWsA as any, [userA_Uid]);
    (rCtx.ctx as any).acceptWebSocket(roomWsB as any, [userB_Uid]);

    await (room as any).handlePlayerConnected(userA_Uid);
    await (room as any).handlePlayerConnected(userB_Uid);

    // Maç normal biter: engineState normal bitti olarak kaydedilir
    const roomData = (room as any).data;
    const baseEngine = deserializeMatchState(roomData.engineState);
    const finishedEngine: MatchState = {
      ...baseEngine,
      phase: 'matchFinished',
      endedBy: 'normal',
    };
    (room as any).data = {
      ...roomData,
      status: 'finished',
      engineState: serializeMatchState(finishedEngine),
    };
    await (room as any).persist();

    // İstemciler maç sonunda oda soketlerini kapatır
    await room.webSocketClose(roomWsA as any, 1000, 'normal');
    await room.webSocketClose(roomWsB as any, 1000, 'normal');

    // userA, userB'ye rövanş isteği gönderir
    await userProfileA.handleClientSendMatchRequest(
      userA_Uid,
      'rematch',
      userB_Uid,
      matchId
    );

    // userA'nın aldığı mesajları kontrol et
    const userAMessages = wsUserA.sent;
    console.log('userA sent messages:', userAMessages);

    // userA match_request_sent veya match_request_error mı aldı?
    const hasError = userAMessages.some(
      (m: any) => m.t === 'match_request_error' && m.code === 'unavailable'
    );
    expect(hasError, 'HATA: userA "unavailable" hatası aldı!').toBe(false);

    const hasSent = userAMessages.some((m: any) => m.t === 'match_request_sent');
    expect(hasSent, 'userA match_request_sent mesajı almalıydı').toBe(true);
  });

  it('Alıcı ilk denemede meşgulken (busy) rövanş hakkı yanmamalı, meşguliyet bitince tekrar denenip iletilebilmeli', async () => {
    const userA_Uid = 'user_alice_123';
    const userB_Uid = 'user_bob_456';
    const matchId = crypto.randomUUID();

    const pA = createMockProfileCtx(userA_Uid);
    const pB = createMockProfileCtx(userB_Uid);
    const rCtx = createMockRoomCtx();

    const roomInstances = new Map<string, MatchRoom>();
    const profileInstances = new Map<string, UserProfile>();

    const env: Partial<Env> = {
      FAST_TIMERS: 'false',
      MATCH_ROOM: {
        idFromName: (name: string) => ({ name, type: 'name' } as any),
        get: (id: any) => roomInstances.get(id.name),
      } as any,
      USER_PROFILE: {
        idFromName: (name: string) => ({ name } as any),
        get: (id: any) => profileInstances.get(id.name),
      } as any,
      MATCHMAKER: {
        idFromName: () => ({ name: 'global' } as any),
        get: () => ({
          createDirectMatch: vi.fn(),
        }),
      } as any,
    };

    const userProfileA = new UserProfile(pA.ctx, env as Env);
    const userProfileB = new UserProfile(pB.ctx, env as Env);
    profileInstances.set(userA_Uid, userProfileA);
    profileInstances.set(userB_Uid, userProfileB);

    const room = new MatchRoom(rCtx.ctx, env as Env);
    roomInstances.set(matchId, room);

    await userProfileA.getProfile(userA_Uid);
    await userProfileB.getProfile(userB_Uid);

    const wsUserA = createMockSocket('userA');
    const wsUserB = createMockSocket('userB');
    (pA.ctx as any).acceptWebSocket(wsUserA as any, [userA_Uid]);
    (pB.ctx as any).acceptWebSocket(wsUserB as any, [userB_Uid]);

    // userA: idle, userB: busy!
    await userProfileA.webSocketMessage(
      wsUserA as any,
      JSON.stringify({ t: 'presence', state: 'idle' })
    );
    await userProfileB.webSocketMessage(
      wsUserB as any,
      JSON.stringify({ t: 'presence', state: 'busy' })
    );

    await room.initMatch({
      matchId,
      p1: { uid: userA_Uid, name: 'Alice', frame: 'classic' },
      p2: { uid: userB_Uid, name: 'Bob', frame: 'classic' },
      questions: sampleQuestions,
      questionOrder: sampleQuestions.map((q) => q.id),
      matchType: 'ranked',
    });

    const roomWsA = createMockSocket(userA_Uid);
    const roomWsB = createMockSocket(userB_Uid);
    (rCtx.ctx as any).acceptWebSocket(roomWsA as any, [userA_Uid]);
    (rCtx.ctx as any).acceptWebSocket(roomWsB as any, [userB_Uid]);

    await (room as any).handlePlayerConnected(userA_Uid);
    await (room as any).handlePlayerConnected(userB_Uid);

    const roomData = (room as any).data;
    const baseEngine = deserializeMatchState(roomData.engineState);
    const finishedEngine: MatchState = {
      ...baseEngine,
      phase: 'matchFinished',
      endedBy: 'normal',
    };
    (room as any).data = {
      ...roomData,
      status: 'finished',
      engineState: serializeMatchState(finishedEngine),
    };
    await (room as any).persist();

    await room.webSocketClose(roomWsA as any, 1000, 'normal');
    await room.webSocketClose(roomWsB as any, 1000, 'normal');

    // 1. Deneme: userB meşgul olduğundan unavailable döner
    await userProfileA.handleClientSendMatchRequest(
      userA_Uid,
      'rematch',
      userB_Uid,
      matchId
    );

    expect(wsUserA.sent).toContainEqual({
      t: 'match_request_error',
      code: 'unavailable',
    });

    // userB artık idle (müsait) oldu!
    wsUserA.sent.length = 0;
    await userProfileB.webSocketMessage(
      wsUserB as any,
      JSON.stringify({ t: 'presence', state: 'idle' })
    );

    // 2. Deneme: userB müsaitken tekrar istek gönderilir
    await userProfileA.handleClientSendMatchRequest(
      userA_Uid,
      'rematch',
      userB_Uid,
      matchId
    );

    // İkinci istek iletilmeli (rematchRequestCreated ilk başarısız denemede yanmamış olmalı!)
    const hasSent = wsUserA.sent.some((m: any) => m.t === 'match_request_sent');
    expect(hasSent, 'Alıcı müsait olunca rövanş isteği başarıyla iletilmeliydi').toBe(true);

    // 3. Deneme: İstek reddedildikten sonra (tek hak kuralı) tekrar denenirse already_requested ile reddedilmeli
    pA.db.exec("UPDATE outgoing_requests SET status = 'declined'");
    wsUserA.sent.length = 0;
    await userProfileA.handleClientSendMatchRequest(
      userA_Uid,
      'rematch',
      userB_Uid,
      matchId
    );

    // already_requested nedeniyle reddedilmeli
    expect(wsUserA.sent).toContainEqual({
      t: 'match_request_error',
      code: 'unavailable',
    });
  });
});
