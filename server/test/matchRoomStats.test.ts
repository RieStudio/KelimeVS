import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { DatabaseSync } from 'node:sqlite';

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
import { UserProfile } from '../src/userProfile';
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
  };
}

function createMockProfileCtx() {
  const db = new DatabaseSync(':memory:');
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      const upper = trimmed.toUpperCase();
      if (
        upper.startsWith('BEGIN') ||
        upper.startsWith('COMMIT') ||
        upper.startsWith('ROLLBACK') ||
        upper.startsWith('SAVEPOINT')
      ) {
        throw new Error('Manual transactions not allowed');
      }
      if (trimmed.toUpperCase().startsWith('SELECT') || trimmed.toUpperCase().startsWith('PRAGMA')) {
        const stmt = db.prepare(trimmed);
        const rows = stmt.all(...bindings) as T[];
        return {
          toArray: () => rows,
          one: () => rows[0],
          [Symbol.iterator]: () => rows[Symbol.iterator](),
        };
      } else {
        if (bindings.length > 0) {
          const stmt = db.prepare(trimmed);
          stmt.run(...bindings);
        } else {
          db.exec(trimmed);
        }
        return {
          toArray: () => [],
          one: () => undefined as any,
          [Symbol.iterator]: () => [][Symbol.iterator](),
        };
      }
    },
  };

  return {
    ctx: {
      storage: {
        sql,
        async deleteAll() {},
        async setAlarm() {},
      },
    } as unknown as DurableObjectState,
    db,
  };
}

function makeQuestions(): Question[] {
  return [
    {
      id: 'q1',
      categoryId: 'cat1',
      text: 'Meyveler',
      answers: [
        { id: 'elma', display: 'Elma', aliases: ['elma'] },
        { id: 'armut', display: 'Armut', aliases: ['armut'] },
        { id: 'muz', display: 'Muz', aliases: ['muz'] },
        { id: 'kivi', display: 'Kivi', aliases: ['kivi'] },
        { id: 'cilek', display: 'Çilek', aliases: ['cilek'] },
      ],
    },
    {
      id: 'q2',
      categoryId: 'cat1',
      text: 'Hayvanlar',
      answers: [
        { id: 'kedi', display: 'Kedi', aliases: ['kedi'] },
        { id: 'kopek', display: 'Köpek', aliases: ['kopek'] },
        { id: 'kus', display: 'Kuş', aliases: ['kus'] },
        { id: 'balık', display: 'Balık', aliases: ['balik'] },
      ],
    },
    {
      id: 'q3',
      categoryId: 'cat1',
      text: 'Renkler',
      answers: [
        { id: 'mavi', display: 'Mavi', aliases: ['mavi'] },
        { id: 'kirmizi', display: 'Kırmızı', aliases: ['kirmizi'] },
        { id: 'yesil', display: 'Yeşil', aliases: ['yesil'] },
        { id: 'sari', display: 'Sarı', aliases: ['sari'] },
        { id: 'mor', display: 'Mor', aliases: ['mor'] },
        { id: 'turuncu', display: 'Turuncu', aliases: ['turuncu'] },
      ],
    },
  ];
}

async function submitAnswer(room: MatchRoom, ws: any, text: string) {
  vi.advanceTimersByTime(600);
  await room.webSocketMessage(ws, JSON.stringify({ t: 'submit', text }));
}

describe('Oyuncu İstatistikleri & MatchRoom Doğru Cevap Doğrulama Testleri', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('1. 2-0 Normal Galibiyet: Maçı bitiren 2. turun doğru cevapları dahil tüm cevaplar roundHistory\'de ve ödül çağrısında eksiksiz aktarılır', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const rewardsApplied: Record<string, any> = {};

    const env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        idFromName: (name: string) => name,
        get: (uid: string) => ({
          async applyMatchReward(params: any) {
            rewardsApplied[uid] = params;
            return { coinsAwarded: 30, coins: 130, nickname: uid };
          },
        }),
      },
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    const questions = makeQuestions();

    await room.initMatch({
      matchId: 'm_2_0',
      p1: { uid: 'p1', name: 'Player1' },
      p2: { uid: 'p2', name: 'Player2' },
      questions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
      roundsToWin: 2,
      answerSeconds: 15,
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1:
    // P1 başlar: 'elma' -> Doğru (P1: 1)
    await submitAnswer(room, ws1, 'elma');
    // P2: 'armut' -> Doğru (P2: 1)
    await submitAnswer(room, ws2, 'armut');
    // P1: 'muz' -> Doğru (P1: 2)
    await submitAnswer(room, ws1, 'muz');
    // P2 süre aşımı -> P1 turu kazanır (Skor: 1-0)
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Tur geçiş süresi (FAST_TIMERS'ta 500ms)
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 2 (Maçı bitiren son tur):
    // P2 başlar: 'kedi' -> Doğru (P2: 2)
    await submitAnswer(room, ws2, 'kedi');
    // P1: 'kopek' -> Doğru (P1: 3)
    await submitAnswer(room, ws1, 'kopek');
    // P2 süre aşımı -> P1 turu ve maçı kazanır (Skor: 2-0 -> matchFinished)
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Ödüller kontrol edilir
    expect(rewardsApplied['p1']).toBeDefined();
    expect(rewardsApplied['p2']).toBeDefined();

    expect(rewardsApplied['p1'].outcome).toBe('win');
    expect(rewardsApplied['p1'].correctAnswers).toBe(3); // 2 in round 1 + 1 in round 2

    expect(rewardsApplied['p2'].outcome).toBe('loss');
    expect(rewardsApplied['p2'].correctAnswers).toBe(2); // 1 in round 1 + 1 in round 2

    // Toplam doğru cevap kaybı yok: 3 + 2 = 5
    expect(rewardsApplied['p1'].correctAnswers + rewardsApplied['p2'].correctAnswers).toBe(5);
  });

  it('2. 2-1 Çekişmeli Maç (3 Karar Turu): Son karar turunun doğru cevapları eksiksiz toplanır', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const rewardsApplied: Record<string, any> = {};

    const env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        idFromName: (name: string) => name,
        get: (uid: string) => ({
          async applyMatchReward(params: any) {
            rewardsApplied[uid] = params;
            return { coinsAwarded: 30, coins: 130, nickname: uid };
          },
        }),
      },
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    const questions = makeQuestions();

    await room.initMatch({
      matchId: 'm_2_1',
      p1: { uid: 'p1', name: 'Player1' },
      p2: { uid: 'p2', name: 'Player2' },
      questions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
      roundsToWin: 2,
      answerSeconds: 15,
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1: P1 kazanır
    // P1: 'elma' (P1: 1), P2: 'armut' (P2: 1), P1: 'muz' (P1: 2), P2 timeout.
    await submitAnswer(room, ws1, 'elma');
    await submitAnswer(room, ws2, 'armut');
    await submitAnswer(room, ws1, 'muz');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Tur geçişi
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 2: P2 kazanır (Skor: 1-1)
    // P2: 'kedi' (P2: 2), P1: 'kopek' (P1: 3), P2: 'kus' (P2: 3), P1 timeout.
    await submitAnswer(room, ws2, 'kedi');
    await submitAnswer(room, ws1, 'kopek');
    await submitAnswer(room, ws2, 'kus');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Tur geçişi
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 3 (Son Karar Turu): P1 başlar ve kazanır (Skor: 2-1 -> matchFinished)
    // P1: 'mavi' (P1: 4), P2: 'kirmizi' (P2: 4), P1: 'yesil' (P1: 5), P2: 'sari' (P2: 5), P1: 'mor' (P1: 6), P2 timeout.
    await submitAnswer(room, ws1, 'mavi');
    await submitAnswer(room, ws2, 'kirmizi');
    await submitAnswer(room, ws1, 'yesil');
    await submitAnswer(room, ws2, 'sari');
    await submitAnswer(room, ws1, 'mor');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    expect(rewardsApplied['p1'].outcome).toBe('win');
    expect(rewardsApplied['p1'].correctAnswers).toBe(6); // 2 + 1 + 3 = 6

    expect(rewardsApplied['p2'].outcome).toBe('loss');
    expect(rewardsApplied['p2'].correctAnswers).toBe(5); // 1 + 2 + 2 = 5
  });

  it('3. Beraberlik İçeren Maç: Berabere biten turdaki doğru cevaplar da kaybolmaz', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const rewardsApplied: Record<string, any> = {};

    const env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        idFromName: (name: string) => name,
        get: (uid: string) => ({
          async applyMatchReward(params: any) {
            rewardsApplied[uid] = params;
            return { coinsAwarded: 30, coins: 130, nickname: uid };
          },
        }),
      },
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    const questions = makeQuestions();

    await room.initMatch({
      matchId: 'm_draw_round',
      p1: { uid: 'p1', name: 'Player1' },
      p2: { uid: 'p2', name: 'Player2' },
      questions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
      roundsToWin: 2,
      answerSeconds: 15,
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1: P1 kazanır (P1: 1, P2: 0)
    await submitAnswer(room, ws1, 'elma');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Tur geçişi
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 2: Tüm cevaplar bulunur (exhausted) -> Berabere
    // P2: 'kedi' (P2: 1), P1: 'kopek' (P1: 2), P2: 'kus' (P2: 2), P1: 'balik' (P1: 3)
    await submitAnswer(room, ws2, 'kedi');
    await submitAnswer(room, ws1, 'kopek');
    await submitAnswer(room, ws2, 'kus');
    await submitAnswer(room, ws1, 'balik'); // Soru cevapları bitti -> RoundDrawn

    // Tur geçişi
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 3: P1 kazanır (Skor: 2-0 -> matchFinished)
    // P1: 'mavi' (P1: 4), P2: 'kirmizi' (P2: 3), P1: 'yesil' (P1: 5), P2 timeout.
    await submitAnswer(room, ws1, 'mavi');
    await submitAnswer(room, ws2, 'kirmizi');
    await submitAnswer(room, ws1, 'yesil');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    expect(rewardsApplied['p1'].outcome).toBe('win');
    expect(rewardsApplied['p1'].correctAnswers).toBe(5); // 1 + 2 + 2 = 5

    expect(rewardsApplied['p2'].outcome).toBe('loss');
    expect(rewardsApplied['p2'].correctAnswers).toBe(3); // 0 + 2 + 1 = 3
  });

  it('4. Hükmen Bitiş (Forfeit): Terk anına kadarki doğru cevaplar eksiksiz sayılır', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const rewardsApplied: Record<string, any> = {};

    const env = {
      FAST_TIMERS: 'true',
      USER_PROFILE: {
        idFromName: (name: string) => name,
        get: (uid: string) => ({
          async applyMatchReward(params: any) {
            rewardsApplied[uid] = params;
            return { coinsAwarded: 30, coins: 130, nickname: uid };
          },
        }),
      },
    } as unknown as Env;

    const room = new MatchRoom(ctx, env);
    const questions = makeQuestions();

    await room.initMatch({
      matchId: 'm_forfeit',
      p1: { uid: 'p1', name: 'Player1' },
      p2: { uid: 'p2', name: 'Player2' },
      questions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
      roundsToWin: 2,
      answerSeconds: 15,
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    sockets.push(ws1, ws2);
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1: P1 kazanır (P1: 2, P2: 1)
    await submitAnswer(room, ws1, 'elma');
    await submitAnswer(room, ws2, 'armut');
    await submitAnswer(room, ws1, 'muz');
    vi.advanceTimersByTime(4000);
    await room.alarm();

    // Tur geçişi
    vi.advanceTimersByTime(1000);
    await room.alarm();

    // Tur 2 sırasında: P2 'kedi' yazar (P2: 2), P1 'kopek' yazar (P1: 3).
    await submitAnswer(room, ws2, 'kedi');
    await submitAnswer(room, ws1, 'kopek');

    // Sonra P2 maçı terk eder (leave -> forfeit)
    vi.advanceTimersByTime(600);
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'leave' }));

    expect(rewardsApplied['p1'].outcome).toBe('win_by_opponent_disconnect');
    expect(rewardsApplied['p1'].correctAnswers).toBe(3); // 2 in round 1 + 1 in round 2

    expect(rewardsApplied['p2'].outcome).toBe('loss_by_disconnect');
    expect(rewardsApplied['p2'].correctAnswers).toBe(2); // 1 in round 1 + 1 in round 2
  });

  it('5. UserProfile DO SQLite: applyMatchReward idempotens ve doğru cevap sayacı birikimi', async () => {
    const { ctx } = createMockProfileCtx();
    const env = {} as Env;
    const profileDO = new UserProfile(ctx, env);

    // 1. Maç: 4 doğru cevapla kazanıldı
    await profileDO.applyMatchReward({
      matchId: 'match_1',
      outcome: 'win',
      uid: 'user_x',
      correctAnswers: 4,
    });

    let p = await profileDO.getProfile('user_x');
    expect(p.stats.played).toBe(1);
    expect(p.stats.won).toBe(1);
    expect(p.stats.lost).toBe(0);
    expect(p.stats.correctAnswers).toBe(4);

    // Aynı matchId ile tekrar çağrılırsa (idempotency guard): sayaçlar ve doğru cevap ikiye katlanmaz
    await profileDO.applyMatchReward({
      matchId: 'match_1',
      outcome: 'win',
      uid: 'user_x',
      correctAnswers: 4,
    });

    p = await profileDO.getProfile('user_x');
    expect(p.stats.played).toBe(1);
    expect(p.stats.won).toBe(1);
    expect(p.stats.correctAnswers).toBe(4);

    // 2. Maç: 3 doğru cevapla kaybedildi
    await profileDO.applyMatchReward({
      matchId: 'match_2',
      outcome: 'loss',
      uid: 'user_x',
      correctAnswers: 3,
    });

    p = await profileDO.getProfile('user_x');
    expect(p.stats.played).toBe(2);
    expect(p.stats.won).toBe(1);
    expect(p.stats.lost).toBe(1);
    expect(p.stats.correctAnswers).toBe(7); // 4 + 3 = 7
  });

  it('6. Migration: Eski şemada correct_answers kolonu yokken otomatik göç eder ve eski sayaçları korur', async () => {
    const { ctx, db } = createMockProfileCtx();

    // Eski şemayı simüle et (correct_answers sütunu YOK)
    db.exec(`
      CREATE TABLE profiles (
        uid TEXT PRIMARY KEY,
        nickname TEXT,
        coins INTEGER NOT NULL,
        played INTEGER NOT NULL DEFAULT 0,
        won INTEGER NOT NULL DEFAULT 0,
        lost INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      INSERT INTO profiles (uid, nickname, coins, played, won, lost, created_at)
      VALUES ('legacy_user', 'EskiOyuncu', 250, 15, 10, 5, 1700000000000);
    `);

    const env = {} as Env;
    const profileDO = new UserProfile(ctx, env);

    const profile = await profileDO.getProfile('legacy_user');
    // Eski sayaçlar korunur, correctAnswers 0 olarak başlar
    expect(profile.nickname).toBe('EskiOyuncu');
    expect(profile.coins).toBe(250);
    expect(profile.stats.played).toBe(15);
    expect(profile.stats.won).toBe(10);
    expect(profile.stats.lost).toBe(5);
    expect(profile.stats.correctAnswers).toBe(0);
  });
});
