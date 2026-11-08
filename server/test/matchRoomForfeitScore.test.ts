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
  MatchEngine,
  type MatchConfig,
  type Question,
} from '../src/engine';
import { buildFinalMessage } from '../src/storage';
import { MatchRoom } from '../src/matchRoom';
import type { Env } from '../src/index';

const sampleQuestions: Question[] = [
  {
    id: 'q1',
    categoryId: 'c1',
    text: 'Soru 1 (Araba)',
    answers: [
      { id: 'audi', display: 'Audi', aliases: ['audi'] },
      { id: 'bmw', display: 'BMW', aliases: ['bmw'] },
      { id: 'mercedes', display: 'Mercedes', aliases: ['mercedes'] },
    ],
  },
  {
    id: 'q2',
    categoryId: 'c2',
    text: 'Soru 2 (Meyve)',
    answers: [
      { id: 'elma', display: 'Elma', aliases: ['elma'] },
      { id: 'armut', display: 'Armut', aliases: ['armut'] },
      { id: 'muz', display: 'Muz', aliases: ['muz'] },
    ],
  },
  {
    id: 'q3',
    categoryId: 'c3',
    text: 'Soru 3 (Başkent)',
    answers: [
      { id: 'ankara', display: 'Ankara', aliases: ['ankara'] },
      { id: 'paris', display: 'Paris', aliases: ['paris'] },
      { id: 'roma', display: 'Roma', aliases: ['roma'] },
    ],
  },
];

const stdConfig: MatchConfig = {
  roundsToWin: 2,
  answerSeconds: 20,
  graceMs: 500,
  nearMissPerRound: 1,
  minAnswersPerQuestion: 1,
  minSubmitIntervalMs: 600,
  maxAttemptsPerTurn: 25,
};

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
    store,
    sockets,
    ctx: {
      blockConcurrencyWhile: async (fn: () => Promise<void>) => fn(),
      storage: {
        get: async (key: string) => store.get(key),
        put: async (key: string, val: any) => store.set(key, val),
        delete: async (key: string) => store.delete(key),
        setAlarm: async (time: number) => {
          alarmTime = time;
        },
        deleteAlarm: async () => {
          alarmTime = null;
        },
        getAlarm: async () => alarmTime,
      },
      getWebSockets: (tag?: string) => {
        if (!tag) return sockets.filter((s) => !s.isClosed);
        return sockets.filter((s) => s.tag === tag && !s.isClosed);
      },
      getTags: (ws: any) => [ws.tag],
    },
    getAlarm: () => alarmTime,
  };
}

function createMockEnv(refundFn?: any) {
  return {
    FAST_TIMERS: 'true',
    USER_PROFILE: {
      idFromName(name: string) {
        return name;
      },
      get() {
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

describe('Hükmen Sonuç (Forfeit) Skor ve Tutarlılık Testleri', () => {
  describe('1. MatchEngine.forfeit Birim Testleri', () => {
    it('İlk turda terk: kazanan hedef skora (roundsToWin = 2) ulaşır, terk eden 0 olur', () => {
      const startRes = MatchEngine.start({
        config: stdConfig,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        nowMs: 1000,
      });

      expect(startRes.state.scores).toEqual({ p1: 0, p2: 0 });

      // P1 ilk turda terk eder
      const forfeitRes = MatchEngine.forfeit({
        state: startRes.state,
        playerId: 'p1',
        nowMs: 3000,
      });

      expect(forfeitRes.state.phase).toBe('matchFinished');
      expect(forfeitRes.state.winnerId).toBe('p2');
      expect(forfeitRes.state.endedBy).toBe('forfeit');
      // Hükmen sonuç kuralı: kazanan = 2, terk eden = 0
      expect(forfeitRes.state.scores).toEqual({ p2: 2, p1: 0 });
      // roundActive fazında terk edildiği için tura ait RoundRecord history'ye eklenmeli
      expect(forfeitRes.state.roundHistory.length).toBe(1);
      expect(forfeitRes.state.roundHistory[0].reason).toBe('forfeit');
      expect(forfeitRes.state.roundHistory[0].winnerId).toBe('p2');
    });

    it('Terk eden öndeyken terk (1 - 0): terk edenin skoru 0 olur, rakip 2 alır', () => {
      const startRes = MatchEngine.start({
        config: stdConfig,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2', 'q3'],
        nowMs: 1000,
      });

      // P1 round 1'i kazanır
      const submitRes = MatchEngine.submit({
        state: startRes.state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 2000,
        questionsPool: sampleQuestions,
      });
      // Süre biter, round 1'i p1 kazanır (skor: p1: 1, p2: 0)
      const tickRes = MatchEngine.checkTimeout({
        state: submitRes.state,
        nowMs: 23000,
      });
      expect(tickRes.state.phase).toBe('roundEnded');
      expect(tickRes.state.scores).toEqual({ p1: 1, p2: 0 });

      // Round 2 başlar
      const round2Res = MatchEngine.startNextRound({
        state: tickRes.state,
        questions: sampleQuestions,
        nowMs: 24000,
        questionOrder: ['q1', 'q2', 'q3'],
      });
      expect(round2Res.state.phase).toBe('roundActive');

      // P1 öndeyken (1 - 0) terk eder!
      const forfeitRes = MatchEngine.forfeit({
        state: round2Res.state,
        playerId: 'p1',
        nowMs: 26000,
      });

      expect(forfeitRes.state.phase).toBe('matchFinished');
      expect(forfeitRes.state.winnerId).toBe('p2');
      expect(forfeitRes.state.endedBy).toBe('forfeit');
      // Kural: Ne olursa olsun terk eden 0, kazanan roundsToWin (2)
      expect(forfeitRes.state.scores).toEqual({ p2: 2, p1: 0 });
      expect(forfeitRes.state.roundHistory.length).toBe(2);
    });

    it('1 - 1 berabere iken terk: terk eden 0 olur, rakip 2 alır', () => {
      const startRes = MatchEngine.start({
        config: stdConfig,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2', 'q3'],
        nowMs: 1000,
      });

      // Round 1: p1 kazanır
      const sub1 = MatchEngine.submit({
        state: startRes.state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 2000,
        questionsPool: sampleQuestions,
      });
      const end1 = MatchEngine.checkTimeout({ state: sub1.state, nowMs: 23000 });
      expect(end1.state.scores).toEqual({ p1: 1, p2: 0 });

      // Round 2: p2 kazanır
      const r2 = MatchEngine.startNextRound({
        state: end1.state,
        questions: sampleQuestions,
        nowMs: 24000,
        questionOrder: ['q1', 'q2', 'q3'],
      });
      const sub2 = MatchEngine.submit({
        state: r2.state,
        playerId: 'p2',
        rawInput: 'elma',
        nowMs: 25000,
        questionsPool: sampleQuestions,
      });
      const end2 = MatchEngine.checkTimeout({ state: sub2.state, nowMs: 46000 });
      expect(end2.state.scores).toEqual({ p1: 1, p2: 1 });

      // Round 3 başlar
      const r3 = MatchEngine.startNextRound({
        state: end2.state,
        questions: sampleQuestions,
        nowMs: 47000,
        questionOrder: ['q1', 'q2', 'q3'],
      });

      // P1 terk eder
      const forfeitRes = MatchEngine.forfeit({
        state: r3.state,
        playerId: 'p1',
        nowMs: 49000,
      });

      expect(forfeitRes.state.phase).toBe('matchFinished');
      expect(forfeitRes.state.winnerId).toBe('p2');
      // 1-1 iken P1'in skoru 0'a çekilir, P2 2 olur
      expect(forfeitRes.state.scores).toEqual({ p2: 2, p1: 0 });
      expect(forfeitRes.state.roundHistory.length).toBe(3);
    });

    it('roundEnded fazında terk: roundHistory mükerrer tur eklemez, mevcut geçmişi korur', () => {
      const startRes = MatchEngine.start({
        config: stdConfig,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2'],
        nowMs: 1000,
      });

      const sub1 = MatchEngine.submit({
        state: startRes.state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 2000,
        questionsPool: sampleQuestions,
      });
      const end1 = MatchEngine.checkTimeout({ state: sub1.state, nowMs: 23000 });
      expect(end1.state.phase).toBe('roundEnded');
      expect(end1.state.roundHistory.length).toBe(1);

      // Henüz round 2 başlamamışken (roundEnded fazında) P2 terk eder
      const forfeitRes = MatchEngine.forfeit({
        state: end1.state,
        playerId: 'p2',
        nowMs: 23000,
      });

      expect(forfeitRes.state.phase).toBe('matchFinished');
      expect(forfeitRes.state.winnerId).toBe('p1');
      expect(forfeitRes.state.endedBy).toBe('forfeit');
      expect(forfeitRes.state.scores).toEqual({ p1: 2, p2: 0 });
      // roundEnded fazında yeni tur eklenmemeli, 1 tur olarak kalmalı
      expect(forfeitRes.state.roundHistory.length).toBe(1);
    });
  });

  describe('2. buildFinalMessage Skor Doğrulaması', () => {
    it('Final mesajında kazanan ve terk eden oyuncu skorları doğru dağıtılır', () => {
      const startRes = MatchEngine.start({
        config: stdConfig,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        nowMs: 1000,
      });

      const forfeitRes = MatchEngine.forfeit({
        state: startRes.state,
        playerId: 'p1',
        nowMs: 3000,
      });

      // P2 için (kazanan)
      const p2Final = buildFinalMessage({
        state: forfeitRes.state,
        playerUid: 'p2',
        opponentUid: 'p1',
        opponentName: 'P1Name',
      });

      expect(p2Final.winnerIsMe).toBe(true);
      expect(p2Final.scores.me).toBe(2);
      expect(p2Final.scores.opponent).toBe(0);
      expect(p2Final.endedBy).toBe('forfeit');

      // P1 için (terk eden)
      const p1Final = buildFinalMessage({
        state: forfeitRes.state,
        playerUid: 'p1',
        opponentUid: 'p2',
        opponentName: 'P2Name',
      });

      expect(p1Final.winnerIsMe).toBe(false);
      expect(p1Final.scores.me).toBe(0);
      expect(p1Final.scores.opponent).toBe(2);
      expect(p1Final.endedBy).toBe('forfeit');
    });
  });

  describe('3. MatchRoom End-to-End Forfeit & Disconnect Testleri', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('leave mesajı gönderildiğinde hükmen 2 - 0 skoruyla biter ve broadcast edilir', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const env = createMockEnv();
      const room = new MatchRoom(ctx as any, env);

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await room.initMatch({
        matchId: 'm_leave_1',
        p1: { uid: 'p1', name: 'Player1' },
        p2: { uid: 'p2', name: 'Player2' },
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2'],
      });

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // P1 maçı terk eder ({ t: 'leave' })
      await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'leave' }));

      const finalRoomData = store.get('roomData');
      expect(finalRoomData.status).toBe('finished');

      // P2'ye gönderilen final mesajı skorunun 2 - 0 olduğunu doğrula
      const p2FinalMsg = ws2.sent.find((m) => m.t === 'final');
      expect(p2FinalMsg).toBeDefined();
      expect(p2FinalMsg.winnerIsMe).toBe(true);
      expect(p2FinalMsg.scores.me).toBe(2);
      expect(p2FinalMsg.scores.opponent).toBe(0);
      expect(p2FinalMsg.endedBy).toBe('forfeit');

      // P1'e giden final mesajının skoru 0 - 2 olmalı
      const p1FinalMsg = ws1.sent.find((m) => m.t === 'final');
      expect(p1FinalMsg).toBeDefined();
      expect(p1FinalMsg.winnerIsMe).toBe(false);
      expect(p1FinalMsg.scores.me).toBe(0);
      expect(p1FinalMsg.scores.opponent).toBe(2);
      expect(p1FinalMsg.endedBy).toBe('forfeit');
    });

    it('disconnectTimeout (30 sn) dolduğunda disconnectForfeit ile hükmen 2 - 0 sonuç üretilir', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const env = createMockEnv();
      const room = new MatchRoom(ctx as any, env);

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await room.initMatch({
        matchId: 'm_disc_1',
        p1: { uid: 'p1', name: 'Player1' },
        p2: { uid: 'p2', name: 'Player2' },
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2'],
      });

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // P1 kopar
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');

      // 30 sn (FAST_TIMERS'da 3000ms) geçer
      vi.advanceTimersByTime(3000);
      await room.alarm();

      const finalRoomData = store.get('roomData');
      expect(finalRoomData.status).toBe('finished');

      const p2FinalMsg = ws2.sent.find((m) => m.t === 'final');
      expect(p2FinalMsg).toBeDefined();
      expect(p2FinalMsg.winnerIsMe).toBe(true);
      expect(p2FinalMsg.scores.me).toBe(2);
      expect(p2FinalMsg.scores.opponent).toBe(0);
    });

    it('Regresyon: opponent_absent (connectTimeout) iptal (voided) olarak kalır, skor üretilmez', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refunded: string[] = [];
      const env = createMockEnv((params: any) => {
        refunded.push(params.uid);
        return { ok: true, refunded: true };
      });
      const room = new MatchRoom(ctx as any, env);

      const ws1 = createMockSocket('p1');
      sockets.push(ws1);

      await room.initMatch({
        matchId: 'm_void_1',
        p1: { uid: 'p1', name: 'Player1' },
        p2: { uid: 'p2', name: 'Player2' },
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2'],
      });

      // Sadece P1 bağlandı, P2 hiç bağlanmadı
      await (room as any).handlePlayerConnected('p1');

      // FAST_TIMERS connectTimeout (3000ms) dolar
      vi.advanceTimersByTime(3000);
      await room.alarm();

      const roomData = store.get('roomData');
      expect(roomData.status).toBe('voided');
      expect(roomData.voidedReason).toBe('opponent_absent');

      // Final mesajı DEĞİL, voided mesajı gitmeli
      const voidedMsg = ws1.sent.find((m) => m.t === 'voided');
      expect(voidedMsg).toBeDefined();
      expect(voidedMsg.reason).toBe('opponent_absent');

      const finalMsg = ws1.sent.find((m) => m.t === 'final');
      expect(finalMsg).toBeUndefined();
    });

    it('Regresyon: İki oyuncu birden koptuğunda both_disconnected ile iptal olur, hükmen sayılmaz', async () => {
      const { ctx, store, sockets } = createMockRoomCtx();
      const refunded: string[] = [];
      const env = createMockEnv((params: any) => {
        refunded.push(params.uid);
        return { ok: true, refunded: true };
      });
      const room = new MatchRoom(ctx as any, env);

      const ws1 = createMockSocket('p1');
      const ws2 = createMockSocket('p2');
      sockets.push(ws1, ws2);

      await room.initMatch({
        matchId: 'm_void_both',
        p1: { uid: 'p1', name: 'Player1' },
        p2: { uid: 'p2', name: 'Player2' },
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2'],
      });

      await (room as any).handlePlayerConnected('p1');
      await (room as any).handlePlayerConnected('p2');

      // İkisi de kopar
      await room.webSocketClose(ws1 as any, 1001, 'disconnect');
      await room.webSocketClose(ws2 as any, 1001, 'disconnect');

      vi.advanceTimersByTime(3000);
      await room.alarm();

      const roomData = store.get('roomData');
      expect(roomData.status).toBe('voided');
      expect(roomData.voidedReason).toBe('both_disconnected');
    });
  });
});
