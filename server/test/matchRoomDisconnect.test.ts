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

import {
  MatchRoom,
  migrateStoredRoomData,
  computeNextDisconnectTimeout,
} from '../src/matchRoom';
import type { Question } from '../src/engine';
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
      acceptWebSocket(ws: any, tags?: string[]) {
        if (tags && tags[0]) ws.tag = tags[0];
        sockets.push(ws);
      },
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

describe('MatchRoom Disconnect State Machine & EK ŞART Tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('Helper Functions & Migration', () => {
    it('computeNextDisconnectTimeout returns earliest future timeout and ignores past timeouts', () => {
      const nowMs = 10000;
      expect(computeNextDisconnectTimeout(undefined, nowMs)).toBeUndefined();
      expect(computeNextDisconnectTimeout({}, nowMs)).toBeUndefined();

      // Only expired
      expect(
        computeNextDisconnectTimeout({ p1: 9000, p2: 10000 }, nowMs)
      ).toBeUndefined();

      // One expired, one future
      expect(
        computeNextDisconnectTimeout({ p1: 8000, p2: 15000 }, nowMs)
      ).toBe(15000);

      // Both future
      expect(
        computeNextDisconnectTimeout({ p1: 20000, p2: 12000 }, nowMs)
      ).toBe(12000);
    });

    it('migrateStoredRoomData safely migrates legacy disconnectedUid and pendingEnergyRefundUid', () => {
      const legacy = {
        matchId: 'm1',
        disconnectedUid: 'p1',
        pendingEnergyRefundUid: 'p2',
        schedule: { disconnectTimeoutAtMs: 50000 },
      };

      const migrated = migrateStoredRoomData(legacy);
      expect(migrated).not.toBeNull();
      expect(migrated!.disconnectedUids).toEqual({ p1: 50000 });
      expect(migrated!.pendingEnergyRefundUids).toEqual(['p2']);
      expect((migrated as any).disconnectedUid).toBeUndefined();
      expect((migrated as any).pendingEnergyRefundUid).toBeUndefined();
    });
  });

  describe('Scenario 1: Single Player Disconnect', () => {
    it('P1 disconnects, P2 stays connected: at 3s P1 forfeits, P2 wins and receives forfeit energy refund', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const logs: string[] = [];
      const logSpy = vi.spyOn(console, 'log').mockImplementation((msg: string) => {
        logs.push(msg);
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm1',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      const roomDataActive = store.get('roomData');
      expect(roomDataActive.status).toBe('active');

      // P1 disconnects
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      const roomDataAfterClose = store.get('roomData');
      expect(roomDataAfterClose.disconnectedUids).toBeDefined();
      expect(roomDataAfterClose.disconnectedUids['p1']).toBeDefined();
      expect(roomDataAfterClose.disconnectedUids['p2']).toBeUndefined();

      // FAST_TIMERS disconnect timeout is 3000ms
      vi.advanceTimersByTime(3000);
      await room.alarm();

      const finalRoomData = store.get('roomData');
      expect(finalRoomData.status).toBe('finished');

      // P2 should be winner, P1 forfeited
      expect(refundedUids).toContain('p2'); // Winner gets forfeit energy refund
      expect(refundedUids).not.toContain('p1'); // Forfeiter does not get energy refund

      // Structured log verification (without UIDs)
      const forfeitLog = logs.find((l) => l.includes('disconnect_forfeit'));
      expect(forfeitLog).toBeDefined();
      const parsedLog = JSON.parse(forfeitLog!);
      expect(parsedLog.event).toBe('disconnect_forfeit');
      expect(parsedLog.matchId).toBe('m1');
      expect(parsedLog.forfeiterIndex).toBe(1);
      expect((parsedLog as any).uid).toBeUndefined();

      logSpy.mockRestore();
    });
  });

  describe('Scenario 2: Sequential Disconnects resulting in Voided', () => {
    it('P1 disconnects at t=0, P2 at t=1s: alarm at t=3s waits; alarm at t=4s voids match and refunds both', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const logs: string[] = [];
      const logSpy = vi.spyOn(console, 'log').mockImplementation((msg: string) => {
        logs.push(msg);
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm2',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // t=0: P1 disconnects (deadline t0 + 3000)
      const t0 = Date.now();
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');

      // t=1000: P2 disconnects (deadline t0 + 4000)
      vi.advanceTimersByTime(1000);
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      const roomDataBothDisc = store.get('roomData');
      expect(roomDataBothDisc.disconnectedUids['p1']).toBe(t0 + 3000);
      expect(roomDataBothDisc.disconnectedUids['p2']).toBe(t0 + 4000);
      // Turn timer must be frozen!
      expect(roomDataBothDisc.schedule.turnDeadlineMs).toBeUndefined();
      expect(roomDataBothDisc.frozenTurnRemainingMs).toBeDefined();

      // Advance to t=3000 (P1 deadline expires, but P2 deadline is 4000)
      vi.advanceTimersByTime(2000);
      await room.alarm();

      // At t=3000, match is NOT finished and NOT voided yet: it is waiting for P2!
      const roomDataAt3s = store.get('roomData');
      expect(roomDataAt3s.status).toBe('active');
      expect(roomDataAt3s.schedule.disconnectTimeoutAtMs).toBe(t0 + 4000);

      // Advance to t=4000 (P2 deadline also expires)
      vi.advanceTimersByTime(1000);
      await room.alarm();

      // At t=4000, both expired -> Match voided!
      const roomDataAt4s = store.get('roomData');
      expect(roomDataAt4s.status).toBe('voided');
      expect(roomDataAt4s.voidedReason).toBe('both_disconnected');

      // BOTH players refunded!
      expect(refundedUids).toContain('p1');
      expect(refundedUids).toContain('p2');

      // Structured log verification
      const voidLog = logs.find((l) => l.includes('match_voided'));
      expect(voidLog).toBeDefined();
      const parsedVoid = JSON.parse(voidLog!);
      expect(parsedVoid.event).toBe('match_voided');
      expect(parsedVoid.reason).toBe('both_disconnected');
      expect(parsedVoid.matchId).toBe('m2');
      expect(parsedVoid.roundsPlayed).toBe(0);
      expect((parsedVoid as any).uid).toBeUndefined();

      logSpy.mockRestore();
    });
  });

  describe('Scenario 3: Simultaneous Disconnects', () => {
    it('Both players disconnect at t=0: at t=3s match is voided (both_disconnected) and both refunded', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm3',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      vi.advanceTimersByTime(3000);
      await room.alarm();

      const roomData = store.get('roomData');
      expect(roomData.status).toBe('voided');
      expect(roomData.voidedReason).toBe('both_disconnected');
      expect(refundedUids).toEqual(expect.arrayContaining(['p1', 'p2']));
    });
  });

  describe('Scenario 4: P1 returns after their timeout passed while P2 is still disconnected and unexpired', () => {
    it('P1 returns at t=3500ms (P1 deadline 3000ms was expired, P2 deadline 4000ms not expired): match continues, turn resumes, and P2 forfeits at 4000ms', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm4',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // t=0: P1 disconnects (deadline t0 + 3000)
      const t0 = Date.now();
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      // t=1000: P2 disconnects (deadline t0 + 4000)
      vi.advanceTimersByTime(1000);
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      // t=3000: P1's deadline expires, DO alarm runs and waits for P2
      vi.advanceTimersByTime(2000);
      await room.alarm();

      // t=3500: P1 reconnects!
      vi.advanceTimersByTime(500);
      const ws1New = createMockSocket('p1');
      sockets.push(ws1New);
      await (room as any).handlePlayerConnected('p1');

      // P1 record removed, P2 still disconnected
      const roomDataAfterP1Return = store.get('roomData');
      expect(roomDataAfterP1Return.status).toBe('active');
      expect(roomDataAfterP1Return.disconnectedUids['p1']).toBeUndefined();
      expect(roomDataAfterP1Return.disconnectedUids['p2']).toBe(t0 + 4000);
      // Turn timer resumed
      expect(roomDataAfterP1Return.schedule.turnDeadlineMs).toBeGreaterThan(3500);

      // t=4000: P2 deadline arrives -> P2 forfeits, P1 wins!
      vi.advanceTimersByTime(500);
      await room.alarm();

      const finalRoomData = store.get('roomData');
      expect(finalRoomData.status).toBe('finished');
      expect(refundedUids).toContain('p1'); // P1 won by forfeit
      expect(refundedUids).not.toContain('p2');
    });
  });

  describe('Scenario 5: P2 returns after P1 deadline already expired while both were absent', () => {
    it('P2 returns at t=3500ms (P1 deadline 3000ms already expired): P1 is immediately forfeited on P2 return', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const logs: string[] = [];
      const logSpy = vi.spyOn(console, 'log').mockImplementation((msg: string) => {
        logs.push(msg);
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm5',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // t=0: P1 disconnects (deadline 3000)
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      // t=1000: P2 disconnects (deadline 4000)
      vi.advanceTimersByTime(1000);
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      // t=3000: Alarm runs and waits
      vi.advanceTimersByTime(2000);
      await room.alarm();

      // t=3500: P2 reconnects! Since P1 was expired, P1 forfeits immediately
      vi.advanceTimersByTime(500);
      const ws2New = createMockSocket('p2');
      sockets.push(ws2New);
      await (room as any).handlePlayerConnected('p2');

      const roomData = store.get('roomData');
      expect(roomData.status).toBe('finished');
      expect(refundedUids).toContain('p2'); // P2 wins
      expect(refundedUids).not.toContain('p1');

      const forfeitLog = logs.find((l) => l.includes('disconnect_forfeit'));
      expect(forfeitLog).toBeDefined();
      const parsedLog = JSON.parse(forfeitLog!);
      expect(parsedLog.forfeiterIndex).toBe(1);

      logSpy.mockRestore();
    });
  });

  describe('Scenario 6: Both disconnect at t=0, P1 returns before deadline at 2.9s', () => {
    it('P1 returns at 2.9s, turn resumes, P2 expires at 3.0s and forfeits', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm6',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      // Advance to 2900ms (100ms before 3000ms deadline)
      vi.advanceTimersByTime(2900);
      const ws1New = createMockSocket('p1');
      sockets.push(ws1New);
      await (room as any).handlePlayerConnected('p1');

      // Advance 100ms to 3000ms -> P2 expires
      vi.advanceTimersByTime(100);
      await room.alarm();

      const finalRoomData = store.get('roomData');
      expect(finalRoomData.status).toBe('finished');
      expect(refundedUids).toContain('p1');
      expect(refundedUids).not.toContain('p2');
    });
  });

  describe('EK ŞART: Both players disconnected turn timer behavior', () => {
    it('iki oyuncu kopuk, tur süresi doluyor -> tur sonucu yok; iki taraf kopukken maç 2-0 ile bitemez', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const env = createMockEnv();

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm_ek',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // Both disconnect at t=0
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      // Fast timers: answerSeconds = 3s (3000ms), disconnectTimeoutMs = 3000ms.
      // Let's verify that turn timer was frozen:
      const initialStore = store.get('roomData');
      expect(initialStore.schedule.turnDeadlineMs).toBeUndefined();
      expect(initialStore.frozenTurnRemainingMs).toBeDefined();

      // If we advance by 2000ms and manually trigger alarm for turnTimeout (defensive check)
      vi.advanceTimersByTime(2000);
      await room.alarm();

      // Match state should NOT have advanced rounds or awarded points
      const middleData = store.get('roomData');
      expect(middleData.status).toBe('active');

      // Advance past 3000ms -> both disconnect timeouts expire, match voids rather than ending 2-0
      vi.advanceTimersByTime(1000);
      await room.alarm();

      const voidedData = store.get('roomData');
      expect(voidedData.status).toBe('voided');
      expect(voidedData.voidedReason).toBe('both_disconnected');
    });

    it('biri dönünce tur dondurulan süreyle devam eder', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const env = createMockEnv();

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm_resume',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // Both disconnect at t=0
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      const frozenRemaining = store.get('roomData').frozenTurnRemainingMs;
      expect(frozenRemaining).toBeGreaterThan(0);

      // Advance to 1000ms and P1 reconnects
      vi.advanceTimersByTime(1000);
      const ws1New = createMockSocket('p1');
      sockets.push(ws1New);
      await (room as any).handlePlayerConnected('p1');

      const resumedData = store.get('roomData');
      expect(resumedData.status).toBe('active');
      expect(resumedData.frozenTurnRemainingMs).toBeUndefined();
      expect(resumedData.schedule.turnDeadlineMs).toBeGreaterThanOrEqual(1000 + frozenRemaining);
    });
  });

  describe('Scenario 8: connectTimeout and Voided Reconnect', () => {
    it('connectTimeout voids waiting room (opponent_absent) and refunds energy', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refundedUids: string[] = [];
      const env = createMockEnv((params: any) => {
        refundedUids.push(params.uid);
        return { ok: true, refunded: true, energy: 5 };
      });

      const logs: string[] = [];
      const logSpy = vi.spyOn(console, 'log').mockImplementation((msg: string) => {
        logs.push(msg);
      });

      const room = new MatchRoom(ctx, env);
      await room.initMatch({
        matchId: 'm_void',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        energyChargedUids: ['p1', 'p2'],
      });

      // Only P1 connects, P2 never arrives
      const ws1 = createMockSocket('p1');
      sockets.push(ws1);
      await (room as any).handlePlayerConnected('p1');

      expect(store.get('roomData').status).toBe('waiting_for_players');

      // FAST_TIMERS connectTimeout is 3000ms
      vi.advanceTimersByTime(3000);
      await room.alarm();

      const voidedData = store.get('roomData');
      expect(voidedData.status).toBe('voided');
      expect(voidedData.voidedReason).toBe('opponent_absent');

      // Both refunded
      expect(refundedUids).toContain('p1');
      expect(refundedUids).toContain('p2');

      // Structured log
      const voidLog = logs.find((l) => l.includes('match_voided'));
      expect(voidLog).toBeDefined();
      const parsedLog = JSON.parse(voidLog!);
      expect(parsedLog.event).toBe('match_voided');
      expect(parsedLog.reason).toBe('opponent_absent');
      expect(parsedLog.roundsPlayed).toBe(0);

      logSpy.mockRestore();
    });

    it('reconnecting to an already-voided room delivers { t: voided } message via WebSocket', async () => {
      const { ctx, store } = createMockRoomCtx();
      const env = createMockEnv();

      // Pre-set room in voided state
      store.set('roomData', {
        matchId: 'm_voided_existing',
        p1: { uid: 'p1', name: 'Player 1' },
        p2: { uid: 'p2', name: 'Player 2' },
        questions: [sampleQuestion],
        questionOrder: ['q1'],
        status: 'voided',
        voidedReason: 'both_disconnected',
        schedule: { cleanupAtMs: Date.now() + 600000 },
      });

      // Mock WebSocketPair for CF DO environment
      let sentToClient: any[] = [];
      let closedCode: number | null = null;
      let closedReason: string | null = null;

      const mockServerWs = {
        send: (text: string) => sentToClient.push(JSON.parse(text)),
        close: (code: number, reason: string) => {
          closedCode = code;
          closedReason = reason;
        },
      };
      const mockClientWs = {};

      (globalThis as any).WebSocketPair = class {
        0 = mockClientWs;
        1 = mockServerWs;
      };

      const OriginalResponse = globalThis.Response;
      (globalThis as any).Response = class MockResponse {
        body: any;
        status: number;
        webSocket: any;
        constructor(body: any, init?: any) {
          this.body = body;
          this.status = init?.status ?? 200;
          this.webSocket = init?.webSocket;
        }
      };

      try {
        const room = new MatchRoom(ctx, env);
        await Promise.resolve();
        await Promise.resolve();
        const req = new Request('http://localhost/ws/match/m_voided_existing', {
          headers: {
            Upgrade: 'websocket',
            'X-User-Id': 'p1',
          },
        });

        const res = await room.fetch(req);
        expect(res.status).toBe(101);
        expect(sentToClient).toEqual([{ t: 'voided', reason: 'both_disconnected' }]);
        expect(closedCode).toBe(1000);
        expect(closedReason).toBe('voided');
      } finally {
        globalThis.Response = OriginalResponse;
      }
    });
  });
});
