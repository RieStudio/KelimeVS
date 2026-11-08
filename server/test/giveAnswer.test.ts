import { describe, expect, it, vi } from 'vitest';
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

import { UserProfile } from '../src/userProfile';
import { MatchRoom } from '../src/matchRoom';
import { deserializeMatchState, serializeMatchState } from '../src/storage';
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

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
        throw new Error(
          'The Durable Object storage SQLite database does not allow manual transactions. Use state.storage.transaction() or state.storage.transactionSync() instead.'
        );
      }
      if (upper.startsWith('SELECT')) {
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
    storage: {
      sql,
      transactionSync<T>(closure: () => T): T {
        db.exec('BEGIN TRANSACTION');
        try {
          const res = closure();
          db.exec('COMMIT');
          return res;
        } catch (err) {
          try {
            db.exec('ROLLBACK');
          } catch {}
          throw err;
        }
      },
      async setAlarm() {},
    },
  } as unknown as DurableObjectState;
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

function createMockSocket(tag: string, sent: any[]) {
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

const multiAnswerQuestion: Question = {
  id: 'q_multi',
  categoryId: 'c1',
  text: 'Türkiye İlleri',
  answers: [
    { id: 'ankara', display: 'Ankara', aliases: ['ankara', 'angara'] },
    { id: 'istanbul', display: 'İstanbul', aliases: ['istanbul', 'ist'] },
    { id: 'izmir', display: 'İzmir', aliases: ['izmir'] },
    { id: 'bursa', display: 'Bursa', aliases: ['bursa'] },
  ],
};

const twoAnswerQuestion: Question = {
  id: 'q_two',
  categoryId: 'c1',
  text: 'İki Cevaplı Soru',
  answers: [
    { id: 'elma', display: 'Elma', aliases: ['elma'] },
    { id: 'armut', display: 'Armut', aliases: ['armut'] },
  ],
};

describe('Cevap Ver (give_answer) Güçlendiricisi - UserProfile Tests', () => {
  it('UserProfile DO: give_answer harcaması atomik ve idempotenttir, (matchId, give_answer) bir kez düşer', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, {} as Env);
    await up.getProfile('user_give_answer'); // 100 jeton başlar

    const r1 = await up.spendCoins({
      matchId: 'm_give_answer_1',
      powerup: 'give_answer',
      amount: 50,
      uid: 'user_give_answer',
    });
    expect(r1.success).toBe(true);
    expect(r1.coins).toBe(50);
    expect(r1.alreadySpent).toBeUndefined();

    // İkinci çağrı (idempotent kontrol)
    const r2 = await up.spendCoins({
      matchId: 'm_give_answer_1',
      powerup: 'give_answer',
      amount: 50,
      uid: 'user_give_answer',
    });
    expect(r2.success).toBe(true);
    expect(r2.alreadySpent).toBe(true);
    expect(r2.coins).toBe(50); // Tekrar jeton düşmez

    // İade testi
    const refund = await up.refundPowerup({
      matchId: 'm_give_answer_1',
      powerup: 'give_answer',
      amount: 50,
      uid: 'user_give_answer',
    });
    expect(refund.ok).toBe(true);
    expect(refund.refunded).toBe(true);
    expect(refund.coins).toBe(100);
  });
});

describe('Cevap Ver (give_answer) Güçlendiricisi - MatchRoom Turn & Race Condition Tests', () => {
  it('1. Başarılı kullanım: jeton 50 düşer, cevap kabul edilir, viaPowerup: true olur, sıra rakibe geçer, süre sıfırlanır, remainingUses: 0', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];

    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    let spendCoinsCalled = false;
    let spendCoinsAmount = 0;
    const mockUserProfile = {
      spendCoins: async (params: any) => {
        spendCoinsCalled = true;
        spendCoinsAmount = params.amount;
        return { success: true, coins: 50 };
      },
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      GIVE_ANSWER_COST: '50',
      USER_PROFILE: {
        idFromName: () => 'id_p1' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    // rng'yi deterministik 0 yapalım (ilk kullanılmamış Ankara seçilsin)
    room.setRngForTest(() => 0);

    await room.initMatch({
      matchId: 'm_give_answer_success',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    sentP1.length = 0;
    sentP2.length = 0;

    // p1 give_answer kullansın
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    expect(spendCoinsCalled).toBe(true);
    expect(spendCoinsAmount).toBe(50);

    // p1'e powerup_ack onay mesajı gitmeli
    const ackMsg = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ackMsg).toBeDefined();
    expect(ackMsg.powerupType).toBe('give_answer');
    expect(ackMsg.success).toBe(true);
    expect(ackMsg.coins).toBe(50);
    expect(ackMsg.remainingUses).toBe(0);

    // p1 ve p2'ye güncel state gitmeli
    const lastStateP1 = [...sentP1].reverse().find((m) => m.t === 'state');
    const lastStateP2 = [...sentP2].reverse().find((m) => m.t === 'state');

    expect(lastStateP1).toBeDefined();
    // Sıra rakibe (p2) geçmiş olmalı
    expect(lastStateP1.turnIsMine).toBe(false);
    expect(lastStateP2.turnIsMine).toBe(true);

    // attempts listesinde Ankara kabul edilmiş ve viaPowerup: true işaretlenmiş olmalı
    const powerupAttemptP1 = lastStateP1.attempts.find((a: any) => a.text === 'Ankara');
    expect(powerupAttemptP1).toBeDefined();
    expect(powerupAttemptP1.result).toBe('correct');
    expect(powerupAttemptP1.mine).toBe(true);
    expect(powerupAttemptP1.viaPowerup).toBe(true);

    const powerupAttemptP2 = lastStateP2.attempts.find((a: any) => a.text === 'Ankara');
    expect(powerupAttemptP2).toBeDefined();
    expect(powerupAttemptP2.result).toBe('correct');
    expect(powerupAttemptP2.mine).toBe(false);
    expect(powerupAttemptP2.viaPowerup).toBe(true);

    // state.powerups altında giveAnswer remainingUses: 0 görünmeli
    expect(lastStateP1.powerups?.giveAnswer?.remainingUses).toBe(0);
    expect(lastStateP1.powerups?.giveAnswer?.cost).toBe(50);
  });

  it('2. Hata durumları: yetersiz bakiye, sıra bende değil, ikinci kullanım (already_used), arkadaş maçı, tur aktif değil', async () => {
    let profileCoins = 100;
    const mockUserProfile = {
      spendCoins: async (params: any) => {
        if (profileCoins < params.amount) {
          return { success: false, error: 'not_enough_coins', coins: profileCoins };
        }
        profileCoins -= params.amount;
        return { success: true, coins: profileCoins };
      },
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      GIVE_ANSWER_COST: '50',
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    // A) Arkadaş maçı testi
    {
      const { ctx, sockets } = createMockRoomCtx();
      const sentP1: any[] = [];
      const sentP2: any[] = [];
      const ws1 = createMockSocket('p1', sentP1);
      const ws2 = createMockSocket('p2', sentP2);
      sockets.push(ws1, ws2);

      const friendlyRoom = new MatchRoom(ctx, env as Env);
      await friendlyRoom.initMatch({
        matchId: 'm_friendly',
        p1: { uid: 'p1', name: 'Alice' },
        p2: { uid: 'p2', name: 'Bob' },
        questions: [multiAnswerQuestion],
        questionOrder: ['q_multi'],
        matchType: 'friendly',
      });
      await (friendlyRoom as any).handlePlayerConnected('p1');
      await (friendlyRoom as any).handlePlayerConnected('p2');

      sentP1.length = 0;
      await friendlyRoom.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
      const friendlyAck = sentP1.find((m) => m.t === 'powerup_ack');
      expect(friendlyAck.success).toBe(false);
      expect(friendlyAck.code).toBe('not_allowed_in_match_type');
    }

    // B) Sıra bende değil, yetersiz bakiye ve already_used testleri
    {
      const { ctx, sockets } = createMockRoomCtx();
      const sentP1: any[] = [];
      const sentP2: any[] = [];
      const ws1 = createMockSocket('p1', sentP1);
      const ws2 = createMockSocket('p2', sentP2);
      sockets.push(ws1, ws2);

      const rankedRoom = new MatchRoom(ctx, env as Env);
      await rankedRoom.initMatch({
        matchId: 'm_ranked_errors',
        p1: { uid: 'p1', name: 'Alice' },
        p2: { uid: 'p2', name: 'Bob' },
        questions: [multiAnswerQuestion],
        questionOrder: ['q_multi'],
      });
      await (rankedRoom as any).handlePlayerConnected('p1');
      await (rankedRoom as any).handlePlayerConnected('p2');

      // 1. Sıra bende değil (p2 sırası değilken ister)
      sentP2.length = 0;
      await rankedRoom.webSocketMessage(ws2 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
      const notYourTurnAck = sentP2.find((m) => m.t === 'powerup_ack');
      expect(notYourTurnAck.success).toBe(false);
      expect(notYourTurnAck.code).toBe('not_your_turn');

      // 2. Yetersiz bakiye testi
      profileCoins = 20; // 50'den az
      sentP1.length = 0;
      await rankedRoom.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
      const notEnoughCoinsAck = sentP1.find((m) => m.t === 'powerup_ack');
      expect(notEnoughCoinsAck.success).toBe(false);
      expect(notEnoughCoinsAck.code).toBe('not_enough_coins');

      // 3. Başarılı kullanım
      profileCoins = 100;
      sentP1.length = 0;
      rankedRoom.setRngForTest(() => 0); // Deterministic: Ankara seçilir
      await rankedRoom.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
      const successAck = sentP1.find((m) => m.t === 'powerup_ack');
      expect(successAck.success).toBe(true);

      // Sırayı tekrar p1'e geçirmek için p2 geçerli bir cevap versin
      await rankedRoom.webSocketMessage(ws2 as any, JSON.stringify({ t: 'submit', text: 'İstanbul' }));

      // 4. İkinci kullanım testi (already_used)
      sentP1.length = 0;
      await rankedRoom.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
      const alreadyUsedAck = sentP1.find((m) => m.t === 'powerup_ack');
      expect(alreadyUsedAck.success).toBe(false);
      expect(alreadyUsedAck.code).toBe('already_used');
    }
  });

  it('3. Çift istek idempotensi: spendCoins alreadySpent döndüğünde powerupsUsed kayıtlıysa mükerrer işlem yapmaz', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => ({ success: true, coins: 50, alreadySpent: true }),
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_idempotency',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Odanın durumunu zaten kullanılmış olarak simüle et
    (room as any).data.powerupsUsed = { p1: { giveAnswer: true } };

    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack).toBeDefined();
    expect(ack.success).toBe(false);
    expect(ack.code).toBe('already_used');
  });

  it('4. Kalan cevap yoksa: no_answers_left döner ve jeton HARCANMAZ', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    let spendCoinsCalled = false;
    const mockUserProfile = {
      spendCoins: async () => {
        spendCoinsCalled = true;
        return { success: true, coins: 50 };
      },
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_no_answers',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [twoAnswerQuestion],
      questionOrder: ['q_two'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Sorunun tüm cevaplarını söylenmiş yapalım
    const baseState = deserializeMatchState((room as any).data.engineState);
    const state = {
      ...baseState,
      usedAnswerIds: new Set(['elma', 'armut']),
    };
    (room as any).data.engineState = serializeMatchState(state);

    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    expect(spendCoinsCalled).toBe(false); // Jeton harcanmamalı!
    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack).toBeDefined();
    expect(ack.success).toBe(false);
    expect(ack.code).toBe('no_answers_left');
  });

  it('5. Yarış durumu: spendCoins sonrası sıra veya süre değişirse harcama iade edilir (enqueueAndRefund)', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    let refunded = false;
    let roomInstance: MatchRoom;

    const mockUserProfile = {
      spendCoins: async () => {
        // Ağ gecikmesi simülasyonu: bu sırada sıra değişmiş olsun
        const baseState = deserializeMatchState((roomInstance as any).data.engineState);
        const state = {
          ...baseState,
          turnPlayerId: 'p2', // Sıra p2'ye kaydı
        };
        (roomInstance as any).data.engineState = serializeMatchState(state);
        return { success: true, coins: 50 };
      },
      refundPowerup: async (params: any) => {
        if (params.powerup === 'give_answer' && params.amount === 50) {
          refunded = true;
        }
        return { ok: true, refunded: true, coins: 100 };
      },
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    roomInstance = new MatchRoom(ctx, env as Env);
    await roomInstance.initMatch({
      matchId: 'm_race',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });
    await (roomInstance as any).handlePlayerConnected('p1');
    await (roomInstance as any).handlePlayerConnected('p2');

    sentP1.length = 0;
    await roomInstance.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    expect(refunded).toBe(true);
    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack).toBeDefined();
    expect(ack.success).toBe(false);
    expect(ack.code).toBe('round_not_active');
    expect(ack.message).toContain('iade');
  });

  it('6. Alias ile daha önce söylenmiş bir cevap tekrar seçilmez', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => ({ success: true, coins: 50 }),
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_alias_test',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p1 önce 'angara' alias'ını söylesin (ankara usedAnswerIds'e girecek)
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'angara' }));

    // Şimdi sıra p2'de; p2 give_answer kullansın
    // rng hep ilk elemanı seçsin
    room.setRngForTest(() => 0);

    sentP1.length = 0;
    // Kalanlar: istanbul, izmir, bursa. Ankara ASLA seçilmemeli!
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    const stateP1 = [...sentP1].reverse().find((m) => m.t === 'state');
    expect(stateP1).toBeDefined();
    const lastAttempt = stateP1.attempts[stateP1.attempts.length - 1];
    expect(lastAttempt.text).not.toBe('Ankara');
    expect(lastAttempt.text).toBe('İstanbul'); // Kalan ilk kullanılmamış
  });

  it('7. Son kalan cevap give_answer ile otomatik oynanırsa mevcut exhausted davranışı berabere ile biter', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => ({ success: true, coins: 50 }),
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_exhausted',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [twoAnswerQuestion],
      questionOrder: ['q_two'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p1 ilk cevabı ('Elma') söylesin
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'Elma' }));

    // Sıra p2'de. Kalan tek cevap 'Armut'. p2 give_answer kullansın
    sentP1.length = 0;
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    // Tur exhausted (berabere) olarak bitmeli
    const lastState = [...sentP1].reverse().find((m) => m.t === 'state');
    expect(lastState).toBeDefined();
    expect(lastState.phase).toBe('roundEnded');
    expect(lastState.lastRound?.draw).toBe(true);
    expect(lastState.lastRound?.reason).toBe('exhausted');
  });

  it('8. Hız sınırı: Yanlış cevaptan hemen sonra güçlendirici tooFast engeline takılmaz; normal submit takılmaya devam eder; istemci submit mesajıyla isSystemPowerup tetiklenemez', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => ({ success: true, coins: 50 }),
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_rate_limit',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // 1. Yanlış cevap gönder
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'YanlisKelime' }));

    // 2. 10 ms sonra hemen normal submit dene -> tooFast ile yoksayılmalı
    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'IkinciKelime' }));
    const fb = sentP1.find((m) => m.t === 'feedback');
    expect(fb).toBeDefined();
    expect(fb.kind).toBe('ignored');
    expect(fb.reason).toBe('tooFast');

    // 3. İstemci hile yapıp { t: 'submit', text: 'Ankara', isSystemPowerup: true } gönderse bile protokol bunu dikkate almaz
    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'Ankara', isSystemPowerup: true }));
    const fbCheat = sentP1.find((m) => m.t === 'feedback');
    expect(fbCheat).toBeDefined();
    expect(fbCheat.kind).toBe('ignored');
    expect(fbCheat.reason).toBe('tooFast');

    // 4. Ancak sunucu içi give_answer güçlendiricisi hemen tetiklenirse tooFast'a takılmaz ve başarıyla çalışır
    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));
    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack).toBeDefined();
    expect(ack.success).toBe(true);
  });

  it('9. Rakibe opponent_powerup mesajı GÖNDERİLMEDİĞİNİ doğrula (eski istemciler +5 sn zannetmesin)', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => ({ success: true, coins: 50 }),
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_no_opp_powerup',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [multiAnswerQuestion],
      questionOrder: ['q_multi'],
    });
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    sentP2.length = 0;
    // p1 give_answer kullanır
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'give_answer' }));

    // p2'ye giden mesajlar arasında opponent_powerup KESİNLİKLE OLMAMALI
    const oppPowerupMsg = sentP2.find((m) => m.t === 'opponent_powerup');
    expect(oppPowerupMsg).toBeUndefined();

    // Ancak p2'ye güncel state gitmiş olmalı
    const stateMsg = sentP2.find((m) => m.t === 'state');
    expect(stateMsg).toBeDefined();
  });
});
