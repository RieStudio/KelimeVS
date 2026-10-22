import * as fs from 'node:fs';
import * as path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, expect, it, vi } from 'vitest';

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

function loadEnergyContractVectors(): any {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/energy_contract.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/energy_contract.json'),
    path.resolve(__dirname, '../../shared/test-vectors/energy_contract.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8'));
    }
  }
  throw new Error('shared/test-vectors/energy_contract.json bulunamadı');
}

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

describe('Energy HTTP & Vector Contract Compliance', () => {
  const vectors = loadEnergyContractVectors();

  function createEnv(overrides: Partial<Env> = {}) {
    const userProfiles = new Map<string, UserProfile>();
    const env: Env = {
      ALLOW_DEV_AUTH: 'true',
      ENERGY_ENABLED: 'true',
      ENERGY_MAX: '5',
      ENERGY_REGEN_MINUTES: '20',
      ENERGY_COST_PER_MATCH: '1',
      ENERGY_PACK_ONE_COST: '20',
      ENERGY_PACK_FULL_COST: '80',
      START_COINS: '200',
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
    } as any;
    return { env, userProfiles };
  }

  it('GET /me dönerken energy_enabled vektör şemasını tam karşılar', async () => {
    const { env } = createEnv();
    const req = new Request('https://api.test/me', {
      headers: { Authorization: 'Bearer dev:user1' },
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;

    expect(typeof body.serverNowMs).toBe('number');
    expect(body.energy).toBeDefined();
    expect(body.energy.enabled).toBe(true);
    expect(body.energy.max).toBe(vectors.get_me_energy_enabled.energy.max);
    expect(body.energy.regenSeconds).toBe(vectors.get_me_energy_enabled.energy.regenSeconds);
    expect(Array.isArray(body.energy.packs)).toBe(true);
    expect(body.energy.packs).toHaveLength(2);
    expect(body.energy.packs[0]).toMatchObject({ id: 'one', cost: 20, energy: 1 });
    expect(body.energy.packs[1]).toMatchObject({ id: 'full', cost: 80, energy: 5 });
  });

  it('GET /me dönerken energy_disabled vektör şemasını tam karşılar', async () => {
    const { env } = createEnv({ ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: '' });
    const req = new Request('https://api.test/me', {
      headers: { Authorization: 'Bearer dev:user1' },
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;

    expect(body.energy).toBeDefined();
    expect(body.energy.enabled).toBe(false);
    expect(body.energy.current).toBe(5);
    expect(body.energy.nextEnergyAtMs).toBeNull();
    expect(body.energy.packs).toEqual([]);
  });

  it('POST /store/energy - response_400_energy_full vektörünü sağlar', async () => {
    const { env } = createEnv();
    const req = new Request('https://api.test/store/energy', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer dev:user1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(vectors.post_store_energy.request_pack_one),
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(vectors.post_store_energy.response_400_energy_full.status);
    const body = await res.json();
    expect(body).toEqual(vectors.post_store_energy.response_400_energy_full.body);
  });

  it('POST /store/energy - response_400_energy_disabled vektörünü sağlar', async () => {
    const { env } = createEnv({ ENERGY_ENABLED: 'false' });
    const req = new Request('https://api.test/store/energy', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer dev:user1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(vectors.post_store_energy.request_pack_one),
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(vectors.post_store_energy.response_400_energy_disabled.status);
    const body = await res.json();
    expect(body).toEqual(vectors.post_store_energy.response_400_energy_disabled.body);
  });

  it('POST /store/energy - response_402_not_enough_coins vektörünü sağlar', async () => {
    const { env } = createEnv({ START_COINS: '10' });
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName('user1'));
    // 2 enerji harca ki energy_full olmasın
    await profileStub.spendEnergy({ matchId: 'm1', uid: 'user1' });
    await profileStub.spendEnergy({ matchId: 'm2', uid: 'user1' });

    const req = new Request('https://api.test/store/energy', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer dev:user1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(vectors.post_store_energy.request_pack_one),
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(vectors.post_store_energy.response_402_not_enough_coins.status);
    const body = await res.json();
    expect(body).toEqual(vectors.post_store_energy.response_402_not_enough_coins.body);
  });

  it('POST /store/energy - response_200 başarılı satın alma vektörünü sağlar', async () => {
    const { env } = createEnv({ START_COINS: '200' });
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName('user1'));
    // 2 enerji harca (3 enerji kaldı)
    await profileStub.spendEnergy({ matchId: 'm1', uid: 'user1' });
    await profileStub.spendEnergy({ matchId: 'm2', uid: 'user1' });

    const req = new Request('https://api.test/store/energy', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer dev:user1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(vectors.post_store_energy.request_pack_one),
    });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(vectors.post_store_energy.response_200.status);
    const body = (await res.json()) as any;
    expect(body.success).toBe(true);
    expect(body.pack).toBe('one');
    expect(body.coins).toBe(180); // 200 - 20
    expect(body.energy).toBe(4);
    expect(body.max).toBe(5);
    expect(typeof body.nextEnergyAtMs).toBe('number');
    expect(typeof body.serverNowMs).toBe('number');
  });

  it('WebSocket matched mesajı - matchmaker_matched_with_energy ve matchmaker_matched_without_energy vektörlerini doğrular', () => {
    const withEnergy = vectors.matchmaker_matched_with_energy.message;
    expect(withEnergy.t).toBe('matched');
    expect(withEnergy.energy).toBeDefined();
    expect(withEnergy.energy.current).toBe(4);
    expect(withEnergy.energy.max).toBe(5);
    expect(typeof withEnergy.energy.nextEnergyAtMs).toBe('number');
    expect(typeof withEnergy.serverNowMs).toBe('number');

    const withoutEnergy = vectors.matchmaker_matched_without_energy.message;
    expect(withoutEnergy.t).toBe('matched');
    expect(withoutEnergy.energy).toBeUndefined();
  });
});

