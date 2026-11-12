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
  text: 'Meyveler',
  answers: [
    { id: 'a1', display: 'Elma', aliases: ['elma'] },
    { id: 'a2', display: 'Armut', aliases: ['armut'] },
  ],
};

describe('MatchRoom Connect Timeout Management', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('1. Online (hızlı / ranked) maçta connect timeout 10 saniyedir (10000 ms)', async () => {
    const fixedNow = 1_700_000_000_000;
    vi.setSystemTime(fixedNow);

    const { ctx, store, getAlarm } = createMockRoomCtx();
    const env = { FAST_TIMERS: 'false' } as Env;
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'match_online_1',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      matchType: 'ranked',
    });

    const roomData = store.get('roomData');
    expect(roomData).toBeDefined();
    expect(roomData.status).toBe('waiting_for_players');
    expect(roomData.schedule.connectTimeoutAtMs).toBe(fixedNow + 10000);
    expect(getAlarm()).toBe(fixedNow + 10000);
  });

  it('2. Arkadaş maçında (isFriendly / matchType: friendly) connect timeout 15 saniyedir (15000 ms)', async () => {
    const fixedNow = 1_700_000_000_000;
    vi.setSystemTime(fixedNow);

    const { ctx, store, getAlarm } = createMockRoomCtx();
    const env = { FAST_TIMERS: 'false' } as Env;
    const room = new MatchRoom(ctx, env);

    await room.initMatch({
      matchId: 'match_friendly_1',
      p1: { uid: 'p1', name: 'Host' },
      p2: { uid: 'p2', name: 'Guest' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      matchType: 'friendly',
    });

    const roomData = store.get('roomData');
    expect(roomData).toBeDefined();
    expect(roomData.status).toBe('waiting_for_players');
    expect(roomData.schedule.connectTimeoutAtMs).toBe(fixedNow + 15000);
    expect(getAlarm()).toBe(fixedNow + 15000);
  });
});
