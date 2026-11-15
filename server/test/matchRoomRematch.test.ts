import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

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

import { MatchRoom } from '../src/matchRoom';
import { Matchmaker } from '../src/matchmaker';
import { deserializeMatchState, serializeMatchState } from '../src/storage';
import type { Question, MatchState } from '../src/engine';
import type { Env } from '../src/index';

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
  };
}

function createMockRoomCtx() {
  const store = new Map<string, any>();
  const sockets: any[] = [];
  let alarmTime: number | null = null;
  let pendingInit: Promise<void> | null = null;

  return {
    ctx: {
      storage: {
        async get(key: string) {
          return store.get(key);
        },
        async put(key: string, val: any) {
          store.set(key, val);
        },
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
          store.clear();
        },
      },
      blockConcurrencyWhile(fn: () => Promise<void>) {
        pendingInit = fn();
        return pendingInit;
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
    getAlarm: () => alarmTime,
    waitForInit: async () => {
      if (pendingInit) await pendingInit;
    },
  };
}

const sampleQuestions: Question[] = Array.from({ length: 8 }, (_, i) => ({
  id: `q${i + 1}`,
  categoryId: 'c1',
  text: `Soru ${i + 1}`,
  answers: [
    { id: `a${i + 1}_1`, display: 'Cevap 1', aliases: ['cevap1'] },
    { id: `a${i + 1}_2`, display: 'Cevap 2', aliases: ['cevap2'] },
  ],
}));

async function setupFinishedMatch(options?: {
  matchType?: 'ranked' | 'friendly';
  forfeit?: boolean;
  bot?: boolean;
  envOverrides?: Partial<Env>;
}) {
  const fixedNow = 1_700_000_000_000;
  vi.setSystemTime(fixedNow);

  const { ctx, store, sockets, getAlarm } = createMockRoomCtx();
  const ws1 = createMockSocket('p1');
  const p2Uid = options?.bot ? 'bot' : 'p2';
  const ws2 = createMockSocket(p2Uid);
  sockets.push(ws1, ws2);

  const env: Partial<Env> = {
    FAST_TIMERS: 'false',
    USER_PROFILE: {
      idFromName: (name: string) => ({ toString: () => name } as any),
      get: (id: any) => ({
        applyMatchReward: vi.fn(async () => ({ coinsAwarded: 10, coins: 100, nickname: id.toString() })),
      }),
    } as any,
    MATCHMAKER: {
      idFromName: (name: string) => ({ toString: () => name } as any),
      get: () => ({
        createDirectMatch: vi.fn(async () => ({
          ok: true,
          matchId: 'new-match-456',
          p1: { uid: 'p1', name: 'Alice', frame: 'classic' },
          p2: { uid: p2Uid, name: options?.bot ? 'Bot' : 'Bob', frame: 'gold' },
          isFriendly: options?.matchType === 'friendly',
        })),
      }),
    } as any,
    ...options?.envOverrides,
  };

  const room = new MatchRoom(ctx, env as Env);
  await room.initMatch({
    matchId: 'old-match-123',
    p1: { uid: 'p1', name: 'Alice', frame: 'classic' },
    p2: { uid: p2Uid, name: options?.bot ? 'Bot' : 'Bob', frame: 'gold' },
    questions: sampleQuestions,
    questionOrder: sampleQuestions.map((q) => q.id),
    matchType: options?.matchType || 'ranked',
  });

  // Connect players
  await (room as any).handlePlayerConnected('p1');
  await (room as any).handlePlayerConnected(p2Uid);

  // Update roomData engineState to be finished
  const roomData = store.get('roomData');
  const baseEngine = deserializeMatchState(roomData.engineState);
  const finishedEngine: MatchState = {
    ...baseEngine,
    phase: 'matchFinished',
    endedBy: options?.forfeit ? 'forfeit' : 'normal',
    winnerId: 'p1',
  };
  roomData.engineState = serializeMatchState(finishedEngine);
  store.set('roomData', roomData);

  // Call handleMatchFinished so everything (final message, rewards, rematch state) is initialized properly
  await (room as any).handleMatchFinished();

  // Clear initial sent messages
  ws1.sent.length = 0;
  ws2.sent.length = 0;

  return { room, ctx, store, ws1, ws2, getAlarm, fixedNow, env, p2Uid };
}

describe('MatchRoom Rematch Availability & Graceful Legacy Degradation', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('1. Normal maç bitişinde final mesajı rematchAvailable: true içerir', async () => {
    const { room, ws1 } = await setupFinishedMatch();
    ws1.sent.length = 0;
    (room as any).broadcastFinal();

    const finalMsg = ws1.sent.find((m) => m.t === 'final');
    expect(finalMsg).toBeDefined();
    expect(finalMsg.rematchAvailable).toBe(true);
  });

  it('2. Hükmen/terk ile biten maçta final mesajı rematchAvailable: false içerir', async () => {
    const { room, ws1 } = await setupFinishedMatch({ forfeit: true });
    ws1.sent.length = 0;
    (room as any).broadcastFinal();

    const finalMsg = ws1.sent.find((m) => m.t === 'final');
    expect(finalMsg).toBeDefined();
    expect(finalMsg.rematchAvailable).toBe(false);
  });

  it('3. Bot rakiple biten maçta final mesajı rematchAvailable: false içerir', async () => {
    const { room, ws1 } = await setupFinishedMatch({ bot: true });
    ws1.sent.length = 0;
    (room as any).broadcastFinal();

    const finalMsg = ws1.sent.find((m) => m.t === 'final');
    expect(finalMsg).toBeDefined();
    expect(finalMsg.rematchAvailable).toBe(false);
  });

  it('4. Kaldırılan eski rövanş mesajları (rematch_offer, rematch_accept, rematch_decline, rematch_leave) bilinmeyen mesaj olarak sessizce yok sayılır, soket kapanmaz ve çökmez', async () => {
    const { room, ws1, ws2 } = await setupFinishedMatch();

    const oldMessages = [
      { t: 'rematch_offer' },
      { t: 'rematch_accept' },
      { t: 'rematch_decline' },
      { t: 'rematch_leave' },
    ];

    for (const msg of oldMessages) {
      ws1.sent.length = 0;
      ws2.sent.length = 0;

      await expect(
        room.webSocketMessage(ws1 as any, JSON.stringify(msg))
      ).resolves.not.toThrow();

      expect(ws1.isClosed).toBe(false);
      expect(ws2.isClosed).toBe(false);
      expect(ws1.sent.length).toBe(0);
      expect(ws2.sent.length).toBe(0);
    }
  });

  it('5. Depoda eski rövanş alanları (rematch nesnesi ve rematchTimeoutAtMs) ile kalmış veri yüklendiğinde ve alarm tetiklendiğinde hata vermez', async () => {
    const fixedNow = 1_700_000_000_000;
    vi.setSystemTime(fixedNow);

    const { ctx, store, getAlarm, waitForInit } = createMockRoomCtx();
    const legacyRoomData = {
      matchId: 'legacy-room-999',
      p1: { uid: 'p1', name: 'Alice', frame: 'classic' },
      p2: { uid: 'p2', name: 'Bob', frame: 'gold' },
      questions: sampleQuestions,
      questionOrder: sampleQuestions.map((q) => q.id),
      status: 'finished',
      finishedAtMs: fixedNow - 5000,
      rematch: {
        state: 'offered',
        offeredByUid: 'p1',
        expiresAtMs: fixedNow + 40000,
      },
      schedule: {
        rematchTimeoutAtMs: fixedNow + 40000,
        cleanupAtMs: fixedNow + 600000,
      },
    };
    store.set('roomData', legacyRoomData);

    const env = { FAST_TIMERS: 'false' } as Env;
    const room = new MatchRoom(ctx, env);
    await waitForInit();

    // migrateStoredRoomData eski rematch alanını ve rematchTimeoutAtMs'i güvenle ayıklar
    const loadedData = store.get('roomData');
    expect((room as any).data).toBeDefined();
    expect((room as any).data.rematch).toBeUndefined();
    expect((room as any).data.schedule.rematchTimeoutAtMs).toBeUndefined();
    expect((room as any).data.schedule.cleanupAtMs).toBe(fixedNow + 600000);

    // Alarm tetiklendiğinde (örneğin eski rematchTimeoutAtMs vadesi dolduğunda)
    vi.setSystemTime(fixedNow + 40000);
    await expect(room.alarm()).resolves.not.toThrow();

    // Oda çökmez, durum bozulmaz ve sonraki alarm temizlik alarmına (cleanupAtMs) ayarlanır
    expect((room as any).data.status).toBe('finished');
    expect(getAlarm()).toBe(fixedNow + 600000);
  });
});

describe('Matchmaker.createDirectMatch RPC & Energy/Blocks/Deletion Logic', () => {
  function createMockDOState() {
    const storageMap = new Map<string, unknown>();
    const socketsMap = new Map<string, any[]>();
    let currentAlarm: number | null = null;

    return {
      blockConcurrencyWhile: vi.fn(async (fn: () => Promise<void>) => fn()),
      storage: {
        get: vi.fn(async (key: string) => storageMap.get(key)),
        put: vi.fn(async (key: string, val: unknown) => {
          storageMap.set(key, val);
        }),
        setAlarm: vi.fn(async (timestamp: number) => {
          currentAlarm = timestamp;
        }),
        getAlarm: vi.fn(async () => currentAlarm),
        deleteAlarm: vi.fn(async () => {
          currentAlarm = null;
        }),
      },
      getTags: vi.fn((ws: any) => ws._tags ?? []),
      waitUntil: vi.fn(),
      getWebSockets: vi.fn((tag?: string) => {
        if (!tag) return [];
        return socketsMap.get(tag) ?? [];
      }),
      acceptWebSocket: vi.fn((ws: any, tags: string[]) => {
        ws._tags = tags;
        const uid = tags[0];
        if (uid) {
          if (!socketsMap.has(uid)) socketsMap.set(uid, []);
          socketsMap.get(uid)!.push(ws);
        }
      }),
      storageMap,
      socketsMap,
      getAlarmTime: () => currentAlarm,
    };
  }

  function createMockEnv(overrides?: {
    p1EnergySuccess?: boolean;
    p2EnergySuccess?: boolean;
    p1Blocked?: string[];
    p2Blocked?: string[];
    p1Deleted?: boolean;
    p2Deleted?: boolean;
    initMatchSpy?: any;
  }) {
    const refundEnergy = vi.fn(async () => ({ ok: true, refunded: true }));
    const spendEnergy = vi.fn(async ({ uid }: { uid: string }) => {
      if (uid === 'p1') {
        return { success: overrides?.p1EnergySuccess !== false };
      }
      return { success: overrides?.p2EnergySuccess !== false };
    });

    const initMatchSpy = overrides?.initMatchSpy || vi.fn(async () => {});

    const env: Partial<Env> = {
      FAST_TIMERS: 'false',
      ENERGY_ENABLED: 'true',
      ENERGY_COST_PER_MATCH: '1',
      USER_PROFILE: {
        idFromName: (name: string) => ({ toString: () => name } as any),
        get: (id: any) => {
          const uid = id.toString();
          return {
            isDeleted: vi.fn(async () => {
              if (uid === 'p1') return overrides?.p1Deleted ?? false;
              if (uid === 'p2') return overrides?.p2Deleted ?? false;
              return false;
            }),
            getBlockedUids: vi.fn(async () => {
              if (uid === 'p1') return overrides?.p1Blocked || [];
              if (uid === 'p2') return overrides?.p2Blocked || [];
              return [];
            }),
            getProfile: vi.fn(async () => ({
              uid,
              nickname: uid === 'p1' ? 'Alice' : 'Bob',
            })),
            spendEnergy,
            refundEnergy,
          };
        },
      } as any,
      MATCH_ROOM: {
        idFromName: (name: string) => ({ toString: () => name } as any),
        get: () => ({
          initMatch: initMatchSpy,
        }),
      } as any,
    };

    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => sampleQuestions),
    };

    return { env: env as Env, spendEnergy, refundEnergy, initMatchSpy, mockProvider };
  }

  it('1. Karşılıklı engel varsa maç kurulmaz ve blocked hatası döner', async () => {
    const mockState = createMockDOState();
    const { env, mockProvider } = createMockEnv({ p1Blocked: ['p2'] });
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'ranked',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe('blocked');
    }
  });

  it('2. Hesap silinmişse maç kurulmaz ve account_deleted hatası döner', async () => {
    const mockState = createMockDOState();
    const { env, mockProvider } = createMockEnv({ p2Deleted: true });
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'ranked',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe('account_deleted');
    }
  });

  it('3. Ranked maçta p1 enerjisi yetersizse harcama yapılmaz ve no_energy döner', async () => {
    const mockState = createMockDOState();
    const { env, spendEnergy, refundEnergy, mockProvider } = createMockEnv({ p1EnergySuccess: false });
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'ranked',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe('no_energy');
    }
    expect(spendEnergy).toHaveBeenCalledTimes(1);
    expect(refundEnergy).not.toHaveBeenCalled();
  });

  it('4. Ranked maçta p1 enerjisi başarılı ancak p2 yetersizse: p1 enerjisi iade edilir ve opponent_no_energy döner', async () => {
    const mockState = createMockDOState();
    const { env, spendEnergy, refundEnergy, mockProvider } = createMockEnv({
      p1EnergySuccess: true,
      p2EnergySuccess: false,
    });
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'ranked',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe('opponent_no_energy');
    }
    expect(spendEnergy).toHaveBeenCalledTimes(2);
    expect(refundEnergy).toHaveBeenCalledTimes(1);
  });

  it('5. Friendly maçta enerji harcanmaz', async () => {
    const mockState = createMockDOState();
    const { env, spendEnergy, mockProvider } = createMockEnv();
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'friendly',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.isFriendly).toBe(true);
    }
    expect(spendEnergy).not.toHaveBeenCalled();
  });

  it('6. Rematch ile kurulan yeni maçta initMatch parametresinde isRematch: true geçilir', async () => {
    const mockState = createMockDOState();
    const { env, initMatchSpy, mockProvider } = createMockEnv();
    const matchmaker = new Matchmaker(mockState as any, env, mockProvider);

    const result = await matchmaker.createDirectMatch({
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      matchType: 'ranked',
      prevMatchId: 'prev-1',
      proposerUid: 'p1',
    });

    expect(result.ok).toBe(true);
    expect(initMatchSpy).toHaveBeenCalledTimes(1);
    const callArgs = initMatchSpy.mock.calls[0][0];
    expect(callArgs.isRematch).toBe(true);
    expect(callArgs.matchType).toBe('ranked');
  });

  it('7. Ranked rövanş maçında isRematch: true verildiğinde connect timeout 15 saniyedir', async () => {
    const fixedNow = 1_700_000_000_000;
    vi.setSystemTime(fixedNow);

    const { ctx, store, getAlarm } = createMockRoomCtx();
    const env = { FAST_TIMERS: 'false' } as Env;
    const room = new MatchRoom(ctx, env);

    // Initialise ranked rematch room
    await room.initMatch({
      matchId: 'match_rematch_ranked',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: sampleQuestions,
      questionOrder: sampleQuestions.map((q) => q.id),
      matchType: 'ranked',
      isRematch: true,
    });

    const roomData = store.get('roomData');
    expect(roomData).toBeDefined();
    // In normal ranked, this would be 10000ms. In rematch, it must be 15000ms!
    expect(roomData.schedule.connectTimeoutAtMs).toBe(fixedNow + 15000);
    expect(getAlarm()).toBe(fixedNow + 15000);
  });

  it('8. validateRematchRequest doğrulama kuralları: durum, oyuncular, bot, bitiş şekli ve tekillik', async () => {
    // A) Oda henüz başlatılmamış / veri yok
    const { ctx: emptyCtx } = createMockRoomCtx();
    const emptyRoom = new MatchRoom(emptyCtx, {} as Env);
    const resEmpty = await emptyRoom.validateRematchRequest('p1', 'p2');
    expect(resEmpty).toEqual({ ok: false, error: 'not_found' });

    // B) Henüz bitmemiş maç
    const { ctx: progCtx } = createMockRoomCtx();
    const progRoom = new MatchRoom(progCtx, { FAST_TIMERS: 'false' } as Env);
    await progRoom.initMatch({
      matchId: 'm_prog',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: sampleQuestions,
      questionOrder: sampleQuestions.map((q) => q.id),
      matchType: 'ranked',
    });
    const resProg = await progRoom.validateRematchRequest('p1', 'p2');
    expect(resProg).toEqual({ ok: false, error: 'not_finished' });

    // C) Terk/hükmen ile bitmiş maç
    const { room: forfeitRoom } = await setupFinishedMatch({ forfeit: true });
    const resForfeit = await forfeitRoom.validateRematchRequest('p1', 'p2');
    expect(resForfeit).toEqual({ ok: false, error: 'not_normal_end' });

    // D) Bot maçı
    const { room: botRoom } = await setupFinishedMatch({ bot: true });
    const resBot = await botRoom.validateRematchRequest('p1', 'bot');
    expect(resBot).toEqual({ ok: false, error: 'bot_match' });

    // E) Maçın oyuncusu olmayan yabancı kullanıcılar
    const { room: normalRoom } = await setupFinishedMatch({ matchType: 'ranked' });
    const resStranger = await normalRoom.validateRematchRequest('stranger', 'p2');
    expect(resStranger).toEqual({ ok: false, error: 'invalid_players' });
    const resStranger2 = await normalRoom.validateRematchRequest('p1', 'stranger');
    expect(resStranger2).toEqual({ ok: false, error: 'invalid_players' });
    const resSelf = await normalRoom.validateRematchRequest('p1', 'p1');
    expect(resSelf).toEqual({ ok: false, error: 'invalid_players' });

    // F) Geçerli normal rankli maç: ilk çağrı başarılı döner ve türü devralır
    const resOk = await normalRoom.validateRematchRequest('p1', 'p2');
    expect(resOk).toEqual({ ok: true, matchType: 'ranked' });

    // İstek başarıyla iletildikten sonra oda işaretlenir
    await normalRoom.markRematchRequestCreated();

    // G) Aynı maç için ikinci kez istek atılamaz (tekillik kuralı)
    const resSecond = await normalRoom.validateRematchRequest('p1', 'p2');
    expect(resSecond).toEqual({ ok: false, error: 'already_requested' });

    // H) Friendly maç türünün devralınması
    const { room: friendlyRoom } = await setupFinishedMatch({ matchType: 'friendly' });
    const resFriendly = await friendlyRoom.validateRematchRequest('p2', 'p1');
    expect(resFriendly).toEqual({ ok: true, matchType: 'friendly' });
  });
});
