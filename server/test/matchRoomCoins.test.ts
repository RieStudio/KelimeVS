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

describe('MatchRoom Coin Reward Tolerance and Retries', () => {
  it('1. Ödül çağrısı başarılı olduğunda final mesajına coinsAwarded ve coins eklenir', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentMessages: string[] = [];
    const mockSocket = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => sentMessages.push(txt),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: () => {},
      close: () => {},
    };
    sockets.push(mockSocket, mockSocketBob);

    let p1RewardCalled = false;
    let p2RewardCalled = false;

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          if (uid === 'alice') p1RewardCalled = true;
          if (uid === 'bob') p2RewardCalled = true;
          return { coinsAwarded: 30, coins: 130 };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    // Oyuncular bağlanır ve maç başlar
    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // Maç biter ve ödül çağrılır
    await (room as any).handleMatchFinished();

    expect(p1RewardCalled).toBe(true);
    expect(p2RewardCalled).toBe(true);

    const finalMsg = sentMessages
      .map((s) => JSON.parse(s))
      .find((m) => m.t === 'final');
    expect(finalMsg).toBeDefined();
    expect(finalMsg.coinsAwarded).toBe(30);
    expect(finalMsg.coins).toBe(130);
  });

  it('2. Kural 4: applyMatchReward başarısız olursa final mesajı yine de gider, alarm kurulur ve tekrar denendiğinde kaydedilir', async () => {
    const { ctx, sockets, getAlarm, store } = createMockRoomCtx();
    const sentMessages: string[] = [];
    const mockSocket = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => sentMessages.push(txt),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: () => {},
      close: () => {},
    };
    sockets.push(mockSocket, mockSocketBob);

    let shouldFail = true;

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (_uid: string) => ({
        applyMatchReward: async () => {
          if (shouldFail) {
            throw new Error('Durable Object temporary error');
          }
          return { coinsAwarded: 30, coins: 130 };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_retry_test',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    // Oyuncular bağlanır ve maç başlar
    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // Maç biter (ödül servisi geçici olarak hata verir)
    await (room as any).handleMatchFinished();

    // Final mesajı yine de gitmeli (coins olmadan)
    const finalMsgInitial = sentMessages
      .map((s) => JSON.parse(s))
      .find((m) => m.t === 'final');
    expect(finalMsgInitial).toBeDefined();
    expect(finalMsgInitial.coinsAwarded).toBeUndefined();
    expect(finalMsgInitial.coins).toBeUndefined();

    // Alarm kurulmuş olmalı (rewardRetryAtMs)
    const alarmTime = getAlarm();
    expect(alarmTime).toBeGreaterThan(Date.now() - 100);

    const roomData = store.get('roomData');
    expect(roomData.schedule.rewardRetryAtMs).toBeDefined();
    expect(roomData.rewardRetryCount).toBe(1);

    // Şimdi servis düzelir, alarm zamanı gelir ve alarm tetiklenir
    shouldFail = false;
    roomData.schedule = {
      ...roomData.schedule,
      rewardRetryAtMs: Date.now() - 10,
    };
    await (room as any).alarm();

    // Başarılı ödül kaydedilmiş olmalı
    const updatedRoomData = store.get('roomData');
    expect(updatedRoomData.rewards).toBeDefined();
    expect(updatedRoomData.rewards.alice).toEqual({ coinsAwarded: 30, coins: 130 });
    expect(updatedRoomData.schedule.rewardRetryAtMs).toBeUndefined();

    // Oyuncu sonradan yeniden bağlandığında final aldığında saklanan coinsAwarded ve coins yer alır
    sentMessages.length = 0;
    (room as any).sendFinalToPlayer('alice');

    const reconnectedFinal = sentMessages
      .map((s) => JSON.parse(s))
      .find((m) => m.t === 'final');
    expect(reconnectedFinal).toBeDefined();
    expect(reconnectedFinal.coinsAwarded).toBe(30);
    expect(reconnectedFinal.coins).toBe(130);
  });
});
