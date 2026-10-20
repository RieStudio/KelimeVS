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
import type { Env } from '../src/index';

function createMockCtx() {
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
      if (trimmed.toUpperCase().startsWith('SELECT')) {
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
    },
  } as unknown as DurableObjectState;
}

function createEnv(overrides?: Partial<Env>): Env {
  return {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    START_COINS: '100',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    DISCONNECT_WIN_COINS: '30',
    DISCONNECT_LOSS_COINS: '0',
    DAILY_MATCH_COIN_CAP: '300',
    ...overrides,
  };
}

describe('UserProfile Durable Object - SQLite & Ekonomi Kuralları', () => {
  it('1. Yeni kullanıcı profili başlangıç bakiyesiyle oluşturulur', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    const profile = await profileDO.getProfile('user_alice');
    expect(profile.uid).toBe('user_alice');
    expect(profile.nickname).toBeNull();
    expect(profile.coins).toBe(100);
    expect(profile.stats).toEqual({ played: 0, won: 0, lost: 0 });
    expect(profile.createdAt).toBeGreaterThan(0);
  });

  it('2. START_COINS ortam değişkeni farklı verilirse o değer esas alınır', async () => {
    const ctx = createMockCtx();
    const env = createEnv({ START_COINS: '250' });
    const profileDO = new UserProfile(ctx, env);

    const profile = await profileDO.getProfile('user_bob');
    expect(profile.coins).toBe(250);
  });

  it('3. Takma ad doğrulama kurallarına göre güncellenir veya reddedilir', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    // Geçerli ad
    const res = await profileDO.setNickname('  Ahmet_10  ', 'user_1');
    expect(res.ok).toBe(true);
    expect(res.nickname).toBe('Ahmet_10');

    const updated = await profileDO.getProfile('user_1');
    expect(updated.nickname).toBe('Ahmet_10');

    // Geçersiz ad (2 karakter, çok kısa)
    await expect(profileDO.setNickname('ab', 'user_1')).rejects.toThrow('invalid_nickname');

    // Geçersiz ad (yasak karakter)
    await expect(profileDO.setNickname('User@123', 'user_1')).rejects.toThrow('invalid_nickname');
  });

  it('4. applyMatchReward galibiyet, mağlubiyet ve kopma ödüllerini doğru uygular', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    // Başlangıç: 100 jeton
    // 1. Normal Galibiyet (+30)
    const r1 = await profileDO.applyMatchReward({
      matchId: 'match_1',
      outcome: 'win',
      uid: 'user_1',
    });
    expect(r1.coinsAwarded).toBe(30);
    expect(r1.coins).toBe(130);

    // 2. Normal Mağlubiyet (+5)
    const r2 = await profileDO.applyMatchReward({
      matchId: 'match_2',
      outcome: 'loss',
      uid: 'user_1',
    });
    expect(r2.coinsAwarded).toBe(5);
    expect(r2.coins).toBe(135);

    // 3. Rakip bağlantısı koptuğu için galibiyet (+30)
    const r3 = await profileDO.applyMatchReward({
      matchId: 'match_3',
      outcome: 'win_by_opponent_disconnect',
      uid: 'user_1',
    });
    expect(r3.coinsAwarded).toBe(30);
    expect(r3.coins).toBe(165);

    // 4. Kendi bağlantısı koptuğu için mağlubiyet (+0)
    const r4 = await profileDO.applyMatchReward({
      matchId: 'match_4',
      outcome: 'loss_by_disconnect',
      uid: 'user_1',
    });
    expect(r4.coinsAwarded).toBe(0);
    expect(r4.coins).toBe(165);

    const stats = (await profileDO.getProfile('user_1')).stats;
    expect(stats.played).toBe(4);
    expect(stats.won).toBe(2);
    expect(stats.lost).toBe(2);
  });

  it('5. İdempotentlik: Aynı matchId için ödül ve istatistik asla ikinci kez yazılmaz', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    // İlk çağrı
    const firstCall = await profileDO.applyMatchReward({
      matchId: 'match_idempotent_test',
      outcome: 'win',
      uid: 'user_1',
    });
    expect(firstCall.coinsAwarded).toBe(30);
    expect(firstCall.coins).toBe(130);

    // İkinci çağrı (aynı matchId)
    const secondCall = await profileDO.applyMatchReward({
      matchId: 'match_idempotent_test',
      outcome: 'win',
      uid: 'user_1',
    });
    expect(secondCall.alreadyProcessed).toBe(true);
    expect(secondCall.coinsAwarded).toBe(30);
    expect(secondCall.coins).toBe(130);

    const profile = await profileDO.getProfile('user_1');
    expect(profile.coins).toBe(130);
    expect(profile.stats.played).toBe(1);
    expect(profile.stats.won).toBe(1);
  });

  it('6. Günlük kazanç üst sınırı (DAILY_MATCH_COIN_CAP = 300) aşılamaz', async () => {
    const ctx = createMockCtx();
    const env = createEnv({ DAILY_MATCH_COIN_CAP: '300' });
    const profileDO = new UserProfile(ctx, env);

    // 9 maç galibiyet = 9 * 30 = 270 jeton
    for (let i = 1; i <= 9; i++) {
      await profileDO.applyMatchReward({
        matchId: `m_${i}`,
        outcome: 'win',
        uid: 'user_cap',
      });
    }

    // 10. maç: 300'e tamamlar (30 jeton alır, toplam kazanılan 300)
    const r10 = await profileDO.applyMatchReward({
      matchId: 'm_10',
      outcome: 'win',
      uid: 'user_cap',
    });
    expect(r10.coinsAwarded).toBe(30);
    expect(r10.coins).toBe(100 + 300); // 400

    // 11. maç: Günlük sınır dolduğu için coinsAwarded = 0 olmalıdır
    const r11 = await profileDO.applyMatchReward({
      matchId: 'm_11',
      outcome: 'win',
      uid: 'user_cap',
    });
    expect(r11.coinsAwarded).toBe(0);
    expect(r11.coins).toBe(400);

    // İstatistik ise artmaya devam eder
    const profile = await profileDO.getProfile('user_cap');
    expect(profile.stats.played).toBe(11);
    expect(profile.stats.won).toBe(11);
  });
});

