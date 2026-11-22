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

import { evaluateAchievements } from '../src/achievements/definitions';
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
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('PRAGMA')
      ) {
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
    rawDb: db,
    ctx: {
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
    } as unknown as DurableObjectState,
  };
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

describe('Achievements - evaluateAchievements (Saf Mantık)', () => {
  it('Eşik altındayken hiçbir başarım açılmaz', () => {
    const unlocked = new Set<string>();
    const res = evaluateAchievements(
      { played: 0, won: 0, currentStreak: 0, maxStreak: 0 },
      unlocked
    );
    expect(res).toEqual([]);
  });

  it('İlk maç tamamlandığında first_match açılır', () => {
    const unlocked = new Set<string>();
    const res = evaluateAchievements(
      { played: 1, won: 0, currentStreak: 0, maxStreak: 0 },
      unlocked
    );
    expect(res).toEqual(['first_match']);
  });

  it('İlk galibiyet alındığında first_match ve first_win birlikte açılır (order sırasıyla)', () => {
    const unlocked = new Set<string>();
    const res = evaluateAchievements(
      { played: 1, won: 1, currentStreak: 1, maxStreak: 1 },
      unlocked
    );
    // first_match order: 1, first_win order: 5, streak_3 eşiği 3 henüz geçilmedi
    expect(res).toEqual(['first_match', 'first_win']);
  });

  it('Zaten açılmış başarımlar tekrar dönmez', () => {
    const unlocked = new Set<string>(['first_match', 'first_win']);
    const res = evaluateAchievements(
      { played: 5, won: 2, currentStreak: 2, maxStreak: 2 },
      unlocked
    );
    expect(res).toEqual([]);
  });

  it('Seri galibiyetler (streak_3, streak_5, streak_10) maxStreak veya currentStreak ile açılır', () => {
    const unlocked = new Set<string>(['first_match', 'first_win']);
    const res3 = evaluateAchievements(
      { played: 3, won: 3, currentStreak: 3, maxStreak: 3 },
      unlocked
    );
    expect(res3).toEqual(['streak_3']);

    unlocked.add('streak_3');
    // current_streak 0'a düşse bile maxStreak 5 ise streak_5 açılır
    const res5 = evaluateAchievements(
      { played: 6, won: 5, currentStreak: 0, maxStreak: 5 },
      unlocked
    );
    expect(res5).toEqual(['streak_5']);
  });

  it('Toplu eşik atlamada başarımlar order değerine göre sıralı döner', () => {
    const unlocked = new Set<string>();
    // played=100, won=100, streak=10 -> tüm 11 başarım açılır
    const all = evaluateAchievements(
      { played: 100, won: 100, currentStreak: 10, maxStreak: 10 },
      unlocked
    );
    expect(all).toEqual([
      'first_match',
      'matches_10',
      'matches_50',
      'matches_100',
      'first_win',
      'wins_10',
      'wins_50',
      'wins_100',
      'streak_3',
      'streak_5',
      'streak_10',
    ]);
  });

  it('Opsiyonel matchContext parametresi hata vermeden kabul edilir', () => {
    const unlocked = new Set<string>();
    const res = evaluateAchievements(
      { played: 1, won: 0, currentStreak: 0, maxStreak: 0 },
      unlocked,
      { isWin: false, isLoss: true }
    );
    expect(res).toEqual(['first_match']);
  });
});

describe('Achievements - UserProfile SQLite Entegrasyonu & applyMatchReward', () => {
  it('1. İlk maç (mağlubiyet): first_match açılır, streak 0 kalır', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('alice');

    const result = await profileDO.applyMatchReward({
      uid: 'alice',
      matchId: 'm1',
      outcome: 'loss',
    });

    expect(result.unlockedAchievements).toEqual(['first_match']);
    expect(result.alreadyProcessed).toBeFalsy();

    const profile = await profileDO.getProfile('alice');
    expect(profile.stats.played).toBe(1);
    expect(profile.stats.won).toBe(0);
    expect(profile.stats.lost).toBe(1);
    expect(profile.currentStreak).toBe(0);
    expect(profile.maxStreak).toBe(0);
    expect(profile.achievements!.map((a) => a.id)).toEqual(['first_match']);
  });

  it('2. İlk galibiyet: first_match ve first_win açılır, streak 1 olur', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('bob');

    const result = await profileDO.applyMatchReward({
      uid: 'bob',
      matchId: 'm1',
      outcome: 'win',
    });

    expect(result.unlockedAchievements).toEqual(['first_match', 'first_win']);
    const profile = await profileDO.getProfile('bob');
    expect(profile.stats.played).toBe(1);
    expect(profile.stats.won).toBe(1);
    expect(profile.currentStreak).toBe(1);
    expect(profile.maxStreak).toBe(1);
  });

  it('3. Üç ardışık galibiyet: streak_3 açılır', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('charlie');

    // 1. Galibiyet
    const r1 = await profileDO.applyMatchReward({
      uid: 'charlie',
      matchId: 'm1',
      outcome: 'win',
    });
    expect(r1.unlockedAchievements).toEqual(['first_match', 'first_win']);

    // 2. Galibiyet
    const r2 = await profileDO.applyMatchReward({
      uid: 'charlie',
      matchId: 'm2',
      outcome: 'win',
    });
    expect(r2.unlockedAchievements).toEqual([]);

    // 3. Galibiyet
    const r3 = await profileDO.applyMatchReward({
      uid: 'charlie',
      matchId: 'm3',
      outcome: 'win',
    });
    expect(r3.unlockedAchievements).toEqual(['streak_3']);

    const profile = await profileDO.getProfile('charlie');
    expect(profile.currentStreak).toBe(3);
    expect(profile.maxStreak).toBe(3);
  });

  it('4. Mağlubiyet seriyi 0 yapar, ancak maxStreak korunur', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('dave');

    // 3 Galibiyet
    for (let i = 1; i <= 3; i++) {
      await profileDO.applyMatchReward({
        uid: 'dave',
        matchId: `m${i}`,
        outcome: 'win',
      });
    }

    // 4. Maç Mağlubiyet
    const r4 = await profileDO.applyMatchReward({
        uid: 'dave',
        matchId: 'm4',
        outcome: 'loss',
    });
    expect(r4.unlockedAchievements).toEqual([]);

    const profile = await profileDO.getProfile('dave');
    expect(profile.currentStreak).toBe(0);
    expect(profile.maxStreak).toBe(3);
  });

  it('5. Hükmen/kopma galibiyeti (win_by_opponent_disconnect) seriyi artırır', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('eva');

    await profileDO.applyMatchReward({
      uid: 'eva',
      matchId: 'm1',
      outcome: 'win',
    });
    await profileDO.applyMatchReward({
      uid: 'eva',
      matchId: 'm2',
      outcome: 'win_by_opponent_disconnect',
    });

    const profile = await profileDO.getProfile('eva');
    expect(profile.stats.won).toBe(2);
    expect(profile.currentStreak).toBe(2);
    expect(profile.maxStreak).toBe(2);
  });

  it('6. Kopma mağlubiyeti (loss_by_disconnect) seriyi 0 yapar', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('frank');

    await profileDO.applyMatchReward({
      uid: 'frank',
      matchId: 'm1',
      outcome: 'win',
    });
    await profileDO.applyMatchReward({
      uid: 'frank',
      matchId: 'm2',
      outcome: 'loss_by_disconnect',
    });

    const profile = await profileDO.getProfile('frank');
    expect(profile.stats.lost).toBe(1);
    expect(profile.currentStreak).toBe(0);
    expect(profile.maxStreak).toBe(1);
  });

  it('7. Idempotency & Retry: Aynı matchId tekrar işlendiğinde sayaç artmaz ve aynı başarımlar döner', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('grace');

    const r1 = await profileDO.applyMatchReward({
      uid: 'grace',
      matchId: 'm1',
      outcome: 'win',
    });
    expect(r1.unlockedAchievements).toEqual(['first_match', 'first_win']);
    expect(r1.alreadyProcessed).toBeFalsy();

    // Tekrar çağrı (retry)
    const r2 = await profileDO.applyMatchReward({
      uid: 'grace',
      matchId: 'm1',
      outcome: 'win',
    });
    expect(r2.alreadyProcessed).toBe(true);
    expect(r2.unlockedAchievements).toEqual(['first_match', 'first_win']);

    const profile = await profileDO.getProfile('grace');
    expect(profile.stats.played).toBe(1);
    expect(profile.stats.won).toBe(1);
    expect(profile.currentStreak).toBe(1);
    expect(profile.achievements!.length).toBe(2);
  });

  it('8. Sessiz Backfill (Silent Backfill): Mevcut kullanıcının eski istatistikleri açılır ancak bu maçın açılanlarına girmez', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv();

    rawDb.exec(`
      CREATE TABLE profiles (
        uid TEXT PRIMARY KEY,
        nickname TEXT,
        coins INTEGER NOT NULL DEFAULT 100,
        played INTEGER NOT NULL DEFAULT 0,
        won INTEGER NOT NULL DEFAULT 0,
        lost INTEGER NOT NULL DEFAULT 0,
        correct_answers INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        equipped_frame TEXT NOT NULL DEFAULT 'classic',
        is_guest INTEGER NOT NULL DEFAULT 0,
        current_streak INTEGER NOT NULL DEFAULT 0,
        max_streak INTEGER NOT NULL DEFAULT 0,
        achievements_initialized INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE processed_matches (
        match_id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        outcome TEXT NOT NULL,
        coins_awarded INTEGER NOT NULL
      );
      CREATE TABLE user_achievements (
        id TEXT PRIMARY KEY,
        unlocked_at INTEGER NOT NULL,
        match_id TEXT NOT NULL
      );
      INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, achievements_initialized)
      VALUES ('legacy_user', 'EskiOyuncu', 500, 65, 32, 33, 150, 100000, 0);
    `);

    const profileDO = new UserProfile(ctx, env);

    // Yeni bir ranked galibiyet maçı işlensin
    const result = await profileDO.applyMatchReward({
      uid: 'legacy_user',
      matchId: 'new_match_1',
      outcome: 'win',
    });

    // 65 played -> first_match, matches_10, matches_50 backfill ile açılmıştır.
    // 32 won -> first_win, wins_10 backfill ile açılmıştır.
    // Yeni maçla: played 66, won 33. Yeni bir eşik geçilmedi! Dolayısıyla unlockedAchievements BOŞ olmalıdır.
    expect(result.unlockedAchievements).toEqual([]);

    // Profil sorgulandığında tüm geçmiş başarımların mevcut olduğu görülmeli
    const profile = await profileDO.getProfile('legacy_user');
    expect(profile.stats.played).toBe(66);
    expect(profile.stats.won).toBe(33);
    expect(profile.currentStreak).toBe(1);
    expect(profile.maxStreak).toBe(1);

    const ids = profile.achievements!.map((a) => a.id).sort();
    expect(ids).toEqual([
      'first_match',
      'first_win',
      'matches_10',
      'matches_50',
      'wins_10',
    ]);

    // Veritabanında backfill kayıtlarının match_id = 'backfill' olduğunu doğrula
    const rows = rawDb
      .prepare('SELECT id, match_id FROM user_achievements ORDER BY id')
      .all() as { id: string; match_id: string }[];
    expect(rows.length).toBe(5);
    for (const r of rows) {
      expect(r.match_id).toBe('backfill');
    }
  });

  it('9. getProfile sessiz backfill: Eski kullanıcı maça girmeden önce profilini açarsa başarımlarını görür', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv();

    rawDb.exec(`
      CREATE TABLE profiles (
        uid TEXT PRIMARY KEY,
        nickname TEXT,
        coins INTEGER NOT NULL DEFAULT 100,
        played INTEGER NOT NULL DEFAULT 0,
        won INTEGER NOT NULL DEFAULT 0,
        lost INTEGER NOT NULL DEFAULT 0,
        correct_answers INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        equipped_frame TEXT NOT NULL DEFAULT 'classic',
        is_guest INTEGER NOT NULL DEFAULT 0,
        current_streak INTEGER NOT NULL DEFAULT 0,
        max_streak INTEGER NOT NULL DEFAULT 0,
        achievements_initialized INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE processed_matches (
        match_id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        outcome TEXT NOT NULL,
        coins_awarded INTEGER NOT NULL
      );
      CREATE TABLE user_achievements (
        id TEXT PRIMARY KEY,
        unlocked_at INTEGER NOT NULL,
        match_id TEXT NOT NULL
      );
      INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, achievements_initialized)
      VALUES ('browser_user', 'ProfilBakan', 500, 10, 10, 0, 50, 100000, 0);
    `);

    const profileDO = new UserProfile(ctx, env);

    const p1 = await profileDO.getProfile('browser_user');
    expect(p1.achievements!.map((a) => a.id).sort()).toEqual([
      'first_match',
      'first_win',
      'matches_10',
      'wins_10',
    ]);

    // İkinci çağrıda tekrar ekleme yapılmaz
    const p2 = await profileDO.getProfile('browser_user');
    expect(p2.achievements!.length).toBe(4);
  });

  it('10. Atomicity & Rollback: İşlem sırasında hata olursa processed_matches yazılmaz ve rollback yapılır', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('err_user');

    (profileDO as any).ctx.storage.sql.exec(`
      CREATE TRIGGER trigger_fail_achievements
      BEFORE INSERT ON user_achievements
      BEGIN
        SELECT RAISE(FAIL, 'Simulated SQLite failure');
      END;
    `);

    await expect(
      profileDO.applyMatchReward({
        uid: 'err_user',
        matchId: 'm_err',
        outcome: 'win',
      })
    ).rejects.toThrow('Simulated SQLite failure');

    // processed_matches yazılmamış olmalı ki retry edilebilsin
    const rows = (profileDO as any).ctx.storage.sql
      .exec('SELECT * FROM processed_matches WHERE match_id = ?', 'm_err')
      .toArray();
    expect(rows.length).toBe(0);

    // Profil de güncellenmemiş olmalı (rollback)
    const profile = await profileDO.getProfile('err_user');
    expect(profile.stats.played).toBe(0);
    expect(profile.stats.won).toBe(0);
  });

  it('11. deleteProfile user_achievements tablosunu temizler, hesap silinmiş döner (410)', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('del_user');
    await profileDO.applyMatchReward({
      uid: 'del_user',
      matchId: 'm1',
      outcome: 'win',
    });

    const pBefore = await profileDO.getProfile('del_user');
    expect(pBefore.achievements!.length).toBeGreaterThan(0);

    await profileDO.deleteProfile('del_user');

    // user_achievements tablosu boşaltılmış olmalı
    const rows = (profileDO as any).ctx.storage.sql
      .exec('SELECT * FROM user_achievements')
      .toArray();
    expect(rows.length).toBe(0);

    // Silinmiş profile getProfile çağrıldığında 410 hatası verir, satır yeniden oluşturulmaz
    await expect(profileDO.getProfile('del_user')).rejects.toThrow('account_deleted');
  });

  it('12. applyResultToCounters bağımsız fonksiyonu solo/bot veya harici maçlar için doğru çalışır', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('solo_user');

    // 1. Maç galibiyet
    const r1 = profileDO.applyResultToCounters({
      matchId: 'solo_1',
      isWin: true,
      isLoss: false,
      source: 'solo',
      correctCount: 4,
    });
    expect(r1.unlockedAchievements).toEqual(['first_match', 'first_win']);
    expect(r1.currentStreak).toBe(1);
    expect(r1.maxStreak).toBe(1);

    // 2. Maç galibiyet
    const r2 = profileDO.applyResultToCounters({
      matchId: 'solo_2',
      isWin: true,
      isLoss: false,
      source: 'solo',
      correctCount: 3,
    });
    expect(r2.unlockedAchievements).toEqual([]);
    expect(r2.currentStreak).toBe(2);

    // 3. Maç galibiyet -> streak_3
    const r3 = profileDO.applyResultToCounters({
      matchId: 'solo_3',
      isWin: true,
      isLoss: false,
      source: 'solo',
    });
    expect(r3.unlockedAchievements).toEqual(['streak_3']);
    expect(r3.currentStreak).toBe(3);

    // 4. Maç mağlubiyet -> streak sıfırlanır
    const r4 = profileDO.applyResultToCounters({
      matchId: 'solo_4',
      isWin: false,
      isLoss: true,
      source: 'solo',
    });
    expect(r4.currentStreak).toBe(0);
    expect(r4.maxStreak).toBe(3);

    const profile = await profileDO.getProfile('solo_user');
    expect(profile.stats.played).toBe(4);
    expect(profile.stats.won).toBe(3);
    expect(profile.stats.lost).toBe(1);
    expect(profile.stats.correctAnswers).toBe(7);
  });
});
