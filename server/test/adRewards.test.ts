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
import { GOOGLE_JWK_URL, resetDefaultKeyCache, type JwkKey } from '../src/auth';

function uint8ArrayToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function utf8ToBase64Url(str: string): string {
  return uint8ArrayToBase64Url(new TextEncoder().encode(str));
}

async function generateTestKeyPair(kid = 'key-ad-test') {
  const keyPair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify']
  )) as CryptoKeyPair;

  const exported = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JwkKey;
  const jwk: JwkKey = { ...exported, kid, alg: 'RS256', use: 'sig' };
  return { keyPair, jwk };
}

async function signJwt(header: object, payload: object, privateKey: CryptoKey): Promise<string> {
  const h = utf8ToBase64Url(JSON.stringify(header));
  const p = utf8ToBase64Url(JSON.stringify(payload));
  const data = new TextEncoder().encode(`${h}.${p}`);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, data);
  return `${h}.${p}.${uint8ArrayToBase64Url(new Uint8Array(sig))}`;
}

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  const sql = {
    exec<T extends Record<string, unknown>>(query: string, ...bindings: unknown[]) {
      const trimmed = query.trim();
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('PRAGMA')
      ) {
        const stmt = db.prepare(trimmed);
        const rows = stmt.all(...(bindings as never[])) as T[];
        return {
          toArray: () => rows,
          one: () => rows[0],
          [Symbol.iterator]: () => rows[Symbol.iterator](),
        };
      }
      if (bindings.length === 0) {
        db.exec(trimmed);
      } else {
        db.prepare(trimmed).run(...(bindings as never[]));
      }
      return {
        toArray: () => [] as T[],
        one: () => undefined,
        [Symbol.iterator]: () => [][Symbol.iterator](),
      };
    },
  };

  return {
    db,
    ctx: {
      storage: {
        sql,
        transactionSync: <T>(fn: () => T): T => fn(),
        setAlarm: async () => {},
        deleteAll: async () => {},
      },
      getWebSockets: () => [],
    } as unknown as DurableObjectState,
  };
}

function createTestEnv(overrides: Partial<Env> = {}): Env {
  return {
    FIREBASE_PROJECT_ID: 'kelimegov2',
    ENERGY_ENABLED: 'true',
    ENERGY_MAX: '5',
    ENERGY_REGEN_MINUTES: '20',
    AD_REWARDS_ENABLED: 'true',
    AD_REWARD_ENERGY_AMOUNT: '1',
    AD_REWARD_ENERGY_DAILY_CAP: '3',
    AD_REWARD_COINS_AMOUNT: '15',
    AD_REWARD_COINS_DAILY_CAP: '3',
    AD_REWARD_MIN_INTERVAL_SECONDS: '60',
    ...overrides,
  } as unknown as Env;
}

describe('Ad Rewards DO & HTTP API', () => {
  it('başarılı enerji ödülü verir ve max enerjiyi aşmaz', async () => {
    const { ctx, db } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    await profile.getProfile('u1', 0, false, nowMs);
    db.prepare('UPDATE profiles SET energy = 2, energy_updated_at = ?').run(nowMs);

    const res = await profile.claimAdReward({
      type: 'energy',
      claimId: 'claim_energy_01',
      uid: 'u1',
      nowMs,
    });

    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.granted).toBe(true);
      expect(res.energy.current).toBe(3);
      expect(res.remainingToday.energy).toBe(2);
      expect(res.remainingToday.coins).toBe(3);
      expect(res.nextClaimAtMs).toBe(nowMs + 60_000);
    }
  });

  it('enerji zaten max iken energy_full döner ve günlük sınırı düşmez', async () => {
    const { ctx } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    await profile.getProfile('u1', 0, false, nowMs);
    const res = await profile.claimAdReward({
      type: 'energy',
      claimId: 'claim_full_01',
      uid: 'u1',
      nowMs,
    });

    expect(res).toEqual({ ok: false, error: 'energy_full' });

    const me = await profile.getProfile('u1', 0, false, nowMs);
    expect(me.adRewards?.energy.remaining).toBe(3);
  });

  it('başarılı jeton ödülü verir; daily_coins ve istatistiklere dokunmaz', async () => {
    const { ctx, db } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    const before = await profile.getProfile('u1', 0, false, nowMs);
    const res = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_coins_01',
      uid: 'u1',
      nowMs,
    });

    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.granted).toBe(true);
      expect(res.coins).toBe(before.coins + 15);
      expect(res.remainingToday.coins).toBe(2);
    }

    const dailyCoinsRows = db.prepare('SELECT * FROM daily_coins').all();
    expect(dailyCoinsRows.length).toBe(0);

    const after = await profile.getProfile('u1', 0, false, nowMs);
    expect(after.stats).toEqual({ played: 0, won: 0, lost: 0, correctAnswers: 0 });
  });

  it('aynı claimId ile ikinci çağrı idempotenttir (ikinci kez ödül vermez)', async () => {
    const { ctx } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    const first = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_idem_01',
      uid: 'u1',
      nowMs,
    });
    expect(first.ok).toBe(true);

    const second = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_idem_01',
      uid: 'u1',
      nowMs: nowMs + 5_000,
    });
    expect(second.ok).toBe(true);
    if (first.ok && second.ok) {
      expect(second.granted).toBe(false);
      expect(second.alreadyProcessed).toBe(true);
      expect(second.coins).toBe(first.coins);
      expect(second.remainingToday.coins).toBe(2);
    }
  });

  it('bekleme süresi dolmadan gelen farklı claimId too_soon döner', async () => {
    const { ctx } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_cool_01',
      uid: 'u1',
      nowMs,
    });

    const tooSoon = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_cool_02',
      uid: 'u1',
      nowMs: nowMs + 15_000,
    });

    expect(tooSoon).toEqual({
      ok: false,
      error: 'too_soon',
      retryAfterSeconds: 45,
      nextClaimAtMs: nowMs + 60_000,
    });
  });

  it('günlük sınır dolunca daily_limit_reached döner ve ertesi UTC gün sıfırlanır', async () => {
    const { ctx } = createMockCtx();
    const env = createTestEnv({ AD_REWARD_COINS_DAILY_CAP: '2' });
    const profile = new UserProfile(ctx, env);
    const day1 = Date.UTC(2026, 10, 25, 23, 50, 0);

    await profile.claimAdReward({ type: 'coins', claimId: 'claim_d1_01', uid: 'u1', nowMs: day1 });
    await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_d1_02',
      uid: 'u1',
      nowMs: day1 + 61_000,
    });

    const capped = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_d1_03',
      uid: 'u1',
      nowMs: day1 + 122_000,
    });
    expect(capped.ok).toBe(false);
    if (!capped.ok) {
      expect(capped.error).toBe('daily_limit_reached');
      expect(capped.remainingToday?.coins).toBe(0);
    }

    const day2 = Date.UTC(2026, 10, 26, 0, 5, 0);
    const nextDay = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_d2_01',
      uid: 'u1',
      nowMs: day2,
    });
    expect(nextDay.ok).toBe(true);
    if (nextDay.ok) {
      expect(nextDay.remainingToday.coins).toBe(1);
    }
  });

  it('AD_REWARDS_ENABLED=false iken ads_disabled döner', async () => {
    const { ctx } = createMockCtx();
    const env = createTestEnv({ AD_REWARDS_ENABLED: 'false' });
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    const res = await profile.claimAdReward({
      type: 'coins',
      claimId: 'claim_disabled_01',
      uid: 'u1',
      nowMs,
    });
    expect(res).toEqual({ ok: false, error: 'ads_disabled' });
  });

  it('deleteProfile tabloları temizler ve tombstone sonrası 410 fırlatır', async () => {
    const { ctx, db } = createMockCtx();
    const env = createTestEnv();
    const profile = new UserProfile(ctx, env);
    const nowMs = Date.UTC(2026, 10, 25, 10, 0, 0);

    await profile.claimAdReward({ type: 'coins', claimId: 'claim_del_01', uid: 'u1', nowMs });
    await profile.deleteProfile('u1');

    expect(db.prepare('SELECT * FROM ad_rewards_daily').all().length).toBe(0);
    expect(db.prepare('SELECT * FROM processed_ad_rewards').all().length).toBe(0);

    await expect(
      profile.claimAdReward({ type: 'coins', claimId: 'claim_del_02', uid: 'u1', nowMs })
    ).rejects.toThrow('account_deleted');
  });

  it('budama: processed_ad_rewards max 100 kayıt, ad_rewards_daily 7 günden eski günleri siler', async () => {
    const { ctx, db } = createMockCtx();
    const env = createTestEnv({ AD_REWARD_COINS_DAILY_CAP: '200', AD_REWARD_MIN_INTERVAL_SECONDS: '0' });
    const profile = new UserProfile(ctx, env);
    const baseMs = Date.UTC(2026, 10, 25, 12, 0, 0);

    await profile.getProfile('u1', 0, false, baseMs);
    db.prepare("INSERT INTO ad_rewards_daily (day_key, reward_type, count) VALUES ('2026-11-10', 'coins', 2)").run();

    for (let i = 0; i < 105; i++) {
      await profile.claimAdReward({
        type: 'coins',
        claimId: `claim_prune_${i.toString().padStart(3, '0')}`,
        uid: 'u1',
        nowMs: baseMs + i * 10,
      });
    }

    const processedCount = (
      db.prepare('SELECT COUNT(*) AS cnt FROM processed_ad_rewards').get() as { cnt: number }
    ).cnt;
    expect(processedCount).toBe(100);

    const oldDays = db
      .prepare("SELECT * FROM ad_rewards_daily WHERE day_key = '2026-11-10'")
      .all();
    expect(oldDays.length).toBe(0);
  });

  it('HTTP: GET /me adRewards alanını döndürür, POST /ads/reward doğrulama ve 410 çalışır', async () => {
    const { ctx } = createMockCtx();
    const baseEnv = createTestEnv({ ALLOW_DEV_AUTH: 'true' });
    const profileStub = new UserProfile(ctx, baseEnv);

    const env = {
      ...baseEnv,
      USER_PROFILE: {
        idFromName: (name: string) => name as unknown as DurableObjectId,
        get: () => profileStub,
      } as unknown as DurableObjectNamespace<UserProfile>,
    } as Env;

    const authHeaders = {
      Authorization: 'Bearer dev:u_http_ad',
      'Content-Type': 'application/json',
    };

    const meRes = await worker.fetch(
      new Request('https://api.riestudio.com.tr/me', {
        headers: { Authorization: 'Bearer dev:u_http_ad' },
      }),
      env
    );
    expect(meRes.status).toBe(200);
    const meJson = (await meRes.json()) as {
      adRewards?: { enabled: boolean; coins: { remaining: number; cap: number } };
    };
    expect(meJson.adRewards?.enabled).toBe(true);
    expect(meJson.adRewards?.coins).toEqual({ remaining: 3, cap: 3 });

    const badTypeRes = await worker.fetch(
      new Request('https://api.riestudio.com.tr/ads/reward', {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({ type: 'gold', claimId: 'valid_claim_123' }),
      }),
      env
    );
    expect(badTypeRes.status).toBe(400);

    const badClaimRes = await worker.fetch(
      new Request('https://api.riestudio.com.tr/ads/reward', {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({ type: 'coins', claimId: 'short' }),
      }),
      env
    );
    expect(badClaimRes.status).toBe(400);

    const okRes = await worker.fetch(
      new Request('https://api.riestudio.com.tr/ads/reward', {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({ type: 'coins', claimId: 'valid_claim_123' }),
      }),
      env
    );
    expect(okRes.status).toBe(200);

    await profileStub.deleteProfile('u_http_ad');
    const deletedRes = await worker.fetch(
      new Request('https://api.riestudio.com.tr/ads/reward', {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({ type: 'coins', claimId: 'valid_claim_456' }),
      }),
      env
    );
    expect(deletedRes.status).toBe(410);
  });
});
