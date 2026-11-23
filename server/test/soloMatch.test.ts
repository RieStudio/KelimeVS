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
import worker, { type Env } from '../src/index';
import {
  validateSoloMatchResult,
  MIN_SOLO_WIN_SECONDS,
  SOLO_DAILY_SAFETY_CAP,
  MAX_SOLO_CORRECT_ANSWERS,
  type SoloMatchResultBody,
} from '../src/soloMatch';

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
        trimmed.toUpperCase().startsWith('WITH') ||
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
        setAlarm: vi.fn(),
        getAlarm: vi.fn().mockResolvedValue(null),
        deleteAlarm: vi.fn(),
        deleteAll: vi.fn(),
      },
    } as any,
  };
}

function createEnv(overrides: Partial<Env> = {}) {
  const userProfiles = new Map<string, UserProfile>();
  const env: Env = {
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    DISCONNECT_WIN_COINS: '30',
    DISCONNECT_LOSS_COINS: '0',
    DAILY_MATCH_COIN_CAP: '300',
    ENERGY_ENABLED: 'true',
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    LEADERBOARD: {} as any,
    USER_PROFILE: {
      idFromName(name: string) {
        return { toString: () => name } as any;
      },
      get(id: { toString: () => string }) {
        const name = id.toString();
        if (!userProfiles.has(name)) {
          const { ctx } = createMockCtx();
          userProfiles.set(name, new UserProfile(ctx, env));
        }
        return userProfiles.get(name)!;
      },
    } as any,
    ...overrides,
  };
  return { env, userProfiles };
}

describe('Solo Match Result - Doğrulama Fonksiyonu (validateSoloMatchResult)', () => {
  const validWinBody: SoloMatchResultBody = {
    matchId: 'bot:a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    ticketId: 'stk_validticket12345678',
    outcome: 'win',
    myScore: 2,
    oppScore: 1,
    correctAnswers: 5,
    durationSeconds: 35,
    endedBy: 'normal',
  };

  it('Geçerli galibiyet gövdesi kabul edilir', () => {
    const res = validateSoloMatchResult(validWinBody);
    expect(res.isValid).toBe(true);
    expect(res.error).toBeUndefined();
    expect(res.data).toBeDefined();
  });

  it('Geçerli normal mağlubiyet gövdesi kabul edilir', () => {
    const res = validateSoloMatchResult({
      ...validWinBody,
      outcome: 'loss',
      myScore: 1,
      oppScore: 2,
      durationSeconds: 25,
      endedBy: 'normal',
    });
    expect(res.isValid).toBe(true);
    expect(res.error).toBeUndefined();
  });

  it('Geçerli çekilme (forfeit) mağlubiyet gövdesi kabul edilir', () => {
    const res = validateSoloMatchResult({
      ...validWinBody,
      outcome: 'loss',
      myScore: 0,
      oppScore: 1,
      durationSeconds: 10,
      endedBy: 'forfeit',
    });
    expect(res.isValid).toBe(true);
    expect(res.error).toBeUndefined();
  });

  describe('matchId format kontrolleri', () => {
    it('bot: öneki olmayan matchId reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        matchId: 'online:a1b2c3d4-e5f6-7890',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('bad_request');
    });

    it('Çok kısa matchId (< 8 karakter son ek) reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        matchId: 'bot:123',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('bad_request');
    });

    it('Çok uzun matchId (> 64 karakter son ek) reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        matchId: 'bot:' + 'a'.repeat(65),
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('bad_request');
    });

    it('Geçersiz karakter içeren matchId reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        matchId: 'bot:a1b2c3d4@#$!',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('bad_request');
    });
  });

  describe('Skor ve Sonuç Tutarlılığı (roundsToWin = 2)', () => {
    it('outcome=win ama myScore != 2 ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'win',
        myScore: 1,
        oppScore: 0,
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });

    it('outcome=win ama oppScore >= 2 ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'win',
        myScore: 2,
        oppScore: 2,
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });

    it('outcome=loss, endedBy=normal ama oppScore != 2 ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'loss',
        myScore: 1,
        oppScore: 1,
        endedBy: 'normal',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });

    it('outcome=loss, endedBy=normal ama myScore >= 2 ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'loss',
        myScore: 2,
        oppScore: 2,
        endedBy: 'normal',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });

    it('endedBy=forfeit iken outcome=win ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'win',
        endedBy: 'forfeit',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });

    it('endedBy=forfeit iken herhangi bir skor >= 2 ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'loss',
        myScore: 2,
        oppScore: 0,
        endedBy: 'forfeit',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_score');
    });
  });

  describe('Bilet, Süre ve Doğru Cevap Sınırları', () => {
    it('ticketId eksikse ticket_required hatası verir', () => {
      const { ticketId, ...noTicket } = validWinBody;
      const res = validateSoloMatchResult(noTicket);
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('ticket_required');
    });

    it('ticketId geçersiz karakter içeriyorsa ticket_invalid hatası verir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        ticketId: 'invalid ticket with spaces!',
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('ticket_invalid');
    });

    it('durationSeconds opsiyoneldir ve verilmediğinde de kabul edilir', () => {
      const { durationSeconds, ...noDuration } = validWinBody;
      const res = validateSoloMatchResult(noDuration);
      expect(res.isValid).toBe(true);
    });

    it('Mağlubiyette süre kısa olabilir (örn. hemen teslim olma)', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        outcome: 'loss',
        myScore: 0,
        oppScore: 1,
        durationSeconds: 3,
        endedBy: 'forfeit',
      });
      expect(res.isValid).toBe(true);
    });

    it('correctAnswers negatif ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        correctAnswers: -1,
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_answers');
    });

    it('correctAnswers ondalıklı ise reddedilir', () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        correctAnswers: 2.5,
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_answers');
    });

    it(`correctAnswers > ${MAX_SOLO_CORRECT_ANSWERS} ise reddedilir`, () => {
      const res = validateSoloMatchResult({
        ...validWinBody,
        correctAnswers: MAX_SOLO_CORRECT_ANSWERS + 1,
      });
      expect(res.isValid).toBe(false);
      expect(res.error).toBe('invalid_answers');
    });
  });
});

describe('Ön Doğrulama (Item 0) - ensureAchievementsBackfilled Atomiklik ve Yarım Kalma', () => {
  it('Backfill işlemi transaction içinde çalışır; hata durumunda rollback gerçekleşir ve achievements_initialized 0 kalır', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;

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
      VALUES ('legacy_user', 'EskiOyuncu', 500, 15, 12, 3, 50, 100000, 0);
    `);

    // user_achievements tablosuna sahte bir trigger ekleyerek ekleme anında hata fırlatalım
    rawDb.exec(`
      CREATE TRIGGER fail_on_achievement_insert
      BEFORE INSERT ON user_achievements
      BEGIN
        SELECT RAISE(FAIL, 'simulated disk failure on insert');
      END;
    `);

    const profileDO = new UserProfile(ctx, env);

    // getProfile çağrıldığında ensureAchievementsBackfilled tetiklenir ama trigger yüzünden hata fırlatır
    await expect(profileDO.getProfile('legacy_user')).rejects.toThrow('simulated disk failure');

    // Rollback kontrolü: user_achievements boş kalmalı ve achievements_initialized hala 0 olmalı!
    const row = rawDb.prepare('SELECT achievements_initialized FROM profiles WHERE uid = ?').get('legacy_user') as any;
    expect(row.achievements_initialized).toBe(0);

    const count = rawDb.prepare('SELECT COUNT(*) as count FROM user_achievements').get() as any;
    expect(count.count).toBe(0);

    // Trigger'ı kaldırıp tekrar deneyelim (retry senaryosu)
    rawDb.exec('DROP TRIGGER fail_on_achievement_insert;');

    const profile = await profileDO.getProfile('legacy_user');
    expect(profile.achievements!.length).toBeGreaterThan(0);

    const rowAfter = rawDb.prepare('SELECT achievements_initialized FROM profiles WHERE uid = ?').get('legacy_user') as any;
    expect(rowAfter.achievements_initialized).toBe(1);
  });
});

describe('UserProfile DO - applyBotMatchReward Mantığı ve Kuralları', () => {
  it('1. Geçerli galibiyet: Enerji düşer (-1), jeton artar (+30), istatistikler, seriler, başarımlar ve audit sayaçları artar', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_1'); // initialize

    const ticket = await profileDO.issueSoloTicket('user_1', Date.now() - 25000);
    expect(ticket.ok).toBe(true);

    const result = await profileDO.applyBotMatchReward({
      uid: 'user_1',
      ticketId: ticket.ticketId!,
      matchId: ticket.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 1,
      correctAnswers: 6,
      durationSeconds: 30,
      endedBy: 'normal',
    });

    expect(result.ok).toBe(true);
    expect(result.counted).toBe(true);
    expect(result.alreadyProcessed).toBeFalsy();
    expect(result.coinsAwarded).toBe(30);
    expect(result.coins).toBe(130); // 100 + 30
    expect(result.energy.current).toBe(4); // 5 - 1
    expect(result.unlockedAchievements).toEqual(['first_match', 'first_win']);

    // Profil istatistiklerini doğrula
    const profile = await profileDO.getProfile('user_1');
    expect(profile.stats.played).toBe(1);
    expect(profile.stats.won).toBe(1);
    expect(profile.stats.lost).toBe(0);
    expect(profile.stats.correctAnswers).toBe(6);
    expect(profile.currentStreak).toBe(1);
    expect(profile.maxStreak).toBe(1);

    // İç audit sayaçlarını (played_solo, won_solo) veritabanından doğrudan doğrula
    const dbRow = rawDb.prepare('SELECT played_solo, won_solo FROM profiles WHERE uid = ?').get('user_1') as any;
    expect(dbRow.played_solo).toBe(1);
    expect(dbRow.won_solo).toBe(1);

    // GET /me profili içinde played_solo / won_solo açığa çıkarılmaz
    expect((profile as any).played_solo).toBeUndefined();
    expect((profile as any).won_solo).toBeUndefined();

    // processed_matches kaydını doğrula
    const processed = rawDb.prepare('SELECT * FROM processed_matches WHERE match_id = ?').get(ticket.matchId!) as any;
    expect(processed).toBeDefined();
    expect(processed.outcome).toBe('win');
    expect(processed.coins_awarded).toBe(30);
  });

  it('2. Geçerli mağlubiyet: Enerji düşer (-1), jeton artar (+5), seri 0 olur, audit sayaçları artar', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_2');

    // Önce 1 galibiyet
    const t1 = await profileDO.issueSoloTicket('user_2', Date.now() - 25000);
    await profileDO.applyBotMatchReward({
      uid: 'user_2',
      ticketId: t1.ticketId!,
      matchId: t1.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 4,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    // Sonra 1 mağlubiyet
    const t2 = await profileDO.issueSoloTicket('user_2', Date.now() - 25000);
    const lossResult = await profileDO.applyBotMatchReward({
      uid: 'user_2',
      ticketId: t2.ticketId!,
      matchId: t2.matchId!,
      outcome: 'loss',
      myScore: 1,
      oppScore: 2,
      correctAnswers: 2,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(lossResult.ok).toBe(true);
    expect(lossResult.counted).toBe(true);
    expect(lossResult.coinsAwarded).toBe(5);
    expect(lossResult.coins).toBe(135); // 100 + 30 + 5
    expect(lossResult.energy.current).toBe(3); // 5 - 1 - 1
    expect(lossResult.unlockedAchievements).toEqual([]);

    const profile = await profileDO.getProfile('user_2');
    expect(profile.stats.played).toBe(2);
    expect(profile.stats.won).toBe(1);
    expect(profile.stats.lost).toBe(1);
    expect(profile.stats.correctAnswers).toBe(6); // 4 + 2
    expect(profile.currentStreak).toBe(0); // seri sıfırlandı
    expect(profile.maxStreak).toBe(1); // maxStreak korundu

    const dbRow = rawDb.prepare('SELECT played_solo, won_solo FROM profiles WHERE uid = ?').get('user_2') as any;
    expect(dbRow.played_solo).toBe(2);
    expect(dbRow.won_solo).toBe(1);
  });

  it('3. Yetersiz enerji: Sayaçlar ve jetonlar yazılmaz, counted: false döner', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_no_energy');

    // 5 enerjiyi tüket
    for (let i = 0; i < 5; i++) {
      await profileDO.spendEnergy({ uid: 'user_no_energy', matchId: 'mock_m_' + i });
    }

    const stateBefore = await profileDO.getEnergyState('user_no_energy');
    expect(stateBefore.current).toBe(0);

    // Enerji sıfırken bilet talep et
    const ticketRes = await profileDO.issueSoloTicket('user_no_energy');
    expect(ticketRes.ok).toBe(false);
    expect(ticketRes.reason).toBe('no_energy');

    // Biletsiz maç sonucu doğrudan reddedilir
    await expect(
      profileDO.applyBotMatchReward({
        uid: 'user_no_energy',
        ticketId: '',
        matchId: 'bot:match_energy_depleted',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      })
    ).rejects.toThrow('ticket_required');

    // DB'de hiçbir şey yazılmadığını doğrula
    const profileAfter = await profileDO.getProfile('user_no_energy');
    expect(profileAfter.stats.played).toBe(0);
    expect(profileAfter.stats.won).toBe(0);

    const ticketCount = rawDb.prepare('SELECT COUNT(*) as count FROM solo_tickets').get() as any;
    expect(ticketCount.count).toBe(0);
  });

  it('4. İdempotentlik ve Yeniden Deneme (Retry): Aynı matchId tekrar gelirse mükerrer harcama/artırım olmaz', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_retry');

    const ticket = await profileDO.issueSoloTicket('user_retry', Date.now() - 25000);
    expect(ticket.ok).toBe(true);

    // 1. Çağrı
    const r1 = await profileDO.applyBotMatchReward({
      uid: 'user_retry',
      ticketId: ticket.ticketId!,
      matchId: ticket.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 5,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(r1.ok).toBe(true);
    expect(r1.alreadyProcessed).toBeFalsy();
    expect(r1.coins).toBe(130);
    expect(r1.energy.current).toBe(4);
    expect(r1.unlockedAchievements).toEqual(['first_match', 'first_win']);

    // 2. Çağrı (aynı matchId) - Bilet used=1 olsa bile 400 değil idempotent döner
    const r2 = await profileDO.applyBotMatchReward({
      uid: 'user_retry',
      ticketId: ticket.ticketId!,
      matchId: ticket.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 5,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(r2.ok).toBe(true);
    expect(r2.alreadyProcessed).toBe(true);
    expect(r2.coinsAwarded).toBe(30);
    expect(r2.coins).toBe(130); // Jeton İKİNCİ KEZ ARTMAZ
    expect(r2.energy.current).toBe(4); // Enerji İKİNCİ KEZ DÜŞMEZ
    expect(r2.unlockedAchievements).toEqual(['first_match', 'first_win']);

    const profile = await profileDO.getProfile('user_retry');
    expect(profile.stats.played).toBe(1); // 1 maç olarak kalır
    expect(profile.stats.won).toBe(1);
  });

  it('5. Günlük Jeton Sınırı (DAILY_MATCH_COIN_CAP = 300) online ve solo maçlar arasında ortaktır', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv({ DAILY_MATCH_COIN_CAP: '300' }).env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_cap');

    // Kullanıcının günlük jeton sayacını 280 yapalım
    const dayKey = new Date().toISOString().slice(0, 10);
    rawDb.exec(`INSERT INTO daily_coins (day_key, earned) VALUES ('${dayKey}', 280)`);

    const t1 = await profileDO.issueSoloTicket('user_cap', Date.now() - 25000);
    // 30 jetonluk galibiyet -> sadece 20 jeton verilmeli
    const r1 = await profileDO.applyBotMatchReward({
      uid: 'user_cap',
      ticketId: t1.ticketId!,
      matchId: t1.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 3,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(r1.coinsAwarded).toBe(20);
    expect(r1.coins).toBe(120);

    const t2 = await profileDO.issueSoloTicket('user_cap', Date.now() - 25000);
    // Sonraki galibiyet -> 0 jeton
    const r2 = await profileDO.applyBotMatchReward({
      uid: 'user_cap',
      ticketId: t2.ticketId!,
      matchId: t2.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 3,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(r2.coinsAwarded).toBe(0);
    expect(r2.coins).toBe(120);
    expect(r2.counted).toBe(true); // İstatistikler ve başarımlar sayılmaya devam eder
  });

  it(`6. Günlük Güvenlik Tavanı (SOLO_DAILY_SAFETY_CAP = ${SOLO_DAILY_SAFETY_CAP}) aşıldığında counted: false döner`, async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_safety');

    // Günlük solo maç sayısını doğrudan güvenlik tavanına çekelim
    const dayKey = new Date().toISOString().slice(0, 10);
    rawDb.exec(`INSERT INTO daily_solo_matches (day_key, count) VALUES ('${dayKey}', ${SOLO_DAILY_SAFETY_CAP})`);

    const ticket = await profileDO.issueSoloTicket('user_safety', Date.now() - 25000);
    const result = await profileDO.applyBotMatchReward({
      uid: 'user_safety',
      ticketId: ticket.ticketId!,
      matchId: ticket.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 5,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(result.ok).toBe(true);
    expect(result.counted).toBe(false);
    expect(result.coinsAwarded).toBe(0);
    expect(result.coins).toBe(100);
    expect(result.energy.current).toBe(4); // Bilet düzenlenirken düştü, burada tekrar düşmez
    expect(result.unlockedAchievements).toEqual([]);

    const profile = await profileDO.getProfile('user_safety');
    expect(profile.stats.played).toBe(0);
  });

  it('7. Silinmiş hesap (tombstone) 410 hatası verir ve satırları diriltmez', async () => {
    const { rawDb, ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('user_deleted');
    await profileDO.deleteProfile('user_deleted');

    await expect(
      profileDO.applyBotMatchReward({
        uid: 'user_deleted',
        ticketId: 'stk_mock_123',
        matchId: 'bot:match_on_deleted_user',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      })
    ).rejects.toThrow();

    // DO'nun tombstone kaydını doğrula
    expect(profileDO.isDeleted()).toBe(true);

    const soloCount = rawDb.prepare('SELECT COUNT(*) as count FROM daily_solo_matches').get() as any;
    expect(soloCount.count).toBe(0);
  });

  it('8. Online Ranked ve Solo maçlar arasında birleşik galibiyet serisi ve streak_3 başarımı', async () => {
    const { ctx } = createMockCtx();
    const env = createEnv().env;
    const profileDO = new UserProfile(ctx, env);

    await profileDO.getProfile('combo_player');

    // 1. Online Ranked Galibiyet (applyMatchReward)
    const o1 = await profileDO.applyMatchReward({
      uid: 'combo_player',
      matchId: 'online_match_1',
      outcome: 'win',
    });
    expect(o1.unlockedAchievements).toEqual(['first_match', 'first_win']);

    // 2. Online Ranked Galibiyet (applyMatchReward)
    const o2 = await profileDO.applyMatchReward({
      uid: 'combo_player',
      matchId: 'online_match_2',
      outcome: 'win',
    });
    expect(o2.unlockedAchievements).toEqual([]);

    // 3. Solo Galibiyet (applyBotMatchReward) -> Seri 3'e ulaşır ve streak_3 AÇILIR!
    const t3 = await profileDO.issueSoloTicket('combo_player', Date.now() - 25000);
    const s3 = await profileDO.applyBotMatchReward({
      uid: 'combo_player',
      ticketId: t3.ticketId!,
      matchId: t3.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 1,
      correctAnswers: 4,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(s3.unlockedAchievements).toEqual(['streak_3']);

    const profile = await profileDO.getProfile('combo_player');
    expect(profile.currentStreak).toBe(3);
    expect(profile.maxStreak).toBe(3);
    expect(profile.stats.played).toBe(3);
    expect(profile.stats.won).toBe(3);
  });
});

describe('HTTP Endpoint Entegrasyonu (POST /matches/solo & /matches/solo/result)', () => {
  it('1. Yetkilendirme başlığı eksik veya geçersizse 401 döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ matchId: 'bot:test' }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('unauthorized');
  });

  it('2. Geçersiz gövde veya doğrulama hatasında 400 ve nötr hata döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_1',
      },
      body: JSON.stringify({
        ticketId: 'stk_valid123456789012345678',
        matchId: 'invalid_no_bot_prefix',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(400);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('bad_request');
  });

  it('2b. Bilet eksik ise 400 ve ticket_required döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_1',
      },
      body: JSON.stringify({
        matchId: 'bot:valid-match-id-1234',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(400);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('ticket_required');
  });

  it('3. 4KB sınırını aşan gövde 400 ile reddedilir', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_1',
      },
      body: JSON.stringify({
        ticketId: 'stk_valid123456789012345678',
        matchId: 'bot:valid-match-id-1234',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
        junk: 'x'.repeat(5000),
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(400);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('bad_request');
  });

  it('4. Başarılı POST /matches/solo isteği 200 döner ve beklenen alanları içerir', async () => {
    const { env, userProfiles } = createEnv();
    const profile =
      userProfiles.get('http_user_2') ||
      (env.USER_PROFILE.get(env.USER_PROFILE.idFromName('http_user_2')) as unknown as UserProfile);
    const issued = await profile.issueSoloTicket('http_user_2', Date.now() - 25000);

    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_2',
      },
      body: JSON.stringify({
        ticketId: issued.ticketId,
        matchId: issued.matchId,
        outcome: 'win',
        myScore: 2,
        oppScore: 1,
        correctAnswers: 5,
        durationSeconds: 26,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(true);
    expect(data.counted).toBe(true);
    expect(data.coinsAwarded).toBe(30);
    expect(data.coins).toBe(130);
    expect(data.energy.current).toBe(4);
    expect(data.unlockedAchievements).toEqual(['first_match', 'first_win']);
  });

  it('5. POST /matches/solo/result alias yolu da aynı şekilde çalışır', async () => {
    const { env, userProfiles } = createEnv();
    const profile =
      userProfiles.get('http_user_3') ||
      (env.USER_PROFILE.get(env.USER_PROFILE.idFromName('http_user_3')) as unknown as UserProfile);
    const issued = await profile.issueSoloTicket('http_user_3', Date.now() - 25000);

    const req = new Request('http://127.0.0.1/matches/solo/result', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_3',
      },
      body: JSON.stringify({
        ticketId: issued.ticketId,
        matchId: issued.matchId,
        outcome: 'loss',
        myScore: 0,
        oppScore: 2,
        correctAnswers: 2,
        durationSeconds: 22,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(true);
    expect(data.counted).toBe(true);
    expect(data.coinsAwarded).toBe(5);
    expect(data.energy.current).toBe(4);
  });

  it('6. Silinmiş kullanıcı için 410 döner', async () => {
    const { env, userProfiles } = createEnv();
    const profile =
      userProfiles.get('http_user_del') ||
      (env.USER_PROFILE.get(env.USER_PROFILE.idFromName('http_user_del')) as unknown as UserProfile);
    await profile.deleteProfile('http_user_del');

    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:http_user_del',
      },
      body: JSON.stringify({
        ticketId: 'stk_mock_del_123456789012',
        matchId: 'bot:http_match_del_001',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(410);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('account_deleted');
  });
});
