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

const sampleQuestion: Question = {
  id: 'q1',
  categoryId: 'c1',
  text: 'Soru 1',
  answers: [{ id: 'a1', display: 'Cevap 1', aliases: ['cevap1'] }],
};

describe('Ek Süre Güçlendiricisi - UserProfile spendCoins & refundPowerup Tests', () => {
  it('1. spendCoins başarılı harcamada bakiyeden 30 düşer, bakiye güncellenir', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, { START_COINS: '100' } as Env);

    const res = await up.spendCoins({
      matchId: 'm_test_1',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_1',
    });

    expect(res.success).toBe(true);
    expect(res.coins).toBe(70);

    const profile = await up.getProfile();
    expect(profile.coins).toBe(70);
  });

  it('2. Yetersiz bakiyede spendCoins reddedilir, bakiye negatif olamaz ve değişmez', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, { START_COINS: '20' } as Env);

    const res = await up.spendCoins({
      matchId: 'm_test_2',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_broke',
    });

    expect(res.success).toBe(false);
    expect(res.error).toBe('not_enough_coins');
    expect(res.coins).toBe(20);

    const profile = await up.getProfile();
    expect(profile.coins).toBe(20);
  });

  it('3. spendCoins idempotenttir: aynı (matchId, powerup) için ikinci çağrı tekrar jeton düşmez', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, { START_COINS: '100' } as Env);

    const res1 = await up.spendCoins({
      matchId: 'm_test_idem',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_idem',
    });
    expect(res1.success).toBe(true);
    expect(res1.coins).toBe(70);

    const res2 = await up.spendCoins({
      matchId: 'm_test_idem',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_idem',
    });
    expect(res2.success).toBe(true);
    expect(res2.alreadySpent).toBe(true);
    expect(res2.coins).toBe(70);

    const profile = await up.getProfile();
    expect(profile.coins).toBe(70);
  });

  it('4. Silinmiş hesapta (tombstone) spendCoins account_deleted döner', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, { START_COINS: '100' } as Env);
    await up.deleteProfile('user_deleted');

    const res = await up.spendCoins({
      matchId: 'm_test_del',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_deleted',
    });
    expect(res.success).toBe(false);
    expect(res.error).toBe('account_deleted');
  });

  it('5. refundPowerup atomik ve idempotenttir: jetonu iade eder, mükerrer çağrıda ikinci kez iade yapmaz', async () => {
    const ctx = createMockProfileCtx();
    const up = new UserProfile(ctx, { START_COINS: '100' } as Env);

    await up.spendCoins({
      matchId: 'm_refund_test',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_refund',
    });
    expect((await up.getProfile()).coins).toBe(70);

    // İlk iade
    const ref1 = await up.refundPowerup({
      matchId: 'm_refund_test',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_refund',
    });
    expect(ref1.ok).toBe(true);
    expect(ref1.refunded).toBe(true);
    expect(ref1.coins).toBe(100);

    // Mükerrer iade (idempotent kontrol)
    const ref2 = await up.refundPowerup({
      matchId: 'm_refund_test',
      powerup: 'extra_time',
      amount: 30,
      uid: 'user_refund',
    });
    expect(ref2.ok).toBe(true);
    expect(ref2.refunded).toBe(false);
    expect(ref2.coins).toBe(100);
  });
});

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

describe('Ek Süre Güçlendiricisi - MatchRoom Turn & Race Condition Tests', () => {
  it('6. Sıra bendeyken use_powerup çağrısı: süre 5 sn uzar, alarm ötelenir, rakibe bildirim gider', async () => {
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
        return { success: true, coins: 70 };
      },
      refundPowerup: async () => ({ ok: true, refunded: true, coins: 100 }),
    };

    const env: Partial<Env> = {
      EXTRA_TIME_COST: '30',
      EXTRA_TIME_SECONDS: '5',
      USER_PROFILE: {
        idFromName: () => 'id_p1' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_room_1',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    // Oyuncuları bağla
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Başlangıç deadline'ını al
    const stateMsg = sentP1.find((m) => m.t === 'state');
    expect(stateMsg).toBeDefined();
    expect(stateMsg.turnIsMine).toBe(true);
    const initialDeadline = stateMsg.deadlineMs;

    // p1 ek süre kullansın
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));

    expect(spendCoinsCalled).toBe(true);

    // p1'e powerup_ack onay mesajı gelmeli
    const ackMsg = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ackMsg).toBeDefined();
    expect(ackMsg.success).toBe(true);
    expect(ackMsg.deadlineMs).toBe(initialDeadline + 5000);
    expect(ackMsg.coins).toBe(70);

    // p2'ye opponent_powerup bildirimi gitmeli
    const oppMsg = sentP2.find((m) => m.t === 'opponent_powerup');
    expect(oppMsg).toBeDefined();
    expect(oppMsg.seconds).toBe(5);

    // İkinci kullanım denenirse reddedilmeli
    sentP1.length = 0;
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));
    const rejectedAck = sentP1.find((m) => m.t === 'powerup_ack');
    expect(rejectedAck.success).toBe(false);
    expect(rejectedAck.code).toBe('already_used');
  });

  it('7. Sıra rakipteyken ek süre çağrısı reddedilir, jeton düşülmez', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP2: any[] = [];
    const ws1 = createMockSocket('p1', []);
    const ws2 = createMockSocket('p2', sentP2);
    sockets.push(ws1, ws2);

    let spendCoinsCalled = false;
    const mockUserProfile = {
      spendCoins: async () => {
        spendCoinsCalled = true;
        return { success: true, coins: 70 };
      },
    };

    const env: Partial<Env> = {
      USER_PROFILE: {
        idFromName: () => 'id_p2' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_room_not_turn',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p2 sırası değilken çağırsın
    await room.webSocketMessage(ws2 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));

    expect(spendCoinsCalled).toBe(false);
    const ack = sentP2.find((m) => m.t === 'powerup_ack');
    expect(ack.success).toBe(false);
    expect(ack.code).toBe('not_your_turn');
  });

  it('8. Arkadaş maçında ek süre çağrısı reddedilir', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', []);
    sockets.push(ws1, ws2);

    const room = new MatchRoom(ctx, {} as Env);
    await room.initMatch({
      matchId: 'm_room_friendly',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
      matchType: 'friendly',
    });

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));

    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack.success).toBe(false);
    expect(ack.code).toBe('not_allowed_in_match_type');
  });

  it('9. Kural 3: spendCoins alreadySpent döndüğünde powerupsUsed kayıtlı değilse süre uzatmayı yine uygular', async () => {
    const { ctx, sockets } = createMockRoomCtx();
    const sentP1: any[] = [];
    const ws1 = createMockSocket('p1', sentP1);
    const ws2 = createMockSocket('p2', []);
    sockets.push(ws1, ws2);

    const mockUserProfile = {
      spendCoins: async () => {
        // Simüle edilen durum: jeton DO'da önceden düşülmüş (alreadySpent: true)
        return { success: true, coins: 70, alreadySpent: true };
      },
    };

    const env: Partial<Env> = {
      EXTRA_TIME_COST: '30',
      EXTRA_TIME_SECONDS: '5',
      USER_PROFILE: {
        idFromName: () => 'id_p1' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    await room.initMatch({
      matchId: 'm_room_alreadyspent',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    const stateMsg = sentP1.find((m) => m.t === 'state');
    const initialDeadline = stateMsg.deadlineMs;

    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));

    const ack = sentP1.find((m) => m.t === 'powerup_ack');
    expect(ack.success).toBe(true);
    expect(ack.deadlineMs).toBe(initialDeadline + 5000);
  });

  it('10. Kural 1: refundPowerup ağ hatası alırsa pendingRefunds ve refundRetryAtMs kaydedilir, alarm sonrası tekrar denenir', async () => {
    let fakeNow = 1000000;
    const nowSpy = vi.spyOn(Date, 'now').mockImplementation(() => fakeNow);

    const { ctx, sockets, getAlarm } = createMockRoomCtx();
    const ws1 = createMockSocket('p1', []);
    const ws2 = createMockSocket('p2', []);
    sockets.push(ws1, ws2);

    let refundAttempts = 0;
    let roomRef: MatchRoom;
    const mockUserProfile = {
      spendCoins: async () => {
        // spendCoins çağrısı sürerken yarış durumu simülasyonu: maç arka planda bitsin
        await (roomRef as any).handleMatchFinished();
        return { success: true, coins: 70 };
      },
      refundPowerup: async () => {
        refundAttempts++;
        if (refundAttempts === 1) {
          throw new Error('Durable Object temporary error');
        }
        return { ok: true, refunded: true, coins: 100 };
      },
      applyMatchReward: async () => ({ coinsAwarded: 0, coins: 70 }),
    };

    const env: Partial<Env> = {
      EXTRA_TIME_COST: '30',
      EXTRA_TIME_SECONDS: '5',
      USER_PROFILE: {
        idFromName: () => 'id_p1' as any,
        get: () => mockUserProfile as any,
      } as any,
    };

    const room = new MatchRoom(ctx, env as Env);
    roomRef = room;
    await room.initMatch({
      matchId: 'm_room_refund_retry',
      p1: { uid: 'p1', name: 'Alice' },
      p2: { uid: 'p2', name: 'Bob' },
      questions: [sampleQuestion],
      questionOrder: ['q1'],
    });

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p1 güçlendirici çağrısını başlatsın -> spendCoins sırasında maç biter, post-check başarısız olup refund tetiklenir
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));

    // İlk iade denemesi geçici hatayla karşılaştı
    expect(refundAttempts).toBe(1);

    // Alarm kurulduğunu doğrula
    const alarmTime = getAlarm();
    expect(alarmTime).not.toBeNull();

    // Alarm vadesine ilerlet ve alarmı tetikle
    fakeNow = alarmTime! + 100;
    await (room as any).alarm();

    // İkinci deneme başarılı oldu
    expect(refundAttempts).toBe(2);

    nowSpy.mockRestore();
  });

  it('11. DO SQLite kısıtı: spendCoins ve refundPowerup transactionSync kullanır; sql.exec("BEGIN TRANSACTION") çağrılmaz', async () => {
    const profileCtx = createMockProfileCtx();
    const env: Partial<Env> = {
      START_COINS: '100',
    };
    const profile = new UserProfile(profileCtx, env as Env);
    await profile.getProfile('p_strict_tx');

    // 1. spendCoins çağrısının manual BEGIN çağırmadan transactionSync ile çalıştığını doğrula
    const spendRes = await profile.spendCoins({
      matchId: 'm_tx_test',
      powerup: 'extra_time',
      amount: 30,
      uid: 'p_strict_tx',
    });
    expect(spendRes.success).toBe(true);
    expect(spendRes.coins).toBe(70);

    // 2. refundPowerup çağrısının da manual BEGIN çağırmadan çalıştığını doğrula
    const refundRes = await profile.refundPowerup({
      matchId: 'm_tx_test',
      powerup: 'extra_time',
      amount: 30,
      uid: 'p_strict_tx',
    });
    expect(refundRes.ok).toBe(true);
    expect(refundRes.refunded).toBe(true);
    expect(refundRes.coins).toBe(100);

    // 3. Doğrudan manual BEGIN TRANSACTION çağrılırsa mock SQLite'ın bunu Cloudflare DO gibi fırlattığını doğrula
    expect(() => {
      (profileCtx.storage as any).sql.exec('BEGIN TRANSACTION');
    }).toThrow('The Durable Object storage SQLite database does not allow manual transactions');
  });
});
