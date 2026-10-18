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
import { Leaderboard } from '../src/leaderboard';
import { UserProfile } from '../src/userProfile';

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  let currentAlarm: number | null = null;

  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      if (trimmed.toUpperCase().startsWith('SELECT') || trimmed.toUpperCase().startsWith('WITH')) {
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

  const storage = {
    sql,
    getAlarm: async () => currentAlarm,
    setAlarm: async (time: number) => {
      currentAlarm = time;
    },
    deleteAlarm: async () => {
      currentAlarm = null;
    },
  };

  return { storage } as unknown as DurableObjectState;
}

function createEnv(overrides?: Partial<Env>): { env: Env; leaderboardDO: Leaderboard } {
  let leaderboardInstance: Leaderboard | null = null;
  const lbCtx = createMockCtx();

  const leaderboardNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}` };
    },
    get(id: { toString: () => string }) {
      if (!leaderboardInstance) {
        leaderboardInstance = new Leaderboard(lbCtx, fullEnv);
      }
      return leaderboardInstance;
    },
  } as unknown as DurableObjectNamespace<Leaderboard>;

  const fullEnv: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    LEADERBOARD: leaderboardNamespace,
    ALLOW_DEV_AUTH: 'true',
    ...overrides,
  };

  return { env: fullEnv, leaderboardDO: leaderboardNamespace.get({ toString: () => 'id_global' }) };
}

describe('API Route: GET /leaderboard (Auth & Response Format)', () => {
  it('1. Yetkisiz istekte (Bearer token yok) 401 döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/leaderboard', { method: 'GET' });
    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);

    const body = (await res.json()) as { error: string };
    expect(body.error).toBe('unauthorized');
  });

  it('2. Yetkili istekte (dev token) 200 döner ve format doğrulanır', async () => {
    const { env, leaderboardDO } = createEnv();

    // Veri ekle:
    // User 1: 5 galibiyet (Caller)
    // User 2: 7 galibiyet
    await leaderboardDO.recordMatchResult({
      matchId: 'm1',
      winnerUid: 'dev_user_1',
      winnerNickname: 'Oyuncu_Ben',
      loserUid: 'dev_user_loser',
      loserNickname: 'Loser',
    });
    await leaderboardDO.recordMatchResult({
      matchId: 'm2',
      winnerUid: 'dev_user_2',
      winnerNickname: 'LiderOyuncu',
      loserUid: 'dev_user_loser',
      loserNickname: 'Loser',
    });

    const req = new Request('http://127.0.0.1/leaderboard', {
      method: 'GET',
      headers: {
        Authorization: 'Bearer dev:dev_user_1',
      },
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);

    const body = (await res.json()) as any;
    expect(body.weekKey).toBeDefined();
    expect(body.endsAt).toBeGreaterThan(Date.now() - 1000);
    expect(Array.isArray(body.top)).toBe(true);
    expect(body.top).toHaveLength(2);

    // Kural 2: Yanıtta uid DÖNMEZ!
    for (const item of body.top) {
      expect(item.uid).toBeUndefined();
      expect(typeof item.rank).toBe('number');
      expect(typeof item.nickname).toBe('string');
      expect(typeof item.wins).toBe('number');
      expect(typeof item.isMe).toBe('boolean');
    }

    // Sıralamada isMe doğru mu?
    const meRow = body.top.find((e: any) => e.isMe === true);
    expect(meRow).toBeDefined();
    expect(meRow.nickname).toBe('Oyuncu_Ben');

    const otherRow = body.top.find((e: any) => e.isMe === false);
    expect(otherRow).toBeDefined();
    expect(otherRow.nickname).toBe('LiderOyuncu');

    // me nesnesi doğrulanır
    expect(body.me).toEqual({
      rank: meRow.rank,
      wins: meRow.wins,
    });
  });

  it('3. Hiç maçı olmayan kullanıcı için me null döner', async () => {
    const { env } = createEnv();

    const req = new Request('http://127.0.0.1/leaderboard', {
      method: 'GET',
      headers: {
        Authorization: 'Bearer dev:new_player_no_match',
      },
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);

    const body = (await res.json()) as any;
    expect(body.top).toEqual([]);
    expect(body.me).toBeNull();
  });
});

