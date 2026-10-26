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
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

function createMockSocket(tag: string, sent: any[] = []) {
  let attachment: any = null;
  return {
    tag,
    send: (data: string) => sent.push(JSON.parse(data)),
    deserializeAttachment: () => attachment,
    serializeAttachment: (val: any) => {
      attachment = val;
    },
    close: () => {},
  };
}

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

function createMockEnv(refundFn?: any) {
  return {
    FAST_TIMERS: 'true',
    USER_PROFILE: {
      idFromName(name: string) {
        return name;
      },
      get(id: string) {
        return {
          async applyMatchReward() {
            return { coinsAwarded: 10, coins: 110 };
          },
          async refundEnergy(params: any) {
            if (refundFn) return refundFn(params);
            return { ok: true, refunded: true, energy: 5 };
          },
        };
      },
    },
    LEADERBOARD: {
      idFromName(name: string) {
        return name;
      },
      get() {
        return {
          async recordMatchResult() {
            return { ok: true };
          },
        };
      },
    },
  } as unknown as Env;
}

describe('MatchRoom Forfeit Energy Refund Tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('1. Rakip açıkça terk ettiğinde (leave): kalan oyuncu energyChargedUids içinde ise 1 enerji iade edilir', async () => {
    const refundMock = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const { ctx, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'm1',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      energyChargedUids: ['p1', 'p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p2 maçı terk eder (leave) -> p1 kazanır
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'leave' }));

    // p1 için refundEnergy çağrılmalı, terk eden p2 için çağrılmamalı
    expect(refundMock).toHaveBeenCalledTimes(1);
    expect(refundMock).toHaveBeenCalledWith(
      expect.objectContaining({
        matchId: 'm1',
        amount: 1,
        uid: 'p1',
      })
    );
  });

  it('2. Rakip koptuktan sonra 30 sn dolunca (disconnectForfeit): kalan oyuncuya enerji iade edilir', async () => {
    const refundMock = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const { ctx, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'm2',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      energyChargedUids: ['p1', 'p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p2 bağlantısı kopar
    const ws2Index = sockets.indexOf(ws2);
    if (ws2Index !== -1) sockets.splice(ws2Index, 1);
    await room.webSocketClose(ws2 as any, 1006, 'abnormal');

    // Süre ilerletilir (FAST_TIMERS'ta 3 sn disconnect süresi)
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // p1'e 1 enerji iade edilir
    expect(refundMock).toHaveBeenCalledTimes(1);
    expect(refundMock).toHaveBeenCalledWith(
      expect.objectContaining({
        matchId: 'm2',
        uid: 'p1',
      })
    );
  });

  it('3. Normal süre aşımında (turnTimeout): terk sayılmaz, enerji iadesi YAPILMAZ', async () => {
    const refundMock = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const { ctx, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'm3',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      energyChargedUids: ['p1', 'p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Sırası gelen oyuncu cevap vermez, turnTimeout süresi dolar ve alarm tetiklenir
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // İade yapılmamalıdır!
    expect(refundMock).not.toHaveBeenCalled();
  });

  it('4. Kalan oyuncu enerjiye tabi değilse (energyChargedUids içinde yoksa): iade YAPILMAZ', async () => {
    const refundMock = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const { ctx, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    // Yalnızca p2 için enerji düşülmüştü (karışık durum: p1 enerji kapalı)
    await room.initMatch({
      matchId: 'm4',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      energyChargedUids: ['p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p2 terk eder, p1 kazanır; ancak p1 enerji harcamadığı için iade yapılmaz
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'leave' }));

    expect(refundMock).not.toHaveBeenCalled();
  });

  it('5. Arkadaş maçı (friendly): terk durumunda bile enerji iadesi YAPILMAZ', async () => {
    const refundMock = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const { ctx, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'm5',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      matchType: 'friendly',
      energyChargedUids: ['p1', 'p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'leave' }));

    expect(refundMock).not.toHaveBeenCalled();
  });

  it('6. İade ilk denemede geçici hata verirse alarm ile yeniden denenir', async () => {
    let callCount = 0;
    const refundMock = vi.fn(async () => {
      callCount++;
      if (callCount === 1) {
        throw new Error('Durable Object temporary error');
      }
      return { ok: true, refunded: true, energy: 5 };
    });

    const { ctx, store, sockets } = createMockRoomCtx();
    const env = createMockEnv(refundMock);
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'm6',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      energyChargedUids: ['p1', 'p2'],
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p2 terk eder
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'leave' }));

    // İlk deneme başarısız olunca alarm kurulmuş olmalı
    expect(callCount).toBe(1);
    const roomData = store.get('roomData');
    expect(roomData.pendingEnergyRefundUids).toEqual(['p1']);
    expect(roomData.schedule.energyRefundRetryAtMs).toBeDefined();

    // Alarm süresi ilerletilir ve tetiklenir
    vi.advanceTimersByTime(2000);
    await room.alarm();

    // İkinci deneme başarılı olmalı
    expect(callCount).toBe(2);
    const updatedRoomData = store.get('roomData');
    expect(updatedRoomData.pendingEnergyRefundUids).toBeUndefined();
    expect(updatedRoomData.schedule.energyRefundRetryAtMs).toBeUndefined();
  });
});

