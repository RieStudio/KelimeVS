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

  let alarmTime: number | null = null;
  const storage = {
    sql,
    getAlarm: async () => alarmTime,
    setAlarm: async (time: number) => {
      alarmTime = time;
    },
    deleteAlarm: async () => {
      alarmTime = null;
    },
    deleteAll: async () => {
      db.exec(`
        DROP TABLE IF EXISTS profiles;
        DROP TABLE IF EXISTS tombstone;
        DROP TABLE IF EXISTS blocked_users;
      `);
    },
    transactionSync: <T>(fn: () => T): T => fn(),
  };

  return { storage, db } as unknown as DurableObjectState & { db: DatabaseSync };
}

function createDO(overrides?: Partial<Env>) {
  const ctx = createMockCtx();
  const env: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    START_COINS: '100',
    ALLOW_DEV_AUTH: 'true',
    ...overrides,
  };
  return { userProfile: new UserProfile(ctx, env), ctx };
}

describe('UserProfile.getPublicProfile & Block Info Methods', () => {
  it('1. Var olmayan UID için getPublicProfile kind: "not_found" döner ve kesinlikle profil satırı OLUŞTURMAZ (sıfır yan etki)', async () => {
    const { userProfile, ctx } = createDO();

    const res = await userProfile.getPublicProfile();
    expect(res).toEqual({ kind: 'not_found' });

    // SQLite profiles tablosunun boş olduğunu doğrula
    const rows = (ctx as any).db.prepare('SELECT count(*) as count FROM profiles').all();
    expect(rows[0].count).toBe(0);
  });

  it('2. Normal profilde yalnızca beyaz listeli alanları döner; hassas alan sızıntısı yoktur', async () => {
    const { userProfile } = createDO();

    // Normal profil oluştur
    await userProfile.getProfile('user_alice', 0, false);
    await userProfile.setNickname('AliceTheGreat', 'user_alice');
    await userProfile.applyMatchReward({
      matchId: 'm1',
      outcome: 'win',
      uid: 'user_alice',
      correctAnswers: 15,
    });
    await userProfile.applyMatchReward({
      matchId: 'm2',
      outcome: 'loss',
      uid: 'user_alice',
      correctAnswers: 5,
    });

    const res = await userProfile.getPublicProfile();
    expect(res.kind).toBe('ok');
    if (res.kind !== 'ok') return;

    expect(res.profile.nickname).toBe('AliceTheGreat');
    expect(res.profile.equippedFrame).toBe('classic');
    expect(res.profile.isGuest).toBe(false);
    expect(res.profile.stats).toEqual({
      played: 2,
      won: 1,
      lost: 1,
      winRate: 50,
    });

    // Anahtarları tam liste olarak doğrula (white-list)
    const profileKeys = Object.keys(res.profile).sort();
    expect(profileKeys).toEqual(['equippedFrame', 'isGuest', 'nickname', 'stats']);

    const statsKeys = Object.keys(res.profile.stats).sort();
    expect(statsKeys).toEqual(['lost', 'played', 'winRate', 'won']);

    // Hassas alanların ASLA sızmadığını assert et
    const raw = res.profile as any;
    expect(raw.coins).toBeUndefined();
    expect(raw.email).toBeUndefined();
    expect(raw.energy).toBeUndefined();
    expect(raw.token).toBeUndefined();
    expect(raw.createdAt).toBeUndefined();
    expect(raw.stats.correctAnswers).toBeUndefined();
  });

  it('3. Misafir hesapta isGuest: true döner ve M-#### takma adı döner', async () => {
    const { userProfile } = createDO();

    await userProfile.getProfile('guest_12345', 0, true);

    const res = await userProfile.getPublicProfile();
    expect(res.kind).toBe('ok');
    if (res.kind !== 'ok') return;

    expect(res.profile.isGuest).toBe(true);
    expect(res.profile.nickname).toMatch(/^M-\d{4}$/);
    expect(res.profile.stats.played).toBe(0);
    expect(res.profile.stats.winRate).toBe(0);
  });

  it('4. winRate hesaplamaları: 0 maçta 0; farklı galibiyet oranlarında yuvarlanmış yüzde', async () => {
    const { userProfile } = createDO();
    await userProfile.getProfile('player_stats', 0, false);

    // 0 maç
    let res = await userProfile.getPublicProfile();
    if (res.kind === 'ok') {
      expect(res.profile.stats.winRate).toBe(0);
    }

    // 10 maç: 7 win, 3 loss -> %70
    for (let i = 0; i < 7; i++) {
      await userProfile.applyMatchReward({ matchId: `win_${i}`, outcome: 'win' });
    }
    for (let i = 0; i < 3; i++) {
      await userProfile.applyMatchReward({ matchId: `loss_${i}`, outcome: 'loss' });
    }
    res = await userProfile.getPublicProfile();
    if (res.kind === 'ok') {
      expect(res.profile.stats.played).toBe(10);
      expect(res.profile.stats.won).toBe(7);
      expect(res.profile.stats.lost).toBe(3);
      expect(res.profile.stats.winRate).toBe(70);
    }

    // 1 win daha ekle: 11 maç, 8 win -> 8/11 = 72.72% -> Math.round -> 73
    await userProfile.applyMatchReward({ matchId: 'win_7', outcome: 'win' });
    res = await userProfile.getPublicProfile();
    if (res.kind === 'ok') {
      expect(res.profile.stats.played).toBe(11);
      expect(res.profile.stats.won).toBe(8);
      expect(res.profile.stats.winRate).toBe(73);
    }
  });

  it('5. Silinmiş hesap (tombstone) için kind: "deleted" döner', async () => {
    const { userProfile } = createDO();
    await userProfile.getProfile('deleted_user', 0, false);
    await userProfile.deleteProfile('deleted_user');

    const res = await userProfile.getPublicProfile();
    expect(res).toEqual({ kind: 'deleted' });
  });

  it('6. getBlockInfoForUid ve unblockUserByUid doğru ve idempotent çalışır', async () => {
    const { userProfile } = createDO();
    await userProfile.getProfile('caller_user', 0, false);

    // Başlangıçta engelli değil
    let info = await userProfile.getBlockInfoForUid('target_x');
    expect(info).toEqual({ isBlocked: false, blockId: null });

    // Engelle
    const blockRes = await userProfile.blockUser({
      blockedUid: 'target_x',
      blockedNickname: 'TargetX',
      uid: 'caller_user',
    });
    expect(blockRes.ok).toBe(true);
    if (!blockRes.ok) return;

    info = await userProfile.getBlockInfoForUid('target_x');
    expect(info.isBlocked).toBe(true);
    expect(info.blockId).toBe(blockRes.id);

    // unblockUserByUid ile kaldır
    const unblockRes = await userProfile.unblockUserByUid('target_x');
    expect(unblockRes).toEqual({ ok: true });

    info = await userProfile.getBlockInfoForUid('target_x');
    expect(info).toEqual({ isBlocked: false, blockId: null });

    // Tekrar unblock çağrısı (idempotentlik testi)
    const unblockRes2 = await userProfile.unblockUserByUid('target_x');
    expect(unblockRes2).toEqual({ ok: true });
  });
});
