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

import {
  UserProfile,
  NICKNAME_WINDOW_MS,
  NICKNAME_MAX_CHANGES,
  formatRemainingCooldown,
  getNicknameCooldownMessage,
} from '../src/userProfile';
import type { Env } from '../src/index';
import worker from '../src/index';

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
    storage: {
      sql,
      transactionSync<T>(closure: () => T): T {
        db.exec('BEGIN TRANSACTION');
        try {
          const res = closure();
          db.exec('COMMIT');
          return res;
        } catch (err) {
          db.exec('ROLLBACK');
          throw err;
        }
      },
      setAlarm: vi.fn(),
      getAlarm: vi.fn().mockResolvedValue(null),
      deleteAlarm: vi.fn(),
      deleteAll: vi.fn(),
    },
  };
}

function createEnv(overrides?: Partial<Env>): Env {
  return {
    START_COINS: '100',
    ALLOW_DEV_AUTH: 'true',
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    ...overrides,
  };
}

describe('Kullanıcı Adı 24 Saatte 2 Kez Değiştirme (Kayan Pencere) Testleri', () => {
  it('1) İlk ad belirleme kota harcamaz, sonrasındaki 2 değişiklik serbesttir, 3. değişiklik reddedilir', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx as any, env);

    const t0 = 100_000_000;
    // 1. İlk ad belirleme: kota harcamaz
    const r1 = await profileDO.setNickname('IlkAdim', 'u1', t0);
    expect(r1.ok).toBe(true);
    expect(r1.nickname).toBe('IlkAdim');

    // nickname_changes tablosunda hiç satır olmamalı (ilk ad kotaya sayılmaz)
    const changesCount0 = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(changesCount0.cnt).toBe(0);

    // 2. İlk adın 10 dk sonrası 1. değişiklik: başarılı
    const t1 = t0 + 10 * 60 * 1000;
    const r2 = await profileDO.setNickname('IkinciAdim', 'u1', t1);
    expect(r2.ok).toBe(true);
    expect(r2.nickname).toBe('IkinciAdim');

    const changesCount1 = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(changesCount1.cnt).toBe(1);

    // 3. Ondan 20 dk sonra 2. değişiklik: başarılı
    const t2 = t1 + 20 * 60 * 1000;
    const r3 = await profileDO.setNickname('UcuncuAdim', 'u1', t2);
    expect(r3.ok).toBe(true);
    expect(r3.nickname).toBe('UcuncuAdim');

    const changesCount2 = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(changesCount2.cnt).toBe(2);

    // 4. Ondan 5 dk sonra 3. deneme: 429 nickname_cooldown fırlatılır
    const t3 = t2 + 5 * 60 * 1000;
    try {
      await profileDO.setNickname('DorduncuAdim', 'u1', t3);
      expect.unreachable('nickname_cooldown fırlatılmalıydı');
    } catch (err) {
      expect((err as Error).message).toBe('nickname_cooldown');
      const expectedRemaining = Math.ceil((t1 + NICKNAME_WINDOW_MS - t3) / 1000);
      expect((err as any).remainingSeconds).toBe(expectedRemaining);
    }
  });

  it('2) HTTP Uç Noktası (PUT /me/nickname): 3. değişiklikte HTTP 429, Retry-After ve dinamik mesaj döner', async () => {
    let mockProfile: UserProfile | undefined;
    const ctx = createMockCtx();
    const env = createEnv({
      USER_PROFILE: {
        idFromName: () => 'uid_http_test' as any,
        get: () => {
          if (!mockProfile) {
            mockProfile = new UserProfile(ctx as any, env);
          }
          return mockProfile as any;
        },
      } as any,
    });

    // İlk ad
    const res0 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_http',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'IlkAdim' }),
      }),
      env
    );
    expect(res0.status).toBe(200);

    // 1. değişiklik
    const res1 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_http',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'IkinciAdim' }),
      }),
      env
    );
    expect(res1.status).toBe(200);

    // 2. değişiklik
    const res2 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_http',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'UcuncuAdim' }),
      }),
      env
    );
    expect(res2.status).toBe(200);

    // 3. değişiklik -> 429
    const res3 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_http',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'DorduncuAdim' }),
      }),
      env
    );
    expect(res3.status).toBe(429);
    expect(res3.headers.get('Retry-After')).toBeTruthy();
    const body3 = (await res3.json()) as any;
    expect(body3.error).toBe('nickname_cooldown');
    expect(body3.message).toContain('Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin.');
    expect(body3.message).toContain('Bir sonraki değişiklik hakkın:');
  });

  it('3) 1. değişikliğin 24 saat + 1 sn sonrasında bir hak açılır, 2. değişiklik henüz dolmadıysa hemen ardından tekrar kilitlenir', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx as any, env);

    const t0 = 500_000_000;
    await profileDO.setNickname('BaslangicAd', 'u2', t0);

    // 1. değişiklik t1'de
    const t1 = t0 + 1_000_000;
    await profileDO.setNickname('Ad1', 'u2', t1);

    // 2. değişiklik t2'de
    const t2 = t1 + 3_600_000; // 1 saat sonra
    await profileDO.setNickname('Ad2', 'u2', t2);

    // 1. değişikliğin üzerinden 24 saat + 1 sn sonra (t1 + 24h + 1s)
    const t3 = t1 + NICKNAME_WINDOW_MS + 1000;
    // 1. değişiklik temizlendiği için 1 hak açılmıştır
    const rSuccess = await profileDO.setNickname('Ad3', 'u2', t3);
    expect(rSuccess.ok).toBe(true);
    expect(rSuccess.nickname).toBe('Ad3');

    // Hemen 1 saniye sonra tekrar denenirse (t2'nin üzerinden henüz 24 saat geçmedi!) -> 429
    await expect(
      profileDO.setNickname('Ad4', 'u2', t3 + 1000)
    ).rejects.toThrow('nickname_cooldown');
  });

  it('4) Göç (Migration): Tablo yokken eski veriyle 10 saat önce değiştirmiş kullanıcıya 1 hak verilir; 30 saat önce olan kullanıcıya 2 hak verilir; göçün yalnızca bir kez çalıştığı doğrulanır', async () => {
    const ctx1 = createMockCtx();
    const env = createEnv();

    const now = 2_000_000_000;
    const tenHoursAgo = now - 10 * 3600 * 1000;

    // 1. Senaryo: 10 saat önce ad değiştirmiş eski kullanıcı (is_system_nickname = 0, nickname_updated_at > 0)
    ctx1.rawDb.exec(`
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
      INSERT INTO profiles (uid, nickname, coins, created_at, nickname_updated_at)
      VALUES ('u_mig_1', 'EskiAd1', 100, ${tenHoursAgo - 10000}, ${tenHoursAgo});
    `);

    const profileDO1 = new UserProfile(ctx1 as any, env);
    // ensureSchema çağrılır
    await profileDO1.getProfile('u_mig_1', 0, false, now);

    // Göç tek satır eklemiş olmalı
    const rows1 = ctx1.rawDb
      .prepare('SELECT * FROM nickname_changes')
      .all() as { changed_at: number }[];
    expect(rows1.length).toBe(1);
    expect(rows1[0].changed_at).toBe(tenHoursAgo);

    // Kullanıcının 1 hakkı kalmıştır: ilk setNickname başarılı olur
    const res1 = await profileDO1.setNickname('YeniAd1', 'u_mig_1', now, false);
    expect(res1.ok).toBe(true);

    // 2. setNickname ise kilitlenir (2 hakkı doldu)
    await expect(
      profileDO1.setNickname('YeniAd2', 'u_mig_1', now + 1000, false)
    ).rejects.toThrow('nickname_cooldown');

    // 2. Senaryo: 30 saat önce ad değiştirmiş kullanıcı -> 2 hakkı da tamdır
    const ctx2 = createMockCtx();
    const thirtyHoursAgo = now - 30 * 3600 * 1000;
    ctx2.rawDb.exec(`
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
      INSERT INTO profiles (uid, nickname, coins, created_at, nickname_updated_at)
      VALUES ('u_mig_2', 'EskiAd2', 100, ${thirtyHoursAgo - 10000}, ${thirtyHoursAgo});
    `);

    const profileDO2 = new UserProfile(ctx2 as any, env);
    await profileDO2.getProfile('u_mig_2', 0, false, now);

    // 30 saat geçtiği için göç satır EKLEMEZ (tablo boş kalır)
    const rows2 = ctx2.rawDb
      .prepare('SELECT * FROM nickname_changes')
      .all() as { changed_at: number }[];
    expect(rows2.length).toBe(0);

    // 2 hakkı da serbestçe kullanabilir
    const rA = await profileDO2.setNickname('Yeni2_1', 'u_mig_2', now, false);
    expect(rA.ok).toBe(true);
    const rB = await profileDO2.setNickname('Yeni2_2', 'u_mig_2', now + 1000, false);
    expect(rB.ok).toBe(true);
    await expect(
      profileDO2.setNickname('Yeni2_3', 'u_mig_2', now + 2000, false)
    ).rejects.toThrow('nickname_cooldown');

    // 3. Senaryo: Göçün tablo oluştuktan sonra tekrar çalışmadığı (idempotent, bir kez) testi
    // Kullanıcı ilk adını belirledikten sonra DO yeniden başlatılsa bile göç çalışıp satır eklemez
    const ctx3 = createMockCtx();
    const profileDO3 = new UserProfile(ctx3 as any, env);
    await profileDO3.setNickname('IlkAdim', 'u_mig_3', now);

    // Şimdi DO'yu sanki bellekten düşmüş gibi yeniden oluşturalım (aynı DB ctx3 ile)
    const profileDO3Reloaded = new UserProfile(ctx3 as any, env);
    await profileDO3Reloaded.getProfile('u_mig_3', 0, false, now + 5000);

    // Tablo daha önce oluşturulduğu için göç tekrar çalışmamalıdır ve satır sayısı 0 kalmalıdır!
    const rows3 = ctx3.rawDb
      .prepare('SELECT * FROM nickname_changes')
      .all() as { changed_at: number }[];
    expect(rows3.length).toBe(0);
  });

  it('5) Çift / eşzamanlı istek yarışında (race condition) 3. değişiklik hak limitini aşamaz (transactionSync)', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx as any, env);

    const now = 3_000_000_000;
    await profileDO.setNickname('IlkAdim', 'u_race', now);

    // 1. değişiklik
    await profileDO.setNickname('Ad1', 'u_race', now + 1000);

    // 2. ve 3. değişiklik aynı anda gönderilirse:
    const results = await Promise.allSettled([
      profileDO.setNickname('Ad2_A', 'u_race', now + 2000),
      profileDO.setNickname('Ad2_B', 'u_race', now + 2000),
    ]);

    // Biri başarılı, diğeri mutlaka reddedilmiş olmalı
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    expect(fulfilled.length).toBe(1);
    expect(rejected.length).toBe(1);

    // Toplam satır sayısı asla 2'yi aşamaz
    const changesCount = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(changesCount.cnt).toBe(2);
  });

  it('6) deleteProfile çağrıldığında nickname_changes tablosu da tamamen temizlenir', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profileDO = new UserProfile(ctx as any, env);

    const now = 4_000_000_000;
    await profileDO.setNickname('IlkAdim', 'u_del', now);
    await profileDO.setNickname('Ad1', 'u_del', now + 1000);

    const beforeDel = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(beforeDel.cnt).toBe(1);

    // Hesabı sil
    await profileDO.deleteProfile('u_del');

    const afterDel = ctx.rawDb
      .prepare('SELECT count(*) as cnt FROM nickname_changes')
      .get() as { cnt: number };
    expect(afterDel.cnt).toBe(0);
  });

  it('7) Dinamik mesaj biçimi: saat ve dakika yuvarlaması doğru çalışır', () => {
    // 14 saat
    expect(formatRemainingCooldown(14 * 3600)).toBe('14 saat sonra');
    expect(getNicknameCooldownMessage(14 * 3600)).toBe(
      'Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: 14 saat sonra.'
    );

    // 13.2 saat -> 14 saat sonra (yukarı yuvarlama)
    expect(formatRemainingCooldown(13 * 3600 + 1200)).toBe('14 saat sonra');

    // 45 dakika
    expect(formatRemainingCooldown(45 * 60)).toBe('45 dakika sonra');
    expect(getNicknameCooldownMessage(45 * 60)).toBe(
      'Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: 45 dakika sonra.'
    );

    // 50 saniye -> 1 dakika sonra
    expect(formatRemainingCooldown(50)).toBe('1 dakika sonra');
    expect(getNicknameCooldownMessage(50)).toBe(
      'Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: 1 dakika sonra.'
    );
  });

  it('8) Leaderboard güncellemesi her başarılı takma ad değişiminde çağrılır', async () => {
    const updateNicknameSpy = vi.fn();
    const ctx = createMockCtx();
    let profileStub: UserProfile | undefined;
    const env = createEnv({
      LEADERBOARD: {
        idFromName: () => 'global' as any,
        get: () => ({ updateNickname: updateNicknameSpy }),
      } as any,
      USER_PROFILE: {
        idFromName: () => 'u_lb' as any,
        get: () => {
          if (!profileStub) {
            profileStub = new UserProfile(ctx as any, env);
          }
          return profileStub as any;
        },
      } as any,
    });

    // 1. İlk ad
    await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_lb',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'LBNick1' }),
      }),
      env
    );
    expect(updateNicknameSpy).toHaveBeenCalledWith('u_lb', 'LBNick1');

    // 2. 1. değişiklik
    await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_lb',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'LBNick2' }),
      }),
      env
    );
    expect(updateNicknameSpy).toHaveBeenCalledWith('u_lb', 'LBNick2');

    // 3. 2. değişiklik
    await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:u_lb',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'LBNick3' }),
      }),
      env
    );
    expect(updateNicknameSpy).toHaveBeenCalledWith('u_lb', 'LBNick3');
  });
});
