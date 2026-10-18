import { describe, expect, it, vi } from 'vitest';

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
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

function createMockRoomCtx() {
  const store = new Map<string, any>();
  const sockets: any[] = [];
  let alarmTime: number | null = null;

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
        return fn();
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets;
        return sockets.filter((s) => s.tag === tag);
      },
      acceptWebSocket() {},
    } as unknown as DurableObjectState,
    store,
    sockets,
    getAlarm: () => alarmTime,
  };
}

const sampleQuestion: Question = {
  id: 'q1',
  categoryId: 'c1',
  text: 'Soru 1',
  answers: [{ id: 'a1', display: 'Cevap 1', aliases: ['cevap1'] }],
};

describe('MatchRoom Leaderboard Integration & Hibernation Resilience', () => {
  it('1. Maç bitince Leaderboard DO çağrılır, UserProfile takma adı kullanılır (kuyruk adı değil)', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const mockSocketAlice = { tag: 'alice', readyState: 1, send: () => {}, close: () => {} };
    const mockSocketBob = { tag: 'bob', readyState: 1, send: () => {}, close: () => {} };
    sockets.push(mockSocketAlice, mockSocketBob);

    let recordedParams: any = null;

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          // Kuyruktaki adı değil, UserProfile'daki adı dönüyor
          const nick = uid === 'alice' ? 'AliceProfileNick' : 'BobProfileNick';
          return { coinsAwarded: 30, coins: 130, nickname: nick };
        },
      }),
    };

    const mockLeaderboard = {
      idFromName: (name: string) => name,
      get: () => ({
        recordMatchResult: async (params: any) => {
          recordedParams = params;
          return { ok: true };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      LEADERBOARD: mockLeaderboard,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_lb_test_1',
      p1: { uid: 'alice', name: 'QueueNameAlice' },
      p2: { uid: 'bob', name: 'QueueNameBob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // Alice kazanacak şekilde simüle et
    const state = (room as any).data.engineState;
    (room as any).data = {
      ...(room as any).data,
      engineState: {
        ...state,
        winnerId: 'alice',
      },
    };

    await (room as any).handleMatchFinished();

    expect(recordedParams).toBeDefined();
    expect(recordedParams.matchId).toBe('match_lb_test_1');
    expect(recordedParams.winnerUid).toBe('alice');
    expect(recordedParams.winnerNickname).toBe('AliceProfileNick'); // QueueNameAlice DEĞİL!
    expect(recordedParams.loserUid).toBe('bob');
    expect(recordedParams.loserNickname).toBe('BobProfileNick');

    const roomData = (room as any).data;
    expect(roomData.leaderboardPending).toBe(false);
  });

  it('2. Leaderboard hatasında leaderboardPending kalıcı duruma kaydedilir, alarm ve hibernation sonrası tekrar denenir', async () => {
    const { ctx, store, sockets, getAlarm } = createMockRoomCtx();
    const mockSocketAlice = { tag: 'alice', readyState: 1, send: () => {}, close: () => {} };
    const mockSocketBob = { tag: 'bob', readyState: 1, send: () => {}, close: () => {} };
    sockets.push(mockSocketAlice, mockSocketBob);

    let shouldFail = true;
    let recordedParams: any = null;

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          const nick = uid === 'alice' ? 'AliceProfileNick' : 'BobProfileNick';
          return { coinsAwarded: 30, coins: 130, nickname: nick };
        },
      }),
    };

    const mockLeaderboard = {
      idFromName: (name: string) => name,
      get: () => ({
        recordMatchResult: async (params: any) => {
          if (shouldFail) {
            throw new Error('Leaderboard DO temporarily unavailable');
          }
          recordedParams = params;
          return { ok: true };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      LEADERBOARD: mockLeaderboard,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_lb_retry_test',
      p1: { uid: 'alice', name: 'QueueNameAlice' },
      p2: { uid: 'bob', name: 'QueueNameBob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    const state = (room as any).data.engineState;
    (room as any).data = {
      ...(room as any).data,
      engineState: {
        ...state,
        winnerId: 'alice',
      },
    };

    // Maç biter, Leaderboard hatası fırlatılır
    await (room as any).handleMatchFinished();

    // Kalıcı durumda leaderboardPending: true olmalı ve alarm kurulmalı
    const persistedInitial = store.get('roomData');
    expect(persistedInitial.leaderboardPending).toBe(true);
    expect(persistedInitial.leaderboardRetryCount).toBe(1);
    expect(persistedInitial.schedule.leaderboardRetryAtMs).toBeDefined();

    const alarmTime = getAlarm();
    expect(alarmTime).toBeGreaterThan(Date.now() - 100);

    // Hibernation simülasyonu: Yeni bir MatchRoom örneği oluşturulur (bellek sıfırlanır, store'dan okunur)
    const hibernatedRoom = new MatchRoom(ctx, env);
    await Promise.resolve();
    await Promise.resolve();
    // ctx.blockConcurrencyWhile ile storage.get('roomData') okunmuş olur
    const hibernatedData = (hibernatedRoom as any).data;
    expect(hibernatedData.leaderboardPending).toBe(true);

    // Şimdi Leaderboard servisi düzelir
    shouldFail = false;
    hibernatedData.schedule = {
      ...hibernatedData.schedule,
      leaderboardRetryAtMs: Date.now() - 10,
    };

    // Alarm çalar
    await (hibernatedRoom as any).alarm();

    // Başarıyla yazılmış ve leaderboardPending: false olarak güncellenmiş olmalı
    expect(recordedParams).toBeDefined();
    expect(recordedParams.matchId).toBe('match_lb_retry_test');
    expect(recordedParams.winnerUid).toBe('alice');

    const persistedAfter = store.get('roomData');
    expect(persistedAfter.leaderboardPending).toBe(false);
    expect(persistedAfter.schedule.leaderboardRetryAtMs).toBeUndefined();
  });
});
