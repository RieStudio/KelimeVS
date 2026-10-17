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
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
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
    storage: { sql },
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
    expect(body.stats).toEqual({ played: 0, won: 0, lost: 0 });
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
});

