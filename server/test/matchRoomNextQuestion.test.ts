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

const q1: Question = {
  id: 'q1',
  categoryId: 'c1',
  text: 'Meyveler',
  answers: [
    { id: 'a1', display: 'Elma', aliases: ['elma'] },
    { id: 'a2', display: 'Armut', aliases: ['armut'] },
  ],
};

const q2: Question = {
  id: 'q2',
  categoryId: 'c2',
  text: 'Şehirler',
  answers: [
    { id: 'a3', display: 'Ankara', aliases: ['ankara'] },
    { id: 'a4', display: 'İzmir', aliases: ['izmir'] },
  ],
};

const q3: Question = {
  id: 'q3',
  categoryId: 'c3',
  text: 'Renkler',
  answers: [
    { id: 'a5', display: 'Mavi', aliases: ['mavi'] },
    { id: 'a6', display: 'Kırmızı', aliases: ['kirmizi'] },
  ],
};

describe('MatchRoom nextQuestion Sync and Security Tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('Tur bitişinde nextQuestion.id, MatchRoom sonraki tur sorusuna eşittir; son turda yoktur; cevap sızdırılmaz', async () => {
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

    const env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        idFromName(name: string) {
          return name;
        },
        get(id: string) {
          return {
            async applyMatchReward() {
              return { ok: true, reward: { coinsEarned: 10 } };
            },
          };
        },
      },
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    await room.initMatch({
      matchId: 'match_sync_1',
      p1: { uid: 'alice', name: 'Alice' },
      p2: { uid: 'bob', name: 'Bob' },
      questions: [q1, q2, q3],
      questionOrder: ['q1', 'q2', 'q3'],
    });

    // Her iki oyuncu bağlanır -> 1. tur başlar
    await (room as any).handlePlayerConnected('alice');
    await (room as any).handlePlayerConnected('bob');

    // 1. Tur aktifken mesajları temizle
    aliceMessages.length = 0;
    bobMessages.length = 0;

    // 1. Tur biter (FAST_TIMERS: 3s answer + 0.5s grace = 3.5s; 4s ilerletiyoruz)
    vi.advanceTimersByTime(4000);
    await room.alarm(); // turnTimeout alarmı tetiklenir

    // roundEnded durumundaki state mesajı gönderilmiş olmalı
    const round1EndedMsg = aliceMessages.find(
      (m) => m.t === 'state' && m.phase === 'roundEnded'
    );
    expect(round1EndedMsg).toBeDefined();

    // 1. İSPAT: nextQuestion alanı mevcuttur ve tam olarak q2'dir
    expect(round1EndedMsg.nextQuestion).toBeDefined();
    expect(round1EndedMsg.nextQuestion.id).toBe('q2');
    expect(round1EndedMsg.nextQuestion.text).toBe('Şehirler');

    // 2. GÜVENLİK İSPATI: Cevap listesi (answers, canonical, accepted) ASLA mesajda yer almaz
    expect(round1EndedMsg.nextQuestion.answers).toBeUndefined();
    expect(round1EndedMsg.nextQuestion.canonicalAnswers).toBeUndefined();
    expect(round1EndedMsg.nextQuestion.acceptedAnswers).toBeUndefined();
    expect(round1EndedMsg.answers).toBeUndefined();

    // Şimdi fastTimer geçiş süresi (500ms) ilerletilir ve 2. tur başlar
    aliceMessages.length = 0;
    vi.advanceTimersByTime(1000);
    await room.alarm(); // startNextRound tetiklenir

    const round2ActiveMsg = aliceMessages.find(
      (m) => m.t === 'state' && m.phase === 'roundActive'
    );
    expect(round2ActiveMsg).toBeDefined();

    // 3. İSPAT: 2. turda oynanan soru, roundEnded mesajında gösterilen nextQuestion ile AYNI sorudur
    expect(round2ActiveMsg.question).toBeDefined();
    expect(round2ActiveMsg.question.id).toBe('q2');
    expect(round2ActiveMsg.question.text).toBe('Şehirler');

    // 2. Tur da biter ve maç sonuçlanırsa (örneğin Alice 2. kez kazanıp maçı bitirir)
    await (room as any).handleMatchFinished();

    const finalMessages = aliceMessages.filter((m) => m.t === 'final');
    expect(finalMessages.length).toBeGreaterThan(0);
    const finalMsg = finalMessages[0];

    // Son turda / maç bittiğinde nextQuestion alanı BULUNMAZ
    expect(finalMsg.nextQuestion).toBeUndefined();
  });
});
