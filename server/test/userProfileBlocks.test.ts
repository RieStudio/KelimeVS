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
  let alarmTime: number | null = null;
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
    storage: {
      sql,
      async getAlarm() {
        return alarmTime;
      },
      async setAlarm(time: number) {
        alarmTime = time;
      },
      async deleteAlarm() {
        alarmTime = null;
      },
    },
  } as unknown as DurableObjectState;
}

describe('UserProfile Blocking Tests', () => {
  const mockEnv = {
    START_COINS: '100',
    MAX_BLOCKS_PER_USER: '3',
  } as unknown as Env;

  it('1. Oyuncu engellendiğinde opak ID döner ve getBlockedUsers içinde gerçek UID sızmaz', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, mockEnv);

    const blockRes = await profile.blockUser({
      blockedUid: 'firebase_secret_uid_123',
      blockedNickname: 'RakipOyuncu',
      uid: 'user_me',
    });

    expect(blockRes.ok).toBe(true);
    if (blockRes.ok) {
      expect(blockRes.id).toBeDefined();
      expect(blockRes.id).not.toBe('firebase_secret_uid_123');

      // İstemciye dönen listede sadece opak id ve takma ad olmalı
      const list = await profile.getBlockedUsers();
      expect(list.length).toBe(1);
      expect(list[0].id).toBe(blockRes.id);
      expect(list[0].nickname).toBe('RakipOyuncu');
      expect((list[0] as any).blockedUid).toBeUndefined();
      expect((list[0] as any).uid).toBeUndefined();
    }
  });

  it('2. getBlockedUids dahili kullanımda gerçek UID dizisini döndürür', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, mockEnv);

    await profile.blockUser({
      blockedUid: 'secret_1',
      blockedNickname: 'User1',
    });
    await profile.blockUser({
      blockedUid: 'secret_2',
      blockedNickname: 'User2',
    });

    const uids = await profile.getBlockedUids();
    expect(uids).toEqual(['secret_1', 'secret_2']);
  });

  it('3. unblockUser opak ID ile engeli kaldırır', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, mockEnv);

    const b = await profile.blockUser({
      blockedUid: 'secret_1',
      blockedNickname: 'User1',
    });
    expect(b.ok).toBe(true);
    if (!b.ok) return;

    const unblockRes = await profile.unblockUser(b.id);
    expect(unblockRes.ok).toBe(true);

    const list = await profile.getBlockedUsers();
    expect(list.length).toBe(0);

    const uids = await profile.getBlockedUids();
    expect(uids.length).toBe(0);
  });

  it('4. Üst sınır (max 3) dolduğunda block_limit_reached hatası verir', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, mockEnv); // Limit 3

    await profile.blockUser({ blockedUid: 'u1', blockedNickname: 'N1' });
    await profile.blockUser({ blockedUid: 'u2', blockedNickname: 'N2' });
    await profile.blockUser({ blockedUid: 'u3', blockedNickname: 'N3' });

    const b4 = await profile.blockUser({ blockedUid: 'u4', blockedNickname: 'N4' });
    expect(b4.ok).toBe(false);
    if (!b4.ok) {
      expect(b4.error).toBe('block_limit_reached');
    }
  });

  it('5. deleteProfile çağrıldığında engel listesi de silinir', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, mockEnv);

    await profile.blockUser({ blockedUid: 'u1', blockedNickname: 'N1' });
    expect((await profile.getBlockedUsers()).length).toBe(1);

    await profile.deleteProfile('user_me');

    expect(profile.isDeleted()).toBe(true);
    // isDeleted varken çağrılar account_deleted hatası atmalı
    await expect(profile.getBlockedUsers()).rejects.toThrow('account_deleted');
  });
});

