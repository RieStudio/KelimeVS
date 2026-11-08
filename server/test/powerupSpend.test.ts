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
          'The Durable Object storage SQLite database does not allow manual transactions.'
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
  } as any;
}

function createEnv(overrides: Partial<Env> = {}) {
  const userProfiles = new Map<string, UserProfile>();
  const env: Env = {
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {
      idFromName(name: string) {
        return { toString: () => name } as any;
      },
      get(id: { toString: () => string }) {
        const name = id.toString();
        if (!userProfiles.has(name)) {
          userProfiles.set(name, new UserProfile(createMockCtx(), env));
        }
        return userProfiles.get(name)!;
      },
    } as any,
    ...overrides,
  };
  return { env, userProfiles };
}

describe('POST /powerups/spend - Bot Maçı Joker Harcama Endpoint Testleri', () => {
  it('1) Yeterli bakiye: 200, bakiye fiyat kadar düşer, alreadySpent false', async () => {
    const { env } = createEnv({ START_COINS: '100' });
    const req = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({
        matchId: 'bot:match-uuid-1234',
        powerup: 'extra_time',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(true);
    expect(data.coins).toBe(70); // 100 - 30 = 70
    expect(data.alreadySpent).toBe(false);
  });

  it('2) Aynı matchId+powerup ikinci kez: 200, alreadySpent true, bakiye değişmez (idempotent)', async () => {
    const { env } = createEnv({ START_COINS: '100' });
    const matchId = 'bot:idempotent-match-1234';

    // 1. çağrı
    const req1 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({ matchId, powerup: 'extra_time' }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);
    const data1 = (await res1.json()) as any;
    expect(data1.ok).toBe(true);
    expect(data1.coins).toBe(70);
    expect(data1.alreadySpent).toBe(false);

    // 2. çağrı (aynı matchId + extra_time)
    const req2 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({ matchId, powerup: 'extra_time' }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(200);
    const data2 = (await res2.json()) as any;
    expect(data2.ok).toBe(true);
    expect(data2.coins).toBe(70); // Bakiye değişmedi!
    expect(data2.alreadySpent).toBe(true);
  });

  it('3) Aynı matchId ile farklı powerup: ikisi de ayrı düşer (30 ve 50)', async () => {
    const { env } = createEnv({ START_COINS: '100' });
    const matchId = 'bot:combo-match-5678';

    // 1. Ek süre (30 jeton)
    const req1 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({ matchId, powerup: 'extra_time' }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);
    const data1 = (await res1.json()) as any;
    expect(data1.coins).toBe(70);

    // 2. Cevap Ver (50 jeton)
    const req2 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({ matchId, powerup: 'give_answer' }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(200);
    const data2 = (await res2.json()) as any;
    expect(data2.ok).toBe(true);
    expect(data2.coins).toBe(20); // 70 - 50 = 20
    expect(data2.alreadySpent).toBe(false);
  });

  it('4) Yetersiz bakiye: 402, bakiye değişmez', async () => {
    const { env } = createEnv({ START_COINS: '20' }); // 20 jeton yetersiz

    // Ek süre 30 jeton ister
    const req1 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_broke',
      },
      body: JSON.stringify({ matchId: 'bot:match-broke-1', powerup: 'extra_time' }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(402);
    const data1 = (await res1.json()) as any;
    expect(data1.ok).toBe(false);
    expect(data1.error).toBe('not_enough_coins');
    expect(data1.coins).toBe(20);

    // Cevap Ver 50 jeton ister
    const req2 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_broke',
      },
      body: JSON.stringify({ matchId: 'bot:match-broke-2', powerup: 'give_answer' }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(402);
    const data2 = (await res2.json()) as any;
    expect(data2.ok).toBe(false);
    expect(data2.error).toBe('not_enough_coins');
    expect(data2.coins).toBe(20);
  });

  it("5) Geçersiz matchId ('bot:' öneksiz, boş, çok uzun, geçersiz karakter, online oda kimliği), bilinmeyen powerup, gövde yok: 400", async () => {
    const { env } = createEnv({ START_COINS: '100' });

    const testBadRequests = [
      { name: 'Gövde yok', body: '' },
      { name: 'Geçersiz JSON', body: 'not-json' },
      { name: 'Gövde dizi', body: JSON.stringify([]) },
      { name: "bot: öneki yok (online oda kimliği)", body: JSON.stringify({ matchId: 'room_12345678', powerup: 'extra_time' }) },
      { name: "bot: öneki yok (UUID formatı)", body: JSON.stringify({ matchId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', powerup: 'extra_time' }) },
      { name: "bot: öneki sonrası çok kısa (<8)", body: JSON.stringify({ matchId: 'bot:short', powerup: 'extra_time' }) },
      { name: "bot: öneki sonrası boş", body: JSON.stringify({ matchId: 'bot:', powerup: 'extra_time' }) },
      { name: "bot: öneki sonrası çok uzun (>64)", body: JSON.stringify({ matchId: 'bot:' + 'a'.repeat(65), powerup: 'extra_time' }) },
      { name: 'Geçersiz karakter (boşluk)', body: JSON.stringify({ matchId: 'bot:match with space', powerup: 'extra_time' }) },
      { name: 'Geçersiz karakter (nokta)', body: JSON.stringify({ matchId: 'bot:match.with.dot', powerup: 'extra_time' }) },
      { name: 'Geçersiz karakter (özel)', body: JSON.stringify({ matchId: 'bot:match!@#$%^&*', powerup: 'extra_time' }) },
      { name: 'Bilinmeyen powerup', body: JSON.stringify({ matchId: 'bot:valid-match-1234', powerup: 'freeze_timer' }) },
      { name: 'Eksik powerup', body: JSON.stringify({ matchId: 'bot:valid-match-1234' }) },
      { name: 'Eksik matchId', body: JSON.stringify({ powerup: 'extra_time' }) },
    ];

    for (const tc of testBadRequests) {
      const req = new Request('http://127.0.0.1/powerups/spend', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer dev:user_1',
        },
        body: tc.body,
      });
      const res = await worker.fetch(req, env);
      expect(res.status, `${tc.name} 400 bad_request dönmeli`).toBe(400);
      const data = (await res.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error).toBe('bad_request');
    }
  });

  it('6) Gövdedeki amount alanı fiyatı etkilemez (örn. amount:1 gönderilse de 30/50 düşer)', async () => {
    const { env } = createEnv({ START_COINS: '100' });

    // amount: 1 gönderiliyor ama extra_time 30 düşmeli
    const req1 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({
        matchId: 'bot:cheat-attempt-1',
        powerup: 'extra_time',
        amount: 1, // Kötü niyetli istemci
      }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);
    const data1 = (await res1.json()) as any;
    expect(data1.coins).toBe(70); // 100 - 30 = 70 (1 değil 30 düştü)

    // amount: 99999 gönderiliyor ama give_answer 50 düşmeli
    const req2 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_1',
      },
      body: JSON.stringify({
        matchId: 'bot:cheat-attempt-2',
        powerup: 'give_answer',
        amount: 99999,
      }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(200);
    const data2 = (await res2.json()) as any;
    expect(data2.coins).toBe(20); // 70 - 50 = 20
  });

  it('7) Hesabı silinmiş kullanıcı: 410. Kimliksiz istek: 401.', async () => {
    const { env } = createEnv({ START_COINS: '100' });

    // Kimliksiz istek -> 401
    const reqNoAuth = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        matchId: 'bot:valid-match-1234',
        powerup: 'extra_time',
      }),
    });
    const resNoAuth = await worker.fetch(reqNoAuth, env);
    expect(resNoAuth.status).toBe(401);
    const dataNoAuth = (await resNoAuth.json()) as any;
    expect(dataNoAuth.error).toBe('unauthorized');

    // Hesabı silinmiş kullanıcı -> 410
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName('deleted_user'));
    await profileStub.deleteProfile('deleted_user');

    const reqDeleted = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:deleted_user',
      },
      body: JSON.stringify({
        matchId: 'bot:valid-match-1234',
        powerup: 'extra_time',
      }),
    });
    const resDeleted = await worker.fetch(reqDeleted, env);
    expect(resDeleted.status).toBe(410);
    const dataDeleted = (await resDeleted.json()) as any;
    expect(dataDeleted.ok).toBe(false);
    expect(dataDeleted.error).toBe('account_deleted');
  });

  it('8) Env ile fiyat değişince (EXTRA_TIME_COST / GIVE_ANSWER_COST) endpoint yeni fiyatı kullanır', async () => {
    const { env } = createEnv({
      START_COINS: '200',
      EXTRA_TIME_COST: '45',
      GIVE_ANSWER_COST: '85',
    });

    // 1. Ek süre 45 düşmeli
    const req1 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_custom_env',
      },
      body: JSON.stringify({
        matchId: 'bot:custom-env-match-1',
        powerup: 'extra_time',
      }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);
    const data1 = (await res1.json()) as any;
    expect(data1.coins).toBe(155); // 200 - 45 = 155

    // 2. Cevap Ver 85 düşmeli
    const req2 = new Request('http://127.0.0.1/powerups/spend', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:user_custom_env',
      },
      body: JSON.stringify({
        matchId: 'bot:custom-env-match-1',
        powerup: 'give_answer',
      }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(200);
    const data2 = (await res2.json()) as any;
    expect(data2.coins).toBe(70); // 155 - 85 = 70
  });
});
