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
import { ReportStore } from '../src/reportStore';

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
      async getAlarm() {
        return alarmTime;
      },
      async setAlarm(time: number) {
        alarmTime = time;
      },
      async deleteAlarm() {
        alarmTime = null;
      },
      transactionSync: <T>(fn: () => T): T => fn(),
    },
    db,
  } as unknown as DurableObjectState & { db: DatabaseSync };
}

function createEnv(overrides?: Partial<Env>) {
  const profilesMap = new Map<string, UserProfile>();
  let reportStoreInstance: ReportStore | null = null;
  const rsCtx = createMockCtx();

  const userProfileNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}`, name };
    },
    get(id: { toString: () => string; name?: string }) {
      const name = id.name ?? id.toString();
      let inst = profilesMap.get(name);
      if (!inst) {
        inst = new UserProfile(createMockCtx(), fullEnv);
        profilesMap.set(name, inst);
      }
      return inst;
    },
  } as unknown as DurableObjectNamespace<UserProfile>;

  const reportStoreNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}` };
    },
    get() {
      if (!reportStoreInstance) {
        reportStoreInstance = new ReportStore(rsCtx, fullEnv);
      }
      return reportStoreInstance;
    },
  } as unknown as DurableObjectNamespace<ReportStore>;

  const fullEnv: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: userProfileNamespace,
    REPORT_STORE: reportStoreNamespace,
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    MAX_BLOCKS_PER_USER: '100',
    MAX_REPORTS_PER_DAY: '10',
    ...overrides,
  };

  return {
    env: fullEnv,
    profilesMap,
    getOrCreateProfile: (uid: string) =>
      userProfileNamespace.get(userProfileNamespace.idFromName(uid)),
  };
}

describe('API Routes: Public Player Profile (/users/:uid/*)', () => {
  describe('GET /users/:uid/public', () => {
    it('1. Yetkisiz istekte 401 döner', async () => {
      const { env } = createEnv();
      const req = new Request('http://127.0.0.1/users/target_1/public', { method: 'GET' });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(401);
      const data = (await res.json()) as any;
      expect(data.error).toBe('unauthorized');
    });

    it('2. Geçersiz UID formatında 400 döner', async () => {
      const { env } = createEnv();
      const req = new Request('http://127.0.0.1/users/invalid@uid!/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:caller_1' },
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(400);
      const data = (await res.json()) as any;
      expect(data.error).toBe('invalid_uid');
    });

    it('3. Kullanıcı bulunamadığında 404 döner ve yan etki üretmez', async () => {
      const { env } = createEnv();
      const req = new Request('http://127.0.0.1/users/non_existent_uid/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:caller_1' },
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(404);
      const data = (await res.json()) as any;
      expect(data.error).toBe('not_found');
    });

    it('4. Hesap silinmiş (tombstone) ise 410 döner', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const target = getOrCreateProfile('deleted_target');
      await target.getProfile('deleted_target', 0, false);
      await target.deleteProfile('deleted_target');

      const req = new Request('http://127.0.0.1/users/deleted_target/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:caller_1' },
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(410);
      const data = (await res.json()) as any;
      expect(data.error).toBe('deleted');
    });

    it('5. Var olan profilde 200 döner, alanlar beyaz listelidir ve engel durumu yansır', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const target = getOrCreateProfile('target_bob');
      await target.getProfile('target_bob', 0, false);
      await target.setNickname('BobTheBuilder', 'target_bob');
      await target.applyMatchReward({ matchId: 'm1', outcome: 'win', uid: 'target_bob' });

      // Henüz engellenmemiş
      const req1 = new Request('http://127.0.0.1/users/target_bob/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:caller_alice' },
      });
      const res1 = await worker.fetch(req1, env);
      expect(res1.status).toBe(200);
      const data1 = (await res1.json()) as any;

      expect(data1).toEqual({
        uid: 'target_bob',
        nickname: 'BobTheBuilder',
        equippedFrame: 'classic',
        stats: {
          played: 1,
          won: 1,
          lost: 0,
          winRate: 100,
        },
        isBlocked: false,
        blockId: null,
        isGuest: false,
      });

      // Hassas alanların OLMADIĞINI tam anahtar listesiyle assert et
      expect(Object.keys(data1).sort()).toEqual([
        'blockId',
        'equippedFrame',
        'isBlocked',
        'isGuest',
        'nickname',
        'stats',
        'uid',
      ]);
      expect(Object.keys(data1.stats).sort()).toEqual(['lost', 'played', 'winRate', 'won']);
      expect(data1.coins).toBeUndefined();
      expect(data1.email).toBeUndefined();
      expect(data1.energy).toBeUndefined();

      // Alice, Bob'u engeller
      const caller = getOrCreateProfile('caller_alice');
      const blockRes = await caller.blockUser({
        blockedUid: 'target_bob',
        blockedNickname: 'BobTheBuilder',
        uid: 'caller_alice',
      });
      expect(blockRes.ok).toBe(true);

      // Şimdi tekrar sorgula: isBlocked: true ve blockId dolu olmalıdır
      const req2 = new Request('http://127.0.0.1/users/target_bob/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:caller_alice' },
      });
      const res2 = await worker.fetch(req2, env);
      expect(res2.status).toBe(200);
      const data2 = (await res2.json()) as any;
      expect(data2.isBlocked).toBe(true);
      expect(typeof data2.blockId).toBe('string');
      expect(data2.blockId).toBe((blockRes as any).id);
    });

    it('6. Kullanıcı kendi public profilini çağırdığında hata almaz, isBlocked: false döner', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const me = getOrCreateProfile('my_uid');
      await me.getProfile('my_uid', 0, false);
      await me.setNickname('SelfUser', 'my_uid');

      const req = new Request('http://127.0.0.1/users/my_uid/public', {
        method: 'GET',
        headers: { Authorization: 'Bearer dev:my_uid' },
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(200);
      const data = (await res.json()) as any;
      expect(data.uid).toBe('my_uid');
      expect(data.nickname).toBe('SelfUser');
      expect(data.isBlocked).toBe(false);
      expect(data.blockId).toBeNull();
    });
  });

  describe('POST /users/:uid/block & DELETE /users/:uid/block', () => {
    it('1. Kendini engelleme 400 cannot_block_self döner', async () => {
      const { env } = createEnv();
      const req = new Request('http://127.0.0.1/users/myself/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:myself' },
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(400);
      const data = (await res.json()) as any;
      expect(data.error).toBe('cannot_block_self');
    });

    it('2. Var olmayan hedef için 404, silinmiş hedef için 410 döner', async () => {
      const { env, getOrCreateProfile } = createEnv();

      // Var olmayan
      const req404 = new Request('http://127.0.0.1/users/not_found_user/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:caller' },
      });
      const res404 = await worker.fetch(req404, env);
      expect(res404.status).toBe(404);

      // Silinmiş
      const target = getOrCreateProfile('deleted_target_b');
      await target.getProfile('deleted_target_b', 0, false);
      await target.deleteProfile('deleted_target_b');

      const req410 = new Request('http://127.0.0.1/users/deleted_target_b/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:caller' },
      });
      const res410 = await worker.fetch(req410, env);
      expect(res410.status).toBe(410);
      const data410 = (await res410.json()) as any;
      expect(data410.error).toBe('deleted');
    });

    it('3. Başarılı engelleme ve IDEMPOTENCY: tekrar engellendiğinde aynı blockId ile 200 döner', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const target = getOrCreateProfile('target_person');
      await target.getProfile('target_person', 0, false);
      await target.setNickname('NicePlayer', 'target_person');

      // İlk engelleme
      const req1 = new Request('http://127.0.0.1/users/target_person/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:active_caller' },
      });
      const res1 = await worker.fetch(req1, env);
      expect(res1.status).toBe(200);
      const data1 = (await res1.json()) as any;
      expect(data1.ok).toBe(true);
      expect(typeof data1.blockId).toBe('string');

      // İkinci engelleme (idempotent)
      const req2 = new Request('http://127.0.0.1/users/target_person/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:active_caller' },
      });
      const res2 = await worker.fetch(req2, env);
      expect(res2.status).toBe(200);
      const data2 = (await res2.json()) as any;
      expect(data2.ok).toBe(true);
      expect(data2.blockId).toBe(data1.blockId);
    });

    it('4. DELETE /users/:uid/block ile engel kaldırılır ve IDEMPOTENTTİR', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const target = getOrCreateProfile('blocked_target');
      await target.getProfile('blocked_target', 0, false);

      // Engelle
      const blockReq = new Request('http://127.0.0.1/users/blocked_target/block', {
        method: 'POST',
        headers: { Authorization: 'Bearer dev:unblocker' },
      });
      await worker.fetch(blockReq, env);

      // Engeli kaldır
      const delReq1 = new Request('http://127.0.0.1/users/blocked_target/block', {
        method: 'DELETE',
        headers: { Authorization: 'Bearer dev:unblocker' },
      });
      const delRes1 = await worker.fetch(delReq1, env);
      expect(delRes1.status).toBe(200);
      const delData1 = (await delRes1.json()) as any;
      expect(delData1.ok).toBe(true);

      // Zaten engelli değilken tekrar kaldır (idempotent)
      const delReq2 = new Request('http://127.0.0.1/users/blocked_target/block', {
        method: 'DELETE',
        headers: { Authorization: 'Bearer dev:unblocker' },
      });
      const delRes2 = await worker.fetch(delReq2, env);
      expect(delRes2.status).toBe(200);
      const delData2 = (await delRes2.json()) as any;
      expect(delData2.ok).toBe(true);
    });
  });

  describe('POST /users/:uid/report', () => {
    it('1. Geçersiz reason durumunda 400 invalid_reason döner', async () => {
      const { env, getOrCreateProfile } = createEnv();
      const target = getOrCreateProfile('rep_target');
      await target.getProfile('rep_target', 0, false);

      const req = new Request('http://127.0.0.1/users/rep_target/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:reporter_1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'spam' }), // Geçersiz!
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(400);
      const data = (await res.json()) as any;
      expect(data.error).toBe('invalid_reason');
    });

    it('2. Kendini bildirme durumunda 400 cannot_report_self döner', async () => {
      const { env } = createEnv();
      const req = new Request('http://127.0.0.1/users/self_rep/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:self_rep',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'other' }),
      });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(400);
      const data = (await res.json()) as any;
      expect(data.error).toBe('cannot_report_self');
    });

    it('3. Var olmayan hedef için 404, silinmiş için 410 döner', async () => {
      const { env, getOrCreateProfile } = createEnv();

      // Var olmayan
      const req404 = new Request('http://127.0.0.1/users/non_exist/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:rep_user',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'cheating' }),
      });
      const res404 = await worker.fetch(req404, env);
      expect(res404.status).toBe(404);

      // Silinmiş
      const target = getOrCreateProfile('deleted_rep_target');
      await target.getProfile('deleted_rep_target', 0, false);
      await target.deleteProfile('deleted_rep_target');

      const req410 = new Request('http://127.0.0.1/users/deleted_rep_target/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:rep_user',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'cheating' }),
      });
      const res410 = await worker.fetch(req410, env);
      expect(res410.status).toBe(410);
      const data410 = (await res410.json()) as any;
      expect(data410.error).toBe('deleted');
    });

    it('4. Başarılı raporlama ve aynı UID için 409 already_reported, farklı UID için başarı', async () => {
      const { env, getOrCreateProfile } = createEnv();

      const target1 = getOrCreateProfile('toxic_player_1');
      await target1.getProfile('toxic_player_1', 0, false);
      await target1.setNickname('BadName', 'toxic_player_1');

      const target2 = getOrCreateProfile('toxic_player_2');
      await target2.getProfile('toxic_player_2', 0, false);
      await target2.setNickname('CheaterOne', 'toxic_player_2');

      // 1. Hedef için ilk rapor -> 200
      const req1 = new Request('http://127.0.0.1/users/toxic_player_1/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:good_citizen',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'inappropriate_nickname' }),
      });
      const res1 = await worker.fetch(req1, env);
      expect(res1.status).toBe(200);
      const data1 = (await res1.json()) as any;
      expect(data1.ok).toBe(true);

      // Aynı hedef için ikinci rapor -> 409 already_reported
      const req1Repeat = new Request('http://127.0.0.1/users/toxic_player_1/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:good_citizen',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'inappropriate_nickname' }),
      });
      const res1Repeat = await worker.fetch(req1Repeat, env);
      expect(res1Repeat.status).toBe(409);
      const data1Repeat = (await res1Repeat.json()) as any;
      expect(data1Repeat.error).toBe('already_reported');

      // 2. Farklı hedef için rapor -> 200 (çakışma yok)
      const req2 = new Request('http://127.0.0.1/users/toxic_player_2/report', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer dev:good_citizen',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ reason: 'cheating' }),
      });
      const res2 = await worker.fetch(req2, env);
      expect(res2.status).toBe(200);
      const data2 = (await res2.json()) as any;
      expect(data2.ok).toBe(true);
    });
  });
});
