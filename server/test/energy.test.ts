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
  calculateRegeneratedEnergy,
  isEnergyEnabledForUser,
  getEnergyMax,
  getEnergyRegenMinutes,
  buildEnergyPacks,
} from '../src/energy';
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

describe('Energy System - calculateRegeneratedEnergy', () => {
  const max = 5;
  const regenMinutes = 20;
  const regenIntervalMs = 20 * 60 * 1000; // 1,200,000 ms

  it('tam enerji (max) iken süre geçse bile enerji max kalır ve nextEnergyAtMs null döner', () => {
    const res = calculateRegeneratedEnergy(5, 1000, 1000 + regenIntervalMs * 10, max, regenMinutes);
    expect(res.current).toBe(5);
    expect(res.gained).toBe(0);
    expect(res.nextEnergyAtMs).toBeNull();
  });

  it('eksik enerji (3/5) iken henüz 20 dakika dolmamışsa (10 dk) artış olmaz, sonraki yenilenme süresi hesaplanır', () => {
    const start = 1000000;
    const now = start + 10 * 60 * 1000;
    const res = calculateRegeneratedEnergy(3, start, now, max, regenMinutes);
    expect(res.current).toBe(3);
    expect(res.gained).toBe(0);
    expect(res.updatedAtMs).toBe(start);
    expect(res.nextEnergyAtMs).toBe(start + regenIntervalMs);
  });

  it('eksik enerji (3/5) iken tam 20 dakika geçtiğinde 1 enerji kazanır ve sonraki yenilenme 20 dk sonradır', () => {
    const start = 1000000;
    const now = start + regenIntervalMs;
    const res = calculateRegeneratedEnergy(3, start, now, max, regenMinutes);
    expect(res.current).toBe(4);
    expect(res.gained).toBe(1);
    expect(res.updatedAtMs).toBe(now);
    expect(res.nextEnergyAtMs).toBe(now + regenIntervalMs);
  });

  it('eksik enerji (3/5) iken 45 dakika geçtiğinde 2 enerji kazanıp max olur (5/5) ve nextEnergyAtMs null döner', () => {
    const start = 1000000;
    const now = start + 45 * 60 * 1000;
    const res = calculateRegeneratedEnergy(3, start, now, max, regenMinutes);
    expect(res.current).toBe(5);
    expect(res.gained).toBe(2);
    expect(res.nextEnergyAtMs).toBeNull();
  });

  it('eksik enerji (1/5) iken çok uzun süre bekledikten sonra (24 saat) max üstüne çıkmaz (cap at 5)', () => {
    const start = 1000000;
    const now = start + 24 * 3600 * 1000;
    const res = calculateRegeneratedEnergy(1, start, now, max, regenMinutes);
    expect(res.current).toBe(5);
    expect(res.nextEnergyAtMs).toBeNull();
  });
});

describe('Energy System - Helper & Feature Flags', () => {
  it('isEnergyEnabledForUser ENERGY_ENABLED=true iken tüm kullanıcılara true döner', () => {
    const env = { ENERGY_ENABLED: 'true' };
    expect(isEnergyEnabledForUser(env, 'user1')).toBe(true);
    expect(isEnergyEnabledForUser(env, 'ghost-123')).toBe(true);
  });

  it('isEnergyEnabledForUser ENERGY_ENABLED=false iken yalnızca ENERGY_TEST_UIDS listesindekilere true döner', () => {
    const env = { ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: 'user_alpha, user_test' };
    expect(isEnergyEnabledForUser(env, 'user_alpha')).toBe(true);
    expect(isEnergyEnabledForUser(env, 'user_test')).toBe(true);
    expect(isEnergyEnabledForUser(env, 'user_other')).toBe(false);
    expect(isEnergyEnabledForUser(env, 'ghost-123')).toBe(false);

    // ENERGY_TEST_UIDS tanımlı değilken veya boşken
    expect(isEnergyEnabledForUser({ ENERGY_ENABLED: 'false' }, 'user_alpha')).toBe(false);
    expect(isEnergyEnabledForUser({ ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: '' }, 'user_alpha')).toBe(false);
    expect(isEnergyEnabledForUser({ ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: '   ' }, 'user_alpha')).toBe(false);
    expect(isEnergyEnabledForUser({ ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: ', , ' }, 'user_alpha')).toBe(false);

    // Boşluklu ve virgüllü formatı destekler
    const envPadded = { ENERGY_ENABLED: 'false', ENERGY_TEST_UIDS: '  user_alpha ,  user_beta  , ' };
    expect(isEnergyEnabledForUser(envPadded, 'user_alpha')).toBe(true);
    expect(isEnergyEnabledForUser(envPadded, 'user_beta')).toBe(true);
    expect(isEnergyEnabledForUser(envPadded, '')).toBe(false);
  });
});

describe('Energy System - UserProfile DO & Storage Operations', () => {
  function createProfile(envOverrides: Partial<Env> = {}) {
    const ctx = createMockCtx();
    const env: Env = {
      ENERGY_ENABLED: 'true',
      ENERGY_MAX: '5',
      ENERGY_REGEN_MINUTES: '20',
      ENERGY_COST_PER_MATCH: '1',
      ENERGY_PACK_ONE_COST: '20',
      ENERGY_PACK_FULL_COST: '80',
      START_COINS: '100',
      ...envOverrides,
    } as any;
    const profile = new UserProfile(ctx, env);
    return { profile, ctx, env };
  }

  it('yeni oluşturulan profilde başlangıç enerjisi max (5) ve energy_updated_at 0 olarak başlar', async () => {
    const { profile } = createProfile();
    const state = await profile.getEnergyState('u1', 1000000);
    expect(state.enabled).toBe(true);
    expect(state.current).toBe(5);
    expect(state.max).toBe(5);
    expect(state.nextEnergyAtMs).toBeNull();
    expect(state.packs).toHaveLength(2);
  });

  it('tam enerjiden ilk harcama: energy_updated_at harcama anına (nowMs) ayarlanır, timer hemen enerji vermez', async () => {
    const { profile } = createProfile();
    const t0 = 1000000;
    // t0 anında harcama yapılıyor
    const spendRes = await profile.spendEnergy({
      matchId: 'match-1',
      uid: 'u1',
      nowMs: t0,
    });
    expect(spendRes.success).toBe(true);
    expect(spendRes.energy).toBe(4);

    // 5 dakika sonra durum sorgulanır (20 dk dolmadı, enerji 4 kalmalı)
    const t5 = t0 + 5 * 60 * 1000;
    const state5 = await profile.getEnergyState('u1', t5);
    expect(state5.current).toBe(4);
    expect(state5.nextEnergyAtMs).toBe(t0 + 20 * 60 * 1000);

    // 20 dakika sonra tam 1 enerji yenilenmeli
    const t20 = t0 + 20 * 60 * 1000;
    const state20 = await profile.getEnergyState('u1', t20);
    expect(state20.current).toBe(5);
    expect(state20.nextEnergyAtMs).toBeNull();
  });

  it('aynı matchId ile spendEnergy tekrar çağrılırsa idempotenttir (alreadySpent: true, enerji tekrar düşmez)', async () => {
    const { profile } = createProfile();
    const t0 = 1000000;
    await profile.spendEnergy({ matchId: 'match-idem', uid: 'u1', nowMs: t0 });

    const secondSpend = await profile.spendEnergy({ matchId: 'match-idem', uid: 'u1', nowMs: t0 + 1000 });
    expect(secondSpend.success).toBe(true);
    expect(secondSpend.alreadySpent).toBe(true);
    expect(secondSpend.energy).toBe(4);
  });

  it('enerji 0 iken spendEnergy çağrılırsa not_enough_energy döner', async () => {
    const { profile } = createProfile();
    // 5 enerjiyi 5 maçta harca
    for (let i = 1; i <= 5; i++) {
      await profile.spendEnergy({ matchId: `m-${i}`, uid: 'u1', nowMs: 1000000 });
    }

    const failedSpend = await profile.spendEnergy({ matchId: 'm-6', uid: 'u1', nowMs: 1000000 });
    expect(failedSpend.success).toBe(false);
    expect(failedSpend.error).toBe('not_enough_energy');
    expect(failedSpend.energy).toBe(0);
  });

  it('refundEnergy harcanan enerjiyi iade eder ve idempotenttir', async () => {
    const { profile } = createProfile();
    await profile.spendEnergy({ matchId: 'm-refund', uid: 'u1', nowMs: 1000000 });

    const refund1 = await profile.refundEnergy({ matchId: 'm-refund', uid: 'u1', nowMs: 1005000 });
    expect(refund1.ok).toBe(true);
    expect(refund1.refunded).toBe(true);
    expect(refund1.energy).toBe(5);

    // İkinci çağrıda tekrar iade edilmez
    const refund2 = await profile.refundEnergy({ matchId: 'm-refund', uid: 'u1', nowMs: 1006000 });
    expect(refund2.ok).toBe(true);
    expect(refund2.refunded).toBe(false);
    expect(refund2.energy).toBe(5);
  });

  it('purchaseEnergy paket satın alma kuralları: dolu iken reddeder, bakiye yetersizse 402 döner, satın alımda bakiye düşüp enerjiyi artırır', async () => {
    const { profile } = createProfile({ START_COINS: '50' });
    await profile.getProfile('u1'); // 50 jetonla başlar

    // 1. Dolu iken satın alma
    const fullErr = await profile.purchaseEnergy({ pack: 'one', uid: 'u1', nowMs: 1000000 });
    expect(fullErr.success).toBe(false);
    if (!fullErr.success) {
      expect(fullErr.error).toBe('energy_full');
    }

    // 2. 2 enerji harca (3 enerji kaldı)
    await profile.spendEnergy({ matchId: 'p-m1', uid: 'u1', nowMs: 1000000 });
    await profile.spendEnergy({ matchId: 'p-m2', uid: 'u1', nowMs: 1000000 });

    // 3. 'one' paketi satın al (fiyat: 20 jeton, 50-20=30 jeton, 3+1=4 enerji)
    const buyOne = await profile.purchaseEnergy({ pack: 'one', uid: 'u1', nowMs: 1000000 });
    expect(buyOne.success).toBe(true);
    if (buyOne.success) {
      expect(buyOne.coins).toBe(30);
      expect(buyOne.energy).toBe(4);
      expect(buyOne.pack).toBe('one');
    }

    // 4. 'full' paketi satın almayı dene (fiyat: 80, bakiyesi 30 -> yetersiz bakiye)
    const buyFullErr = await profile.purchaseEnergy({ pack: 'full', uid: 'u1', nowMs: 1000000 });
    expect(buyFullErr.success).toBe(false);
    if (!buyFullErr.success) {
      expect(buyFullErr.error).toBe('not_enough_coins');
      expect(buyFullErr.coins).toBe(30);
    }
  });

  it('adminGrant ile enerji tanımlama çalışır ve 0-MAX aralığına sınırlar', async () => {
    const { profile } = createProfile();
    const res = await profile.adminGrant({ uid: 'u1', energy: 2 });
    expect(res.success).toBe(true);
    if (res.success) {
      expect(res.energy).toBe(2);
    }

    const state = await profile.getEnergyState('u1', 1000000);
    expect(state.current).toBe(2);

    // 10 versek bile max olan 5'e sınırlanır
    const resMax = await profile.adminGrant({ uid: 'u1', energy: 10 });
    expect(resMax.success).toBe(true);
    if (resMax.success) {
      expect(resMax.energy).toBe(5);
    }
  });
});

