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

import worker, { type Env } from '../src/index';
import { UserProfile } from '../src/userProfile';

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  let alarmTime: number | null = null;
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
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
      async setAlarm(t: number) {
        alarmTime = t;
      },
      async getAlarm() {
        return alarmTime;
      },
      async deleteAlarm() {
        alarmTime = null;
      },
      async deleteAll() {
        alarmTime = null;
      },
    },
  } as unknown as DurableObjectState;
}

function createEnv(overrides?: Partial<Env>): Env {
  const profilesMap = new Map<string, UserProfile>();

  const userProfileNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}` };
    },
    get(id: { toString: () => string }) {
      const key = id.toString();
      if (!profilesMap.has(key)) {
        profilesMap.set(key, new UserProfile(createMockCtx(), fullEnv));
      }
      return profilesMap.get(key)!;
    },
  } as unknown as DurableObjectNamespace<UserProfile>;

  const fullEnv: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: userProfileNamespace,
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    DISCONNECT_WIN_COINS: '30',
    DISCONNECT_LOSS_COINS: '0',
    DAILY_MATCH_COIN_CAP: '300',
    ...overrides,
  };

  return fullEnv;
}

describe('API Routes: /me & /me/nickname (auth & validation)', () => {
  it('1. GET /me yetkisiz istekte (token yok) 401 döner', async () => {
    const env = createEnv();
    const req = new Request('http://127.0.0.1/me', { method: 'GET' });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);
  });

  it('2. Kural 6: ALLOW_DEV_AUTH tanımlı değilken dev:<uid> token ile istek 401 döner', async () => {
    const env = createEnv({ ALLOW_DEV_AUTH: undefined }); // Üretim varsayılanı
    const req = new Request('http://127.0.0.1/me', {
      method: 'GET',
      headers: { Authorization: 'Bearer dev:alice' },
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);
  });

  it('3. ALLOW_DEV_AUTH=true iken dev:<uid> token ile GET /me 200 ve profili döner', async () => {
    const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
    const req = new Request('http://127.0.0.1/me', {
      method: 'GET',
      headers: { Authorization: 'Bearer dev:alice' },
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);

    const body = (await res.json()) as any;
    expect(body.uid).toBe('alice');
    expect(body.nickname).toBeNull();
    expect(body.coins).toBe(100);
    expect(body.stats).toEqual({ played: 0, won: 0, lost: 0, correctAnswers: 0 });
  });

  it('4. PUT /me/nickname geçerli adla çağrılınca günceller ve 200 döner', async () => {
    const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
    const req = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:alice',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: '   Alice_Gamer   ' }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);

    const body = (await res.json()) as any;
    expect(body.ok).toBe(true);
    expect(body.nickname).toBe('Alice_Gamer');

    // GET /me ile kontrol
    const getReq = new Request('http://127.0.0.1/me', {
      method: 'GET',
      headers: { Authorization: 'Bearer dev:alice' },
    });
    const getRes = await worker.fetch(getReq, env);
    const getBody = (await getRes.json()) as any;
    expect(getBody.nickname).toBe('Alice_Gamer');
  });

  it('5. PUT /me/nickname geçersiz ad verildiğinde 400 döner', async () => {
    const env = createEnv({ ALLOW_DEV_AUTH: 'true' });

    // 2 karakter (çok kısa)
    const reqShort = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:alice',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'ab' }),
    });
    const resShort = await worker.fetch(reqShort, env);
    expect(resShort.status).toBe(400);

    // Yasak karakter (@#)
    const reqInvalid = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:alice',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'Bad@Name!' }),
    });
    const resInvalid = await worker.fetch(reqInvalid, env);
    expect(resInvalid.status).toBe(400);
  });

  it('6. OPTIONS preflight başlığında DELETE metodu bulunur', async () => {
    const env = createEnv();
    const req = new Request('http://127.0.0.1/me', { method: 'OPTIONS' });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(204);
    const allowMethods = res.headers.get('Access-Control-Allow-Methods');
    expect(allowMethods).toContain('DELETE');
  });

  it('7. DELETE /me yetkisiz istekte 401 döner', async () => {
    const env = createEnv();
    const req = new Request('http://127.0.0.1/me', { method: 'DELETE' });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);
  });

  it('8. DELETE /me başarıyla çalışır, Matchmaker ve Leaderboard temizleme çağrılarını yapar', async () => {
    let removedFromQueueUid = '';
    let deletedLeaderboardUid = '';

    const mockMatchmaker = {
      idFromName: () => 'global',
      get: () => ({
        removeFromQueue: async (uid: string) => {
          removedFromQueueUid = uid;
        },
      }),
    };

    const mockLeaderboard = {
      idFromName: () => 'global',
      get: () => ({
        updateNickname: async () => {},
        deleteUserData: async (uid: string) => {
          deletedLeaderboardUid = uid;
        },
      }),
    };

    const env = createEnv({
      ALLOW_DEV_AUTH: 'true',
      MATCHMAKER: mockMatchmaker as any,
      LEADERBOARD: mockLeaderboard as any,
    });

    // Önce kullanıcı profili oluşturalım
    const putReq = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:carol',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'CarolPlayer' }),
    });
    const putRes = await worker.fetch(putReq, env);
    expect(putRes.status).toBe(200);

    // DELETE /me çağır
    const delReq = new Request('http://127.0.0.1/me', {
      method: 'DELETE',
      headers: { Authorization: 'Bearer dev:carol' },
    });
    const delRes = await worker.fetch(delReq, env);
    expect(delRes.status).toBe(200);
    const delBody = (await delRes.json()) as any;
    expect(delBody.ok).toBe(true);
    expect(delBody.deleted).toBe(true);

    expect(removedFromQueueUid).toBe('carol');
    expect(deletedLeaderboardUid).toBe('carol');

    // 2. Kural: DELETE /me tombstone varken de 200 döner (idempotent)
    const delAgainRes = await worker.fetch(delReq, env);
    expect(delAgainRes.status).toBe(200);

    // Silinmiş hesaba GET /me yapıldığında 410 Gone döner
    const getRes = await worker.fetch(
      new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:carol' },
      }),
      env
    );
    expect(getRes.status).toBe(410);
    const getBody = (await getRes.json()) as any;
    expect(getBody.error).toBe('account_deleted');

    // Silinmiş hesaba PUT /me/nickname yapıldığında 410 Gone döner
    const putAfterDelRes = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:carol',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'NewCarol' }),
      }),
      env
    );
    expect(putAfterDelRes.status).toBe(410);
    const putAfterDelBody = (await putAfterDelRes.json()) as any;
    expect(putAfterDelBody.error).toBe('account_deleted');
  });

  it('7. Misafir kullanıcı GET /me çağırınca isGuest: true ve M-#### formatında ad döner', async () => {
    const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
    const req = new Request('http://127.0.0.1/me', {
      method: 'GET',
      headers: { Authorization: 'Bearer dev:guest:misafir_user' },
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);

    const body = (await res.json()) as any;
    expect(body.uid).toBe('misafir_user');
    expect(body.isGuest).toBe(true);
    expect(body.nickname).toMatch(/^M-[1-9]\d{3}$/);
  });

  describe('8. Misafir takma ad kilidi ve eski istemci (X-App-Build < 13) uyumluluk katmanı', () => {
    it('8a. build yok (veya 0) + misafir: 200 döner, gönderilen ad yok sayılır ve sunucudaki M-#### adı korunur', async () => {
      const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
      const req = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:guest:misafir_nobuild',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'OzelTakmaAd' }),
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(200);

      const body = (await res.json()) as any;
      expect(body.ok).toBe(true);
      expect(body.nickname).toMatch(/^M-[1-9]\d{3}$/);
      expect(body.nickname).not.toBe('OzelTakmaAd');

      // GET /me ile DB'deki takma adın değişmediğini doğrula
      const getReq = new Request('http://127.0.0.1/me', {
        headers: { Authorization: 'Bearer dev:guest:misafir_nobuild' },
      });
      const getRes = await worker.fetch(getReq, env);
      const getBody = (await getRes.json()) as any;
      expect(getBody.nickname).toBe(body.nickname);
      expect(getBody.nickname).not.toBe('OzelTakmaAd');
    });

    it('8b. build 12 + misafir: 200 döner, ad değişmez ve mevcut M-#### adı döner', async () => {
      const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
      const req = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:guest:misafir_b12',
          'X-App-Build': '12',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'HackerAd' }),
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(200);

      const body = (await res.json()) as any;
      expect(body.ok).toBe(true);
      expect(body.nickname).toMatch(/^M-[1-9]\d{3}$/);
      expect(body.nickname).not.toBe('HackerAd');

      // GET /me doğrulaması
      const getReq = new Request('http://127.0.0.1/me', {
        headers: { Authorization: 'Bearer dev:guest:misafir_b12' },
      });
      const getRes = await worker.fetch(getReq, env);
      const getBody = (await getRes.json()) as any;
      expect(getBody.nickname).toBe(body.nickname);
      expect(getBody.nickname).not.toBe('HackerAd');
    });

    it('8c. build 13 + misafir: 403 guest_nickname_locked döner', async () => {
      const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
      const req = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:guest:misafir_b13',
          'X-App-Build': '13',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'OzelTakmaAd' }),
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(403);

      const body = (await res.json()) as any;
      expect(body.error).toBe('guest_nickname_locked');
      expect(body.message).toContain('Misafir hesaplar takma ad değiştiremez');
    });

    it('8d. GUEST_NICKNAME_LOCK_MIN_BUILD ortam değişkeni ile eşik güncellenebilir', async () => {
      const env = createEnv({
        ALLOW_DEV_AUTH: 'true',
        GUEST_NICKNAME_LOCK_MIN_BUILD: '15',
      });

      // Build 14 (< 15) -> 200 dönmeli
      const req14 = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:guest:misafir_b14',
          'X-App-Build': '14',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'OzelAd14' }),
      });
      const res14 = await worker.fetch(req14, env);
      expect(res14.status).toBe(200);
      const body14 = (await res14.json()) as any;
      expect(body14.ok).toBe(true);
      expect(body14.nickname).toMatch(/^M-[1-9]\d{3}$/);

      // Build 15 (>= 15) -> 403 dönmeli
      const req15 = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:guest:misafir_b15',
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'OzelAd15' }),
      });
      const res15 = await worker.fetch(req15, env);
      expect(res15.status).toBe(403);
      const body15 = (await res15.json()) as any;
      expect(body15.error).toBe('guest_nickname_locked');
    });

    it('8e. Google token + build 12: mevcut ad değiştirme ve cooldown kuralları aynen geçerlidir', async () => {
      const env = createEnv({ ALLOW_DEV_AUTH: 'true' });
      const req = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:google_user_b12',
          'X-App-Build': '12',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'GoogleAd' }),
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(200);

      const body = (await res.json()) as any;
      expect(body.ok).toBe(true);
      expect(body.nickname).toBe('GoogleAd');

      // 24 saat geçmeden tekrar ad değiştirmeye çalışırsa 429 Cooldown almalı
      const reqCooldown = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:google_user_b12',
          'X-App-Build': '12',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'YeniGoogleAd' }),
      });
      const resCooldown = await worker.fetch(reqCooldown, env);
      expect(resCooldown.status).toBe(429);
      expect(resCooldown.headers.get('Retry-After')).toBeTruthy();
      const bodyCooldown = (await resCooldown.json()) as any;
      expect(bodyCooldown.error).toBe('nickname_cooldown');
    });
  });

  it('9. Şema değişikliğinden ÖNCE oluşturulmuş profiller: GET /me ile Google kullanıcısının "Sevbans" adı korunur, eski anonim ad M-#### olur', async () => {
    const profilesMap = new Map<string, UserProfile>();
    const fullEnv: Env = {
      MATCHMAKER: {} as any,
      MATCH_ROOM: {} as any,
      USER_PROFILE: {
        idFromName(name: string) {
          return { toString: () => `id_${name}` };
        },
        get(id: { toString: () => string }) {
          const key = id.toString();
          if (!profilesMap.has(key)) {
            profilesMap.set(key, new UserProfile(createMockCtx(), fullEnv));
          }
          return profilesMap.get(key)!;
        },
      } as any,
      ALLOW_DEV_AUTH: 'true',
      START_COINS: '100',
      WIN_COINS: '30',
      LOSS_COINS: '5',
      DISCONNECT_WIN_COINS: '30',
      DISCONNECT_LOSS_COINS: '0',
      DAILY_MATCH_COIN_CAP: '300',
    };

    // 1. Şema migrasyonu öncesi DO SQLite tablosu simülasyonu
    const sevbansCtx = createMockCtx();
    sevbansCtx.storage.sql.exec(`
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
      VALUES ('sevbans_user', 'Sevbans', 120, 3, 2, 1, 5, 1000, 'classic', 5, 0, 500);
    `);
    profilesMap.set('id_sevbans_user', new UserProfile(sevbansCtx, fullEnv));

    const anonCtx = createMockCtx();
    anonCtx.storage.sql.exec(`
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
      VALUES ('legacy_anon_user', 'EskiAnonimAd', 120, 3, 2, 1, 5, 1000, 'classic', 5, 0, 500);
    `);
    profilesMap.set('id_legacy_anon_user', new UserProfile(anonCtx, fullEnv));

    // 2. Google token ile GET /me (dev:sevbans_user -> auth.isGuest === false)
    const googleRes = await worker.fetch(
      new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:sevbans_user' },
      }),
      fullEnv
    );
    expect(googleRes.status).toBe(200);
    const googleBody = (await googleRes.json()) as any;
    expect(googleBody.uid).toBe('sevbans_user');
    expect(googleBody.nickname).toBe('Sevbans');
    expect(googleBody.isGuest).toBe(false);

    // 3. Anonim token ile GET /me (dev:guest:legacy_anon_user -> auth.isGuest === true)
    const anonRes = await worker.fetch(
      new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:guest:legacy_anon_user' },
      }),
      fullEnv
    );
    expect(anonRes.status).toBe(200);
    const anonBody = (await anonRes.json()) as any;
    expect(anonBody.uid).toBe('legacy_anon_user');
    expect(anonBody.nickname).toMatch(/^M-[1-9]\d{3}$/);
    expect(anonBody.nickname).not.toBe('EskiAnonimAd');
    expect(anonBody.isGuest).toBe(true);
  });
});

