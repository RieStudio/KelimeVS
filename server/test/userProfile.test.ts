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
    expect(profile.stats).toEqual({ played: 0, won: 0, lost: 0, correctAnswers: 0 });
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

    // Yasaklı / rezerve ad
    await expect(profileDO.setNickname('Admin_Ahmet', 'user_1')).rejects.toThrow('reserved_nickname');
  });

  it('3b. Takma ad 24 saat bekleme süresi (cooldown) kuralı doğru uygulanır', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx, env);

    const t0 = 1_000_000_000;

    // 1. İlk belirleme serbesttir
    const r1 = await profileDO.setNickname('IlkAdim', 'user_cd', t0);
    expect(r1.ok).toBe(true);
    expect(r1.nickname).toBe('IlkAdim');

    // 2. 1 saat sonra değiştirme denenirse (3600 sn < 86400 sn) 429 nickname_cooldown fırlatılır
    const tPlus1Hour = t0 + 3600 * 1000;
    try {
      await profileDO.setNickname('IkinciAdim', 'user_cd', tPlus1Hour);
      expect.unreachable('nickname_cooldown hatası fırlatılmalıydı');
    } catch (err) {
      expect((err as Error).message).toBe('nickname_cooldown');
      expect((err as any).remainingSeconds).toBe(23 * 3600);
    }

    // 3. 24 saat 1 saniye sonra (t0 + 86401 sn) değiştirme başarılı olur
    const tPlus24Hours = t0 + 86401 * 1000;
    const r2 = await profileDO.setNickname('IkinciAdim', 'user_cd', tPlus24Hours);
    expect(r2.ok).toBe(true);
    expect(r2.nickname).toBe('IkinciAdim');
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

  describe('Misafir (Anonim) Otomatik Takma Ad & Migrasyon & Cooldown', () => {
    it('7. Misafir kullanıcı profili ilk oluşturulduğunda M-#### formatında ad üretilir (1000-9999 aralığında)', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);

      const profile = await profileDO.getProfile('guest_user_1', 0, true);
      expect(profile.isGuest).toBe(true);
      expect(profile.isSystemNickname).toBe(true);
      expect(profile.nickname).toMatch(/^M-[1-9]\d{3}$/);
    });

    it('8. Mevcut misafir kullanıcı özel ad seçmiş olsa bile getProfile ile M-#### adına tembel dönüştürülür ve idempotenttir', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);
      (profileDO as any).ensureSchema();

      // 1. Önce eski sistemde ad seçmiş bir profil oluştur (is_guest = 1, nickname = 'EskiOzelAd')
      ctx.storage.sql.exec(
        `INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, is_guest, is_system_nickname, nickname_updated_at)
         VALUES ('guest_legacy', 'EskiOzelAd', 100, 0, 0, 0, 0, 1000, 'classic', 1, 0, 500)`
      );

      // 2. getProfile çağrıldığında M-#### formatına dönüştürülür
      const migrated = await profileDO.getProfile('guest_legacy', 0, true);
      expect(migrated.isGuest).toBe(true);
      expect(migrated.isSystemNickname).toBe(true);
      expect(migrated.nickname).toMatch(/^M-[1-9]\d{3}$/);
      expect(migrated.nickname).not.toBe('EskiOzelAd');

      // 3. İdempotentlik: ikinci getProfile çağrısı aynı adı korur
      const secondCall = await profileDO.getProfile('guest_legacy', 0, true);
      expect(secondCall.nickname).toBe(migrated.nickname);
    });

    it('9. Misafir kullanıcı setNickname çağırmaya çalışırsa guest_nickname_locked hatası fırlatılır', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);

      await profileDO.getProfile('guest_user_locked', 0, true);

      await expect(
        profileDO.setNickname('YeniAd', 'guest_user_locked', Date.now(), true)
      ).rejects.toThrow('guest_nickname_locked');

      await expect(
        profileDO.setNickname('YeniAd', 'guest_user_locked', Date.now())
      ).rejects.toThrow('guest_nickname_locked');
    });

    it('10. Google bağlama: isGuest: false ile getProfile çağrıldığında is_guest = 0 olur', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);

      const guestProfile = await profileDO.getProfile('user_to_link', 0, true);
      expect(guestProfile.isGuest).toBe(true);

      // Google hesabı bağlandı
      const linkedProfile = await profileDO.getProfile('user_to_link', 0, false);
      expect(linkedProfile.isGuest).toBe(false);
      // M-#### adı başlangıçta korunur
      expect(linkedProfile.nickname).toBe(guestProfile.nickname);
      expect(linkedProfile.isSystemNickname).toBe(true);
    });

    it('11. (USER ADDITION 1) Tek yönlü misafirlik: google\'a bağlanmış, özel adı olan profil + anonim token → ad değişmez', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);
      (profileDO as any).ensureSchema();

      // Google'a bağlanmış ve özel ad seçmiş profil
      ctx.storage.sql.exec(
        `INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, is_guest, is_system_nickname, nickname_updated_at)
         VALUES ('user_linked_custom', 'OzelAdim123', 100, 0, 0, 0, 0, 1000, 'classic', 0, 0, 1000)`
      );

      // Eski veya süresi dolmamış anonim token geldi (isGuest: true)
      const profile = await profileDO.getProfile('user_linked_custom', 0, true);
      // isGuest bayrağı asla tekrar 1 olamaz!
      expect(profile.isGuest).toBe(false);
      // Takma ad kesinlikle M-#### ile ezilmez!
      expect(profile.nickname).toBe('OzelAdim123');
    });

    it('12. Google\'a bağlanan kullanıcının ilk özel ad seçimi 24 saatlik cooldown\'a takılmaz, ikinci seçim takılır', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(ctx, env);

      // Misafir olarak başla
      const guest = await profileDO.getProfile('user_cooldown_test', 0, true);
      expect(guest.isSystemNickname).toBe(true);

      // Google ile bağla
      await profileDO.getProfile('user_cooldown_test', 0, false);

      const t0 = 100_000_000;
      // 1. İlk özel ad seçimi: cooldown baypas edilir, başarıyla kaydedilir
      const res1 = await profileDO.setNickname('IlkOzelAdim', 'user_cooldown_test', t0, false);
      expect(res1.ok).toBe(true);
      expect(res1.nickname).toBe('IlkOzelAdim');

      const afterRes1 = await profileDO.getProfile('user_cooldown_test');
      expect(afterRes1.nickname).toBe('IlkOzelAdim');
      expect(afterRes1.isSystemNickname).toBe(false);

      // 2. 1 saat sonra (t0 + 3600_000) ikinci değişiklik denenirse cooldown'a takılır
      await expect(
        profileDO.setNickname('IkinciOzelAdim', 'user_cooldown_test', t0 + 3600_000, false)
      ).rejects.toThrow('nickname_cooldown');

      // 3. 24 saat + 1 sn sonra (t0 + 86401_000) değişiklik serbesttir
      const res2 = await profileDO.setNickname(
        'IkinciOzelAdim',
        'user_cooldown_test',
        t0 + 86401_000,
        false
      );
      expect(res2.ok).toBe(true);
      expect(res2.nickname).toBe('IkinciOzelAdim');
    });

    it('13. Şema değişikliğinden ÖNCE oluşturulmuş Google kullanıcısı (Sevbans): ensureSchema sonrası Google token ile getProfile çağrılınca nickname "Sevbans" AYNEN kalır, Leaderboard değişmez, is_guest=0 ve is_system_nickname=0 olur', async () => {
      const ctx = createMockCtx();
      const updateNicknameSpy = vi.fn();
      const env = createEnv({
        LEADERBOARD: {
          get: () => ({ updateNickname: updateNicknameSpy }),
          idFromName: () => 'global_id',
        } as any,
      });

      // 1. Şema değişikliğinden ÖNCEKİ tabloyu oluştur (is_guest ve is_system_nickname sütunları YOK!)
      ctx.storage.sql.exec(`
        CREATE TABLE profiles (
          uid TEXT PRIMARY KEY,
          nickname TEXT,
          coins INTEGER NOT NULL,
          played INTEGER NOT NULL DEFAULT 0,
          won INTEGER NOT NULL DEFAULT 0,
          lost INTEGER NOT NULL DEFAULT 0,
          correct_answers INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          equipped_frame TEXT NOT NULL DEFAULT 'classic',
          energy INTEGER NOT NULL DEFAULT 5,
          energy_updated_at INTEGER NOT NULL DEFAULT 0,
          nickname_updated_at INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at, nickname_updated_at)
        VALUES ('u_sevbans', 'Sevbans', 150, 5, 3, 2, 10, 1000, 'classic', 5, 0, 500);
      `);

      const profileDO = new UserProfile(ctx, env);

      // 2. Google token ile getProfile çağrılır (isGuest: false)
      const profile = await profileDO.getProfile('u_sevbans', 0, false);

      // Beklenenler:
      // a) Takma ad AYNEN kalmalı
      expect(profile.nickname).toBe('Sevbans');
      // b) is_guest = 0 ve isSystemNickname = 0 olmalı
      expect(profile.isGuest).toBe(false);
      expect(profile.isSystemNickname).toBe(false);
      // c) Leaderboard güncellemesi HİÇ çağrılmamalı
      expect(updateNicknameSpy).not.toHaveBeenCalled();

      // d) DB'deki değerler doğrudan doğrulanır
      const row = ctx.storage.sql
        .exec<any>('SELECT is_guest, is_system_nickname, nickname FROM profiles WHERE uid = ?', 'u_sevbans')
        .one();
      expect(row.is_guest).toBe(0);
      expect(row.is_system_nickname).toBe(0);
      expect(row.nickname).toBe('Sevbans');
    });

    it('14. Şema değişikliğinden ÖNCE oluşturulmuş eski anonim profil (EskiAnonim): ensureSchema sonrası anonim token ile getProfile çağrılınca M-#### olur, Leaderboard güncellenir', async () => {
      const ctx = createMockCtx();
      const updateNicknameSpy = vi.fn();
      const env = createEnv({
        LEADERBOARD: {
          get: () => ({ updateNickname: updateNicknameSpy }),
          idFromName: () => 'global_id',
        } as any,
      });

      // 1. Şema değişikliğinden ÖNCEKİ tabloyu oluştur (is_guest ve is_system_nickname sütunları YOK!)
      ctx.storage.sql.exec(`
        CREATE TABLE profiles (
          uid TEXT PRIMARY KEY,
          nickname TEXT,
          coins INTEGER NOT NULL,
          played INTEGER NOT NULL DEFAULT 0,
          won INTEGER NOT NULL DEFAULT 0,
          lost INTEGER NOT NULL DEFAULT 0,
          correct_answers INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          equipped_frame TEXT NOT NULL DEFAULT 'classic',
          energy INTEGER NOT NULL DEFAULT 5,
          energy_updated_at INTEGER NOT NULL DEFAULT 0,
          nickname_updated_at INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at, nickname_updated_at)
        VALUES ('u_old_anon', 'EskiAnonim', 150, 5, 3, 2, 10, 1000, 'classic', 5, 0, 500);
      `);

      const profileDO = new UserProfile(ctx, env);

      // 2. Anonim token ile getProfile çağrılır (isGuest: true)
      const profile = await profileDO.getProfile('u_old_anon', 0, true);

      // Beklenenler:
      // a) Takma ad M-#### kalıbına dönüşmeli
      expect(profile.nickname).toMatch(/^M-[1-9]\d{3}$/);
      expect(profile.nickname).not.toBe('EskiAnonim');
      // b) isGuest = true ve isSystemNickname = true olmalı
      expect(profile.isGuest).toBe(true);
      expect(profile.isSystemNickname).toBe(true);
      // c) Leaderboard güncellemesi çağrılmış olmalı
      expect(updateNicknameSpy).toHaveBeenCalledWith('u_old_anon', profile.nickname);

      // d) DB'deki değerler doğrulanır
      const row = ctx.storage.sql
        .exec<any>('SELECT is_guest, is_system_nickname, nickname FROM profiles WHERE uid = ?', 'u_old_anon')
        .one();
      expect(row.is_guest).toBe(1);
      expect(row.is_system_nickname).toBe(1);
      expect(row.nickname).toBe(profile.nickname);
    });

    it('15. Şema değişikliğinden ÖNCE oluşturulmuş Google kullanıcısı (Sevbans) için cooldown normal çalışır (is_system_nickname=0)', async () => {
      const ctx = createMockCtx();
      const env = createEnv();

      const tLastUpdated = 1_000_000_000;
      // Eski sistemde 1 saat önce adını güncellemiş bir Google kullanıcısı
      ctx.storage.sql.exec(`
        CREATE TABLE profiles (
          uid TEXT PRIMARY KEY,
          nickname TEXT,
          coins INTEGER NOT NULL,
          played INTEGER NOT NULL DEFAULT 0,
          won INTEGER NOT NULL DEFAULT 0,
          lost INTEGER NOT NULL DEFAULT 0,
          correct_answers INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          equipped_frame TEXT NOT NULL DEFAULT 'classic',
          energy INTEGER NOT NULL DEFAULT 5,
          energy_updated_at INTEGER NOT NULL DEFAULT 0,
          nickname_updated_at INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at, nickname_updated_at)
        VALUES ('u_sevbans_cooldown', 'Sevbans', 200, 10, 8, 2, 25, 500, 'classic', 5, 0, ${tLastUpdated});
      `);

      const profileDO = new UserProfile(ctx, env);
      await profileDO.getProfile('u_sevbans_cooldown', 0, false);

      // 1 saat sonra yeni ad seçmeye çalışırsa cooldown uygulanmalı (çünkü is_system_nickname=0)
      await expect(
        profileDO.setNickname('Sevbans2', 'u_sevbans_cooldown', tLastUpdated + 3600_000, false)
      ).rejects.toThrow('nickname_cooldown');

      // 24 saat 1 saniye sonra serbesttir
      const res = await profileDO.setNickname(
        'Sevbans2',
        'u_sevbans_cooldown',
        tLastUpdated + 86401_000,
        false
      );
      expect(res.ok).toBe(true);
      expect(res.nickname).toBe('Sevbans2');
    });

    it('16. getProfile isGuest parametresi verilmediğinde (undefined) misafir dönüşümü asla tetiklenmez', async () => {
      const ctx = createMockCtx();
      const updateNicknameSpy = vi.fn();
      const env = createEnv({
        LEADERBOARD: {
          get: () => ({ updateNickname: updateNicknameSpy }),
          idFromName: () => 'global_id',
        } as any,
      });

      ctx.storage.sql.exec(`
        CREATE TABLE profiles (
          uid TEXT PRIMARY KEY,
          nickname TEXT,
          coins INTEGER NOT NULL,
          played INTEGER NOT NULL DEFAULT 0,
          won INTEGER NOT NULL DEFAULT 0,
          lost INTEGER NOT NULL DEFAULT 0,
          correct_answers INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          equipped_frame TEXT NOT NULL DEFAULT 'classic',
          energy INTEGER NOT NULL DEFAULT 5,
          energy_updated_at INTEGER NOT NULL DEFAULT 0,
          nickname_updated_at INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at, nickname_updated_at)
        VALUES ('u_internal_call', 'OrijinalAd', 100, 0, 0, 0, 0, 1000, 'classic', 5, 0, 0);
      `);

      const profileDO = new UserProfile(ctx, env);

      // isGuest verilmedi (undefined)
      const profile = await profileDO.getProfile('u_internal_call');
      expect(profile.nickname).toBe('OrijinalAd');
      expect(updateNicknameSpy).not.toHaveBeenCalled();
    });
  });
});

