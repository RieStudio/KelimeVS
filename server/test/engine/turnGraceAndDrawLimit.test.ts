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

import { MatchEngine, type MatchConfig, type Question } from '../../src/engine';
import { MatchRoom } from '../../src/matchRoom';
import { deserializeMatchState } from '../../src/storage';
import type { Env } from '../../src/index';

const sampleQuestions: Question[] = [
  {
    id: 'q1',
    category: 'genel_kultur',
    text: 'Soru 1',
    answers: [{ id: 'a1', display: 'Ankara', aliases: ['ankara'] }],
  },
  {
    id: 'q2',
    category: 'genel_kultur',
    text: 'Soru 2',
    answers: [{ id: 'a2', display: 'Cevap 2', aliases: ['cevap2'] }],
  },
  {
    id: 'q3',
    category: 'genel_kultur',
    text: 'Soru 3',
    answers: [{ id: 'a3', display: 'Cevap 3', aliases: ['cevap3'] }],
  },
  {
    id: 'q4',
    category: 'genel_kultur',
    text: 'Soru 4',
    answers: [{ id: 'a4', display: 'Cevap 4', aliases: ['cevap4'] }],
  },
  {
    id: 'q5',
    category: 'genel_kultur',
    text: 'Soru 5',
    answers: [{ id: 'a5', display: 'Cevap 5', aliases: ['cevap5'] }],
  },
  {
    id: 'q6',
    category: 'genel_kultur',
    text: 'Soru 6',
    answers: [{ id: 'a6', display: 'Cevap 6', aliases: ['cevap6'] }],
  },
];

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
        async delete(key: string) {
          store.delete(key);
        },
        async deleteAll() {
          store.clear();
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
      },
      acceptWebSocket(ws: any, tags: string[]) {
        (ws as any)._tags = tags;
        sockets.push(ws);
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets.filter((s) => !s.isClosed);
        return sockets.filter((s) => !s.isClosed && (s as any)._tags?.includes(tag));
      },
      getTags(ws: any) {
        return (ws as any)._tags ?? [];
      },
      blockConcurrencyWhile: async (fn: () => Promise<void>) => fn(),
    },
    store,
    sockets,
    getAlarmTime: () => alarmTime,
  };
}

describe('MADDE 1: MatchEngine.submit Sanitization & Length Boundary', () => {
  const baseConfig: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 400,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 0,
    minSubmitIntervalMs: 0,
    maxAttemptsPerTurn: 25,
    maxTotalRounds: 5,
  };

  it('girdi boşlukları temizlenerek motora girer', () => {
    const t0 = 10000;
    const startRes = MatchEngine.start({
      config: baseConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      nowMs: t0,
    });

    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: '   ankara \t \n  ',
      nowMs: t0 + 100,
    });

    expect(submitRes.events.some((e) => e.type === 'AnswerAccepted')).toBe(true);
    const attempt = submitRes.state.currentRoundAttempts[0];
    expect(attempt.rawInput).toBe('ankara');
    expect(attempt.displayText).toBe('Ankara');
  });

  it('40 karakteri aşan yanlış cevap 40 karaktere kırpılır ve WrongAnswer eventinde kırpılmış metin döner', () => {
    const t0 = 10000;
    const startRes = MatchEngine.start({
      config: baseConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      nowMs: t0,
    });

    const longWrongInput = 'bu cok ama cok uzun bir yanlis cevaptir kesinlikle 40 karakteri asiyor';
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: longWrongInput,
      nowMs: t0 + 100,
    });

    const wrongEvent = submitRes.events.find((e) => e.type === 'WrongAnswer') as any;
    expect(wrongEvent).toBeDefined();
    expect(wrongEvent.rawInput.length).toBeLessThanOrEqual(40);
    expect(wrongEvent.rawInput).toBe(longWrongInput.slice(0, 40));
    expect(submitRes.state.currentRoundAttempts[0].rawInput).toBe(longWrongInput.slice(0, 40));
  });

  it('yalnızca boşluk içeren girdi empty_input ile reddedilir', () => {
    const t0 = 10000;
    const startRes = MatchEngine.start({
      config: baseConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      nowMs: t0,
    });

    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: '   \t \n  ',
      nowMs: t0 + 100,
    });

    expect(submitRes.events).toEqual([{ type: 'Ignored', reason: 'empty_input' }]);
    expect(submitRes.state.currentRoundAttempts.length).toBe(0);
  });
});

describe('MADDE 2: TURN_GRACE_MS Ağ Gecikmesi Toleransı', () => {
  const baseConfig: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 400,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 0,
    minSubmitIntervalMs: 0,
    maxAttemptsPerTurn: 25,
    maxTotalRounds: 5,
  };

  it('nominal deadline + 200ms anında cevap tolerans dahilinde kabul edilir', () => {
    const t0 = 10000;
    const startRes = MatchEngine.start({
      config: baseConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      nowMs: t0,
    });

    const deadline = startRes.state.deadlineMs;
    expect(deadline).toBe(t0 + 15000);

    // 200 ms tolerans içi: deadline + 200 ms <= deadline + 400 ms
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'ankara',
      nowMs: deadline + 200,
    });

    expect(submitRes.events.some((e) => e.type === 'AnswerAccepted')).toBe(true);
  });

  it('nominal deadline + 401ms anında cevap timeout olarak reddedilir', () => {
    const t0 = 10000;
    const startRes = MatchEngine.start({
      config: baseConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      nowMs: t0,
    });

    const deadline = startRes.state.deadlineMs;

    // 401 ms tolerans dışı: deadline + 401 ms > deadline + 400 ms
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'ankara',
      nowMs: deadline + 401,
    });

    expect(submitRes.events.some((e) => e.type === 'RoundDrawn' || e.type === 'RoundWon')).toBe(true);
    expect(submitRes.state.phase).toBe('roundEnded');
  });

  it('MatchRoom schedule alarm vadesine TURN_GRACE_MS eklerken istemciye nominal süre gönderir', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env: Env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as any;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_grace',
      p1: { uid: 'u1', name: 'P1' },
      p2: { uid: 'u2', name: 'P2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      matchType: 'ranked',
      energyChargedUids: ['u1', 'u2'],
    });

    const ws1 = createMockSocket('u1');
    const ws2 = createMockSocket('u2');
    ctx.acceptWebSocket(ws1, ['u1']);
    ctx.acceptWebSocket(ws2, ['u2']);

    await (room as any).handlePlayerConnected('u1');
    await (room as any).handlePlayerConnected('u2');

    const stateMsgs = ws1.sent.filter((m) => m.t === 'state');
    expect(stateMsgs.length).toBeGreaterThan(0);
    const clientState = stateMsgs[stateMsgs.length - 1];

    const alarmTime = getAlarmTime();
    expect(alarmTime).toBeDefined();

    // Alarm vadesi = client nominal deadline + 400 ms
    expect(alarmTime).toBe(clientState.deadlineMs + 400);
  });

  it('Regresyon testi: İki oyuncu kopunca dondurulan süre ve dönünce eklenen tolerans alarmda korunur', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env: Env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as any;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_freeze_grace',
      p1: { uid: 'u1', name: 'P1' },
      p2: { uid: 'u2', name: 'P2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
      energyChargedUids: ['u1', 'u2'],
    });

    const ws1 = createMockSocket('u1');
    const ws2 = createMockSocket('u2');
    ctx.acceptWebSocket(ws1, ['u1']);
    ctx.acceptWebSocket(ws2, ['u2']);

    await (room as any).handlePlayerConnected('u1');
    await (room as any).handlePlayerConnected('u2');

    // İki oyuncu da kopar
    await room.webSocketClose(ws1 as any, 1006, 'abnormal');
    await room.webSocketClose(ws2 as any, 1006, 'abnormal');

    const roomData = (room as any).data;
    expect(roomData.schedule.turnDeadlineMs).toBeUndefined();
    expect(roomData.frozenTurnRemainingMs).toBeGreaterThan(0);

    // P1 geri bağlanır
    const ws1New = createMockSocket('u1');
    ctx.acceptWebSocket(ws1New, ['u1']);
    await (room as any).handlePlayerConnected('u1');

    const resumedData = (room as any).data;
    expect(resumedData.frozenTurnRemainingMs).toBeUndefined();
    expect(resumedData.schedule.turnDeadlineMs).toBeDefined();

    const newAlarmTime = getAlarmTime();
    // Alarm zamanı disconnectTimeout (30sn) ile turnDeadlineMs (kalan süre + 400ms) arasından küçüğü alır
    expect(newAlarmTime).toBeLessThanOrEqual(resumedData.schedule.turnDeadlineMs);
  });
});

describe('MADDE 3: Beraberlik Tavanı (maxTotalRounds = 5) ve Voided Akışı', () => {
  const ceilingConfig: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 400,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 0,
    minSubmitIntervalMs: 0,
    maxAttemptsPerTurn: 25,
    maxTotalRounds: 5,
  };

  it('5 tur boyunca beraberlik olursa (sorular tükenince) 5. tur sonunda maç draw_limit_reached ile biter', () => {
    let now = 10000;
    let engineRes = MatchEngine.start({
      config: ceilingConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      nowMs: now,
    });

    // 5 tur boyunca tek cevabı olan sorunun tek cevabı verilerek tur tüketilir (exhausted -> draw)
    const answers = ['ankara', 'cevap2', 'cevap3', 'cevap4', 'cevap5'];

    for (let round = 1; round <= 5; round++) {
      const activePlayer = engineRes.state.turnPlayerId!;
      engineRes = MatchEngine.submit({
        state: engineRes.state,
        playerId: activePlayer,
        rawInput: answers[round - 1],
        nowMs: now + 500,
      });

      if (round < 5) {
        expect(engineRes.state.phase).toBe('roundEnded');
        now += 3000;
        engineRes = MatchEngine.startNextRound({
          state: engineRes.state,
          questions: sampleQuestions,
          questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
          nowMs: now,
        });
      }
    }

    // 5. tur bittiğinde tavan dolmuştur ve skorlar 0-0'dır
    expect(engineRes.state.phase).toBe('matchFinished');
    expect(engineRes.state.winnerId).toBeNull();
    expect(engineRes.state.endedBy).toBe('draw_limit_reached');
    expect(engineRes.state.totalRoundsPlayed).toBe(5);
  });

  it('5. turun sonunda skor eşit değilse (örn. 1-0) lider olan normal kazanır', () => {
    let now = 10000;
    let engineRes = MatchEngine.start({
      config: ceilingConfig,
      playerIds: ['p1', 'p2'],
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      nowMs: now,
    });

    // 1. turu p1 kazansın (p2 timeout)
    const deadline1 = engineRes.state.deadlineMs;
    now = deadline1 + 500;
    engineRes = MatchEngine.checkTimeout({
      state: engineRes.state,
      nowMs: now,
    });
    // p1 sırasıydı, timeout olunca p2 kazandı (0-1)
    expect(engineRes.state.phase).toBe('roundEnded');

    // Sonraki 4 tur berabere bitsin (exhausted ile, skor 0-1 kalsın)
    const answers = ['cevap2', 'cevap3', 'cevap4', 'cevap5'];
    for (let round = 2; round <= 5; round++) {
      now += 3000;
      engineRes = MatchEngine.startNextRound({
        state: engineRes.state,
        questions: sampleQuestions,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
        nowMs: now,
      });

      const activePlayer = engineRes.state.turnPlayerId!;
      engineRes = MatchEngine.submit({
        state: engineRes.state,
        playerId: activePlayer,
        rawInput: answers[round - 2],
        nowMs: now + 500,
      });

      if (engineRes.state.phase === 'matchFinished') {
        break;
      }
    }

    expect(engineRes.state.phase).toBe('matchFinished');
    expect(engineRes.state.endedBy).toBe('normal');
    expect(engineRes.state.winnerId).toBe('p2');
    expect(engineRes.state.totalRoundsPlayed).toBe(5);
  });

  it('MatchRoom 5. tur berabere bitince draw_limit_reached ile voided ilan eder ve enerji iadesi yapar', async () => {
    vi.useFakeTimers();
    let simTime = 10000;
    vi.setSystemTime(simTime);

    const { ctx } = createMockRoomCtx();
    const refundedUids: string[] = [];
    const env: Env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        get: (_id: any) => ({
          refundEnergy: async (params: any) => {
            refundedUids.push(params.uid);
            return { refunded: true };
          },
        }),
        idFromName: (name: string) => name as any,
      } as any,
    } as any;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_draw_limit',
      p1: { uid: 'u1', name: 'P1' },
      p2: { uid: 'u2', name: 'P2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      matchType: 'ranked',
      energyChargedUids: ['u1', 'u2'],
    });

    const ws1 = createMockSocket('u1');
    const ws2 = createMockSocket('u2');
    ctx.acceptWebSocket(ws1, ['u1']);
    ctx.acceptWebSocket(ws2, ['u2']);

    await (room as any).handlePlayerConnected('u1');
    await (room as any).handlePlayerConnected('u2');

    // 5 tur boyunca tek cevaplı soruları doğru yanıtlayarak turları tüket (exhausted -> draw)
    const answers = ['ankara', 'cevap2', 'cevap3', 'cevap4', 'cevap5'];
    for (let round = 1; round <= 5; round++) {
      const roomData = (room as any).data;
      if (roomData.status === 'voided') {
        break;
      }

      // Aktif oyuncuyu bul
      const state = deserializeMatchState(roomData.engineState);
      const activeUid = state.turnPlayerId;
      const ws = activeUid === 'u1' ? ws1 : ws2;

      simTime += 1000;
      vi.setSystemTime(simTime);
      await room.webSocketMessage(ws as any, JSON.stringify({ t: 'submit', text: answers[round - 1] }));

      const postSubmitData = (room as any).data;
      if (postSubmitData.status === 'voided') {
        break;
      }

      if (postSubmitData.schedule.nextRoundAtMs) {
        simTime = postSubmitData.schedule.nextRoundAtMs + 10;
        vi.setSystemTime(simTime);
        await room.alarm();
      }
    }

    vi.useRealTimers();

    const finalData = (room as any).data;
    expect(finalData.status).toBe('voided');
    expect(finalData.voidedReason).toBe('draw_limit_reached');

    // Soketlere gönderilen mesajlar arasında voided mesajı var mı?
    const voidedMsg1 = ws1.sent.find((m) => m.t === 'voided');
    expect(voidedMsg1).toEqual({ t: 'voided', reason: 'draw_limit_reached' });

    // Enerjiler iade edildi mi?
    expect(refundedUids).toContain('u1');
    expect(refundedUids).toContain('u2');

    // Soketler kapatıldı mı?
    expect(ws1.isClosed).toBe(true);
    expect(ws1.closeCode).toBe(1000);
  });
});
