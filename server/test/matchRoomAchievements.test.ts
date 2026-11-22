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
      getTags(ws: any) {
        return ws.tag ? [ws.tag] : [];
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

describe('MatchRoom - Başarımlar (unlockedAchievements) Entegrasyonu', () => {
  it('1. Normal maç bitişinde her oyuncunun kazandığı başarımlar final mesajında iletilir', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          if (uid === 'alice') {
            return {
              coinsAwarded: 30,
              coins: 130,
              unlockedAchievements: ['first_match', 'first_win'],
            };
          }
          return {
            coinsAwarded: 5,
            coins: 105,
            unlockedAchievements: ['first_match'],
          };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_normal_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // Alice doğru cevap verir ve kazanır
    (room as any).data.scores = { alice: 1, bob: 0 };
    await (room as any).handleMatchFinished();

    const aliceFinal = aliceMessages.find((m) => m.t === 'final');
    expect(aliceFinal).toBeDefined();
    expect(aliceFinal.unlockedAchievements).toEqual(['first_match', 'first_win']);

    const bobFinal = bobMessages.find((m) => m.t === 'final');
    expect(bobFinal).toBeDefined();
    expect(bobFinal.unlockedAchievements).toEqual(['first_match']);
  });

  it('2. Hükmen (forfeit) bitişinde kalan oyuncunun final mesajında başarımları yer alır', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    let bobAttachment: any = null;
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      deserializeAttachment: () => bobAttachment,
      serializeAttachment: (val: any) => {
        bobAttachment = val;
      },
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          if (uid === 'alice') {
            return {
              coinsAwarded: 30,
              coins: 130,
              unlockedAchievements: ['streak_3'],
            };
          }
          return { coinsAwarded: 0, coins: 100, unlockedAchievements: [] };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_forfeit_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // Bob odayı terk eder (forfeit)
    await room.webSocketMessage(mockSocketBob as any, JSON.stringify({ t: 'leave' }));

    const aliceFinal = aliceMessages.find((m) => m.t === 'final');
    expect(aliceFinal).toBeDefined();
    expect(aliceFinal.endedBy).toBe('forfeit');
    expect(aliceFinal.unlockedAchievements).toEqual(['streak_3']);
  });

  it('3. Dostluk maçında (matchType: friendly) başarımlar gönderilmez ve UserProfile çağrılmaz', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    let profileCalled = false;
    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: () => ({
        applyMatchReward: async () => {
          profileCalled = true;
          return { coinsAwarded: 0, coins: 100 };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_friendly_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      matchType: 'friendly',
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    await (room as any).handleMatchFinished();

    expect(profileCalled).toBe(false);

    const aliceFinal = aliceMessages.find((m) => m.t === 'final');
    expect(aliceFinal).toBeDefined();
    expect(aliceFinal.unlockedAchievements).toBeUndefined();

    const bobFinal = bobMessages.find((m) => m.t === 'final');
    expect(bobFinal).toBeDefined();
    expect(bobFinal.unlockedAchievements).toBeUndefined();
  });

  it('4. İptal edilen (voided) maçta final mesajı veya başarım gönderilmez', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    let profileCalled = false;
    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: () => ({
        applyMatchReward: async () => {
          profileCalled = true;
          return { coinsAwarded: 0, coins: 100 };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_voided_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    await (room as any).handleDrawLimitVoided(5);

    expect(profileCalled).toBe(false);

    const voidedMsg = aliceMessages.find((m) => m.t === 'voided');
    expect(voidedMsg).toBeDefined();
    expect(voidedMsg.reason).toBe('draw_limit_reached');

    const finalMsg = aliceMessages.find((m) => m.t === 'final');
    expect(finalMsg).toBeUndefined();
  });

  it('5. Maç bittikten sonra yeniden bağlanan (reconnect) oyuncuya saklanan başarımlar eksiksiz tekrar gönderilir', async () => {
    const { ctx, sockets, store } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (uid: string) => ({
        applyMatchReward: async () => {
          return {
            coinsAwarded: 30,
            coins: 130,
            unlockedAchievements: ['first_match', 'first_win'],
          };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_reconnect_test',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');
    await (room as any).handleMatchFinished();

    // roomData.rewards alanında alice için unlockedAchievements saklanmış olmalı
    const roomData = store.get('roomData');
    expect(roomData.rewards.alice.unlockedAchievements).toEqual(['first_match', 'first_win']);

    // Soketi temizleyip sendFinalToPlayer çağırarak reconnect simüle edelim
    aliceMessages.length = 0;
    (room as any).sendFinalToPlayer('alice');

    const reconnectedFinal = aliceMessages.find((m) => m.t === 'final');
    expect(reconnectedFinal).toBeDefined();
    expect(reconnectedFinal.unlockedAchievements).toEqual(['first_match', 'first_win']);
  });

  it('6. Reward retry ile sonradan kazanılan başarımlar saklanır ve reconnect anında oyuncuya iletilir', async () => {
    const { ctx, sockets, store } = createMockRoomCtx();
    const aliceMessages: any[] = [];
    const bobMessages: any[] = [];

    const mockSocketAlice = {
      tag: 'alice',
      readyState: 1,
      send: (txt: string) => aliceMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    const mockSocketBob = {
      tag: 'bob',
      readyState: 1,
      send: (txt: string) => bobMessages.push(JSON.parse(txt)),
      close: () => {},
    };
    sockets.push(mockSocketAlice, mockSocketBob);

    let shouldFail = true;
    const mockUserProfile = {
      idFromName: (name: string) => name,
      get: (_uid: string) => ({
        applyMatchReward: async () => {
          if (shouldFail) {
            throw new Error('Temporary profile DO error');
          }
          return {
            coinsAwarded: 30,
            coins: 130,
            unlockedAchievements: ['wins_10'],
          };
        },
      }),
    };

    const env = {
      USER_PROFILE: mockUserProfile,
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_retry_achievements',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // İlk bitişte applyMatchReward hata verir
    await (room as any).handleMatchFinished();

    const initialFinal = aliceMessages.find((m) => m.t === 'final');
    expect(initialFinal).toBeDefined();
    expect(initialFinal.unlockedAchievements).toBeUndefined();

    // Alarm tetiklensin ve retry başarılı olsun
    shouldFail = false;
    const roomData = store.get('roomData');
    roomData.schedule = {
      ...roomData.schedule,
      rewardRetryAtMs: Date.now() - 10,
    };
    await (room as any).alarm();

    const updatedRoomData = store.get('roomData');
    expect(updatedRoomData.rewards.alice.unlockedAchievements).toEqual(['wins_10']);

    // Reconnect sonrası final mesajı kontrolü
    aliceMessages.length = 0;
    (room as any).sendFinalToPlayer('alice');
    const reconnectedFinal = aliceMessages.find((m) => m.t === 'final');
    expect(reconnectedFinal).toBeDefined();
    expect(reconnectedFinal.unlockedAchievements).toEqual(['wins_10']);
  });
});
