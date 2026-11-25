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
  SOLO_VOID_DAILY_REFUND_CAP,
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

describe('Solo Void / Draw Limit (outcome: void) ve Budama Testleri', () => {
  it('1. validateSoloMatchResult outcome="void" yalnız ticketId ile kabul edilir; geçersiz opsiyonel alan reddedilir', () => {
    const okMinimal = validateSoloMatchResult({
      ticketId: 'stk_validticket12345678',
      outcome: 'void',
    });
    expect(okMinimal.isValid).toBe(true);
    expect(okMinimal.data?.outcome).toBe('void');

    const okFull = validateSoloMatchResult({
      ticketId: 'stk_validticket12345678',
      matchId: 'bot:a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      outcome: 'void',
      myScore: 1,
      oppScore: 1,
      correctAnswers: 4,
      durationSeconds: 45,
      endedBy: 'draw_limit_reached',
    });
    expect(okFull.isValid).toBe(true);

    const missingTicket = validateSoloMatchResult({ outcome: 'void' });
    expect(missingTicket.isValid).toBe(false);
    expect(missingTicket.error).toBe('ticket_required');

    const badMatchId = validateSoloMatchResult({
      ticketId: 'stk_validticket12345678',
      matchId: 'invalid_match',
      outcome: 'void',
    });
    expect(badMatchId.isValid).toBe(false);
    expect(badMatchId.error).toBe('bad_request');
  });

  it('2. Void başarılı enerji iadesi yapar; sayaç, seri, başarım, jeton ve liderliğe dokunmaz', async () => {
    const recordMatchResult = vi.fn();
    const { env } = createEnv({
      LEADERBOARD: {
        idFromName: () => ({ toString: () => 'global' }),
        get: () => ({ recordMatchResult }),
      } as any,
    });
    const { ctx, rawDb } = createMockCtx();
    const profileDO = new UserProfile(ctx, env);
    const uid = 'void_user_1';
    const baseMs = 1_700_000_000_000;

    // İlk olarak 1 galibiyet alarak seri=1, played=1, won=1 oluşturalım
    const tWin = await profileDO.issueSoloTicket(uid, baseMs);
    await profileDO.applyBotMatchReward({
      uid,
      ticketId: tWin.ticketId!,
      matchId: tWin.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 3,
      endedBy: 'normal',
      nowMs: baseMs + 25_000,
    });

    const beforeProfile = await profileDO.getProfile(uid, 0, undefined, baseMs + 25_000);
    const beforeEnergy = await profileDO.getEnergyState(uid, baseMs + 25_000);
    expect(beforeEnergy.current).toBe(4);
    expect(beforeProfile.currentStreak).toBe(1);
    expect(beforeProfile.coins).toBe(130);

    // Yeni bilet al -> enerji 3'e düşer
    const tVoid = await profileDO.issueSoloTicket(uid, baseMs + 30_000);
    expect(tVoid.energy?.current).toBe(3);

    // Void bildirimi -> enerji 4'e iade edilir, sayaç/seri/başarım/jeton değişmez
    const voidRes = await profileDO.applyBotMatchReward({
      uid,
      ticketId: tVoid.ticketId!,
      outcome: 'void',
      nowMs: baseMs + 35_000,
    });

    expect(voidRes.ok).toBe(true);
    expect(voidRes.counted).toBe(false);
    expect(voidRes.voided).toBe(true);
    expect(voidRes.refunded).toBe(true);
    expect(voidRes.energy.current).toBe(4);
    expect(voidRes.unlockedAchievements).toEqual([]);

    const afterProfile = await profileDO.getProfile(uid, 0, undefined, baseMs + 35_000);
    expect(afterProfile.stats.played).toBe(1);
    expect(afterProfile.stats.won).toBe(1);
    expect(afterProfile.stats.lost).toBe(0);
    expect(afterProfile.currentStreak).toBe(1);
    expect(afterProfile.maxStreak).toBe(1);
    expect(afterProfile.coins).toBe(130);
    expect(afterProfile.achievements?.map((a) => a.id)).toEqual(['first_match', 'first_win']);
    expect(recordMatchResult).not.toHaveBeenCalled();

    const ticketRow = rawDb
      .prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?')
      .get(tVoid.ticketId!) as { used: number };
    expect(ticketRow.used).toBe(1);

    const processedRow = rawDb
      .prepare('SELECT outcome, coins_awarded FROM processed_matches WHERE match_id = ?')
      .get(tVoid.matchId!) as { outcome: string; coins_awarded: number };
    expect(processedRow.outcome).toBe('solo_voided');
    expect(processedRow.coins_awarded).toBe(0);
  });

  it('3. Void tekrar çağrısında idempotenttir (alreadyProcessed: true, ikinci kez iade ETMEZ)', async () => {
    const { env } = createEnv();
    const { ctx } = createMockCtx();
    const profileDO = new UserProfile(ctx, env);
    const uid = 'void_idem_user';
    const baseMs = 1_700_000_000_000;

    // 2 bilet al -> enerji 5 -> 3 (2. bilet alınırken 1. bilet solo_abandoned olur; toplam 2 harcanır)
    const t1 = await profileDO.issueSoloTicket(uid, baseMs);
    const t2 = await profileDO.issueSoloTicket(uid, baseMs + 1000);
    expect(t2.energy?.current).toBe(3);
    expect(t1.ticketId).toBeDefined();

    const firstVoid = await profileDO.applyBotMatchReward({
      uid,
      ticketId: t2.ticketId!,
      outcome: 'void',
      nowMs: baseMs + 5000,
    });
    expect(firstVoid.refunded).toBe(true);
    expect(firstVoid.alreadyProcessed).toBeUndefined();
    expect(firstVoid.energy.current).toBe(4);

    // Aynı biletle ikinci void çağrısı -> idempotent, enerji 4 olarak kalır (5 olmaz!)
    const secondVoid = await profileDO.applyBotMatchReward({
      uid,
      ticketId: t2.ticketId!,
      outcome: 'void',
      nowMs: baseMs + 6000,
    });
    expect(secondVoid.ok).toBe(true);
    expect(secondVoid.counted).toBe(false);
    expect(secondVoid.voided).toBe(true);
    expect(secondVoid.refunded).toBe(false);
    expect(secondVoid.alreadyProcessed).toBe(true);
    expect(secondVoid.energy.current).toBe(4);
  });

  it('4. Günlük iade sınırı (SOLO_VOID_DAILY_REFUND_CAP = 5) aşılınca bilet solo_abandoned gibi kapanır (kayıp + seri sıfırlama + başarım, iade ve jeton yok)', async () => {
    const { env } = createEnv();
    const { ctx, rawDb } = createMockCtx();
    const profileDO = new UserProfile(ctx, env);
    const uid = 'void_cap_user';
    const baseMs = 1_700_000_000_000;

    expect(SOLO_VOID_DAILY_REFUND_CAP).toBe(5);

    // Önce 7 mağlubiyet + 2 galibiyet -> played=9, won=2, lost=7, currentStreak=2, maxStreak=2
    for (let i = 0; i < 7; i++) {
      await profileDO.applyMatchReward({ uid, matchId: `cap_pre_l_${i}`, outcome: 'loss' });
    }
    await profileDO.applyMatchReward({ uid, matchId: 'cap_pre_w_1', outcome: 'win' });
    await profileDO.applyMatchReward({ uid, matchId: 'cap_pre_w_2', outcome: 'win' });

    const preProf = await profileDO.getProfile(uid, 0, undefined, baseMs);
    expect(preProf.stats.played).toBe(9);
    expect(preProf.stats.lost).toBe(7);
    expect(preProf.currentStreak).toBe(2);
    const coinsBeforeVoid = preProf.coins;

    // İlk 5 void işleminde iade gerçekleşir, sayaç ve seri değişmez (enerji 5 -> 4 -> 5)
    for (let i = 0; i < 5; i++) {
      const t = await profileDO.issueSoloTicket(uid, baseMs + i * 2000);
      expect(t.energy?.current).toBe(4);
      const r = await profileDO.applyBotMatchReward({
        uid,
        ticketId: t.ticketId!,
        outcome: 'void',
        nowMs: baseMs + i * 2000 + 1000,
      });
      expect(r.ok).toBe(true);
      expect(r.counted).toBe(false);
      expect(r.voided).toBe(true);
      expect(r.refunded).toBe(true);
      expect(r.energy.current).toBe(5);
      expect(r.unlockedAchievements).toEqual([]);
    }

    // 6. void işleminde günlük sınır aşılmış -> solo_abandoned gibi kapatılır
    const t6 = await profileDO.issueSoloTicket(uid, baseMs + 20_000);
    expect(t6.energy?.current).toBe(4);
    const r6 = await profileDO.applyBotMatchReward({
      uid,
      ticketId: t6.ticketId!,
      outcome: 'void',
      nowMs: baseMs + 21_000,
    });
    expect(r6.ok).toBe(true);
    expect(r6.counted).toBe(true);
    expect(r6.voided).toBe(false);
    expect(r6.refunded).toBe(false);
    expect(r6.energy.current).toBe(4);
    expect(r6.unlockedAchievements).toEqual(['matches_10']);

    const afterProf = await profileDO.getProfile(uid, 0, undefined, baseMs + 21_000);
    expect(afterProf.stats.played).toBe(10);
    expect(afterProf.stats.won).toBe(2);
    expect(afterProf.stats.lost).toBe(8);
    expect(afterProf.currentStreak).toBe(0);
    expect(afterProf.maxStreak).toBe(2);
    expect(afterProf.coins).toBe(coinsBeforeVoid);

    const t6Row = rawDb
      .prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?')
      .get(t6.ticketId!) as { used: number };
    expect(t6Row.used).toBe(1);

    const processed6 = rawDb
      .prepare('SELECT outcome, coins_awarded FROM processed_matches WHERE match_id = ?')
      .get(t6.matchId!) as { outcome: string; coins_awarded: number };
    expect(processed6.outcome).toBe('solo_abandoned');
    expect(processed6.coins_awarded).toBe(0);

    // Aynı bilete tekrar void veya win gönderilirse ticket_already_used döner
    await expect(
      profileDO.applyBotMatchReward({
        uid,
        ticketId: t6.ticketId!,
        outcome: 'void',
        nowMs: baseMs + 22_000,
      })
    ).rejects.toThrow('ticket_already_used');

    // Void iadeleri SOLO_DAILY_SAFETY_CAP (1000) sayacını tüketmemelidir
    const dayKey = new Date(baseMs).toISOString().slice(0, 10);
    const dailyRow = rawDb
      .prepare('SELECT count, void_refund_count FROM daily_solo_matches WHERE day_key = ?')
      .get(dayKey) as { count: number; void_refund_count: number };
    expect(dailyRow.void_refund_count).toBe(5);
    expect(dailyRow.count).toBe(0);
  });

  it('5. Yarış koruması: Void sonrası aynı bilete win/loss gelirse (ve tersi) 400 ticket_already_used döner', async () => {
    const { env, userProfiles } = createEnv();
    const uid = 'void_race_user';
    const profile =
      userProfiles.get(uid) ||
      (env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile);

    // A) Önce void, sonra win -> win isteği 400 ticket_already_used almalı
    const t1 = await profile.issueSoloTicket(uid, Date.now() - 25_000);
    const voidHttpRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/solo', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ ticketId: t1.ticketId, outcome: 'void' }),
      }),
      env
    );
    expect(voidHttpRes.status).toBe(200);
    const voidJson = (await voidHttpRes.json()) as any;
    expect(voidJson.voided).toBe(true);
    expect(voidJson.refunded).toBe(true);

    const winAfterVoidRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/solo/result', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({
          ticketId: t1.ticketId,
          matchId: t1.matchId,
          outcome: 'win',
          myScore: 2,
          oppScore: 0,
          correctAnswers: 4,
          endedBy: 'normal',
        }),
      }),
      env
    );
    expect(winAfterVoidRes.status).toBe(400);
    const winAfterVoidJson = (await winAfterVoidRes.json()) as any;
    expect(winAfterVoidJson.error).toBe('ticket_already_used');

    // B) Önce win, sonra void -> void isteği 400 ticket_already_used almalı
    const t2 = await profile.issueSoloTicket(uid, Date.now() - 25_000);
    const winRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/solo', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({
          ticketId: t2.ticketId,
          matchId: t2.matchId,
          outcome: 'win',
          myScore: 2,
          oppScore: 1,
          correctAnswers: 4,
          endedBy: 'normal',
        }),
      }),
      env
    );
    expect(winRes.status).toBe(200);

    const voidAfterWinRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/solo', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ ticketId: t2.ticketId, outcome: 'void' }),
      }),
      env
    );
    expect(voidAfterWinRes.status).toBe(400);
    const voidAfterWinJson = (await voidAfterWinRes.json()) as any;
    expect(voidAfterWinJson.error).toBe('ticket_already_used');
  });

  it('6. Budama: issueSoloTicket 30 günden eski used=1 biletleri ve 7 günden eski daily_solo_matches satırlarını siler', async () => {
    const { env } = createEnv();
    const { ctx, rawDb } = createMockCtx();
    const profileDO = new UserProfile(ctx, env);
    const uid = 'prune_user';
    const nowMs = 1_700_000_000_000;
    await profileDO.getProfile(uid, 0, undefined, nowMs);

    const thirtyOneDaysAgo = nowMs - 31 * 24 * 60 * 60 * 1000;
    const fiveDaysAgo = nowMs - 5 * 24 * 60 * 60 * 1000;
    const eightDaysAgoKey = new Date(nowMs - 8 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const twoDaysAgoKey = new Date(nowMs - 2 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const todayKey = new Date(nowMs).toISOString().slice(0, 10);

    rawDb
      .prepare('INSERT INTO solo_tickets (ticket_id, match_id, issued_at, expires_at, used) VALUES (?, ?, ?, ?, 1)')
      .run('stk_old_used_31d', 'bot:old_31d_00001', thirtyOneDaysAgo, thirtyOneDaysAgo + 900_000);
    rawDb
      .prepare('INSERT INTO solo_tickets (ticket_id, match_id, issued_at, expires_at, used) VALUES (?, ?, ?, ?, 1)')
      .run('stk_recent_used_5d', 'bot:recent_5d_001', fiveDaysAgo, fiveDaysAgo + 900_000);

    rawDb
      .prepare('INSERT INTO daily_solo_matches (day_key, count, void_refund_count) VALUES (?, 50, 2)')
      .run(eightDaysAgoKey);
    rawDb
      .prepare('INSERT INTO daily_solo_matches (day_key, count, void_refund_count) VALUES (?, 12, 1)')
      .run(twoDaysAgoKey);
    rawDb
      .prepare('INSERT INTO daily_solo_matches (day_key, count, void_refund_count) VALUES (?, 999, 0)')
      .run(todayKey);

    // Yeni bilet üretimi budamayı tetikler
    const issued = await profileDO.issueSoloTicket(uid, nowMs);
    expect(issued.ok).toBe(true);

    const oldTicket = rawDb
      .prepare('SELECT ticket_id FROM solo_tickets WHERE ticket_id = ?')
      .get('stk_old_used_31d');
    const recentTicket = rawDb
      .prepare('SELECT ticket_id FROM solo_tickets WHERE ticket_id = ?')
      .get('stk_recent_used_5d');
    expect(oldTicket).toBeUndefined();
    expect(recentTicket).toBeDefined();

    const oldDaily = rawDb
      .prepare('SELECT day_key FROM daily_solo_matches WHERE day_key = ?')
      .get(eightDaysAgoKey);
    const recentDaily = rawDb
      .prepare('SELECT day_key FROM daily_solo_matches WHERE day_key = ?')
      .get(twoDaysAgoKey);
    const todayDaily = rawDb
      .prepare('SELECT count FROM daily_solo_matches WHERE day_key = ?')
      .get(todayKey) as { count: number };
    expect(oldDaily).toBeUndefined();
    expect(recentDaily).toBeDefined();
    expect(todayDaily.count).toBe(999);
  });

  it('7. Silinmiş hesapta POST /matches/solo (outcome: void) 410 account_deleted döner', async () => {
    const { env, userProfiles } = createEnv();
    const uid = 'void_deleted_user';
    const profile =
      userProfiles.get(uid) ||
      (env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile);
    await profile.deleteProfile(uid);

    const res = await worker.fetch(
      new Request('http://127.0.0.1/matches/solo', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({
          ticketId: 'stk_deleted_ticket_123456',
          outcome: 'void',
        }),
      }),
      env
    );
    expect(res.status).toBe(410);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(false);
    expect(data.error).toBe('account_deleted');
  });
});
