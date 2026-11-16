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
  const webSockets: any[] = [];
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
    acceptWebSocket(ws: any, tags?: string[]) {
      (ws as any).tags = tags ?? [];
      webSockets.push(ws);
    },
    getWebSockets() {
      return webSockets;
    },
    getTags(ws: any) {
      return (ws as any).tags ?? [];
    },
    rawDb: db,
  } as unknown as DurableObjectState & { rawDb: DatabaseSync };
}

function createEnv(overrides?: Partial<Env>) {
  const profilesMap = new Map<string, UserProfile>();
  const ctxMap = new Map<string, any>();

  const userProfileNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}` };
    },
    get(id: { toString: () => string }) {
      const key = id.toString();
      if (!profilesMap.has(key)) {
        const ctx = createMockCtx();
        ctxMap.set(key, ctx);
        profilesMap.set(key, new UserProfile(ctx, fullEnv));
      }
      return profilesMap.get(key)!;
    },
  } as unknown as DurableObjectNamespace<UserProfile>;

  const fullEnv: Env = {
    MATCHMAKER: {
      idFromName: () => ({ toString: () => 'mm' }),
      get: () => ({
        leaveQueue: vi.fn().mockResolvedValue(true),
      }),
    } as any,
    MATCH_ROOM: {
      idFromName: () => ({ toString: () => 'mr' }),
      get: () => ({
        getMatchReportContext: vi.fn().mockResolvedValue({
          ok: true,
          context: {
            reportedUid: 'target_u',
            reportedNickname: 'Target',
          },
        }),
      }),
    } as any,
    REPORT_STORE: {
      idFromName: () => ({ toString: () => 'rs' }),
      get: () => ({
        addReport: vi.fn().mockResolvedValue({ ok: true, reportId: 'rep_1' }),
      }),
    } as any,
    LEADERBOARD: {
      idFromName: () => ({ toString: () => 'lb' }),
      get: () => ({
        deleteUser: vi.fn().mockResolvedValue(true),
        updateNickname: vi.fn().mockResolvedValue(true),
        updateFrame: vi.fn().mockResolvedValue(true),
      }),
    } as any,
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

  return { env: fullEnv, profilesMap, ctxMap };
}

function getTableCount(profile: unknown, table: string): number {
  const sql = (profile as any).ctx.storage.sql;
  const rows = sql.exec(`SELECT COUNT(*) as count FROM ${table}`).toArray();
  return Number(rows[0]?.count ?? 0);
}

describe('Account Deletion & Tombstone Compliance (server/)', () => {
  it('1. PUT /me/settings ve updateSettings: Silinmiş hesap 410 alır, profil satırı YENİDEN OLUŞTURULMAZ', async () => {
    const { env, profilesMap } = createEnv();
    const uid = 'del_user_1';
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));

    // Hesabı oluştur ve başlangıç profil verisini yükle
    await profileStub.getProfile(uid);
    expect(getTableCount(profileStub, 'profiles')).toBe(1);
    expect(getTableCount(profileStub, 'tombstone')).toBe(0);

    // Hesabı sil
    await profileStub.deleteProfile(uid);
    expect(profileStub.isDeleted()).toBe(true);
    expect(getTableCount(profileStub, 'tombstone')).toBe(1);
    expect(getTableCount(profileStub, 'profiles')).toBe(0);

    // PUT /me/settings { allowMatchRequests: false } çağrısı yap
    const putReq1 = new Request('http://127.0.0.1/me/settings', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ allowMatchRequests: false }),
    });

    const res1 = await worker.fetch(putReq1, env);
    expect(res1.status).toBe(410);
    const body1 = (await res1.json()) as any;
    expect(body1).toEqual({ error: 'account_deleted', message: 'Hesap silinmiş' });

    // KESİN KANIT: profiles tablosunda HİÇBİR satır oluşmamalı!
    expect(getTableCount(profileStub, 'profiles')).toBe(0);

    // PUT /me/settings { allowMatchRequests: true } çağrısı yap
    const putReq2 = new Request('http://127.0.0.1/me/settings', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ allowMatchRequests: true }),
    });

    const res2 = await worker.fetch(putReq2, env);
    expect(res2.status).toBe(410);
    const body2 = (await res2.json()) as any;
    expect(body2).toEqual({ error: 'account_deleted', message: 'Hesap silinmiş' });

    // profiles tablosu HALEN 0 olmalı
    expect(getTableCount(profileStub, 'profiles')).toBe(0);

    // DO updateSettings metodunu doğrudan çağırmayı dene -> throw 'account_deleted'
    await expect(
      profileStub.updateSettings({ allowMatchRequests: false, uid })
    ).rejects.toThrow('account_deleted');

    // DO çağrısı sonrası da profil satırı OLUŞMADIĞI kanıtlanır
    expect(getTableCount(profileStub, 'profiles')).toBe(0);
  });

  it('2. /ws/user WebSocket yükseltme yolu: Silinmiş hesap 410 alır, soket açılmaz, presence/profile oluşmaz', async () => {
    const { env } = createEnv();
    const uid = 'del_user_ws';
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
    await profileStub.getProfile(uid);
    await profileStub.deleteProfile(uid);

    // Worker seviyesi /ws/user WebSocket upgrade denemesi
    const wsReq = new Request('http://127.0.0.1/ws/user', {
      headers: {
        Upgrade: 'websocket',
        Authorization: `Bearer dev:${uid}`,
      },
    });

    const wsRes = await worker.fetch(wsReq, env);
    expect(wsRes.status).toBe(410);
    const wsBody = (await wsRes.json()) as any;
    expect(wsBody).toEqual({ error: 'account_deleted', message: 'Hesap silinmiş' });

    // DO seviyesi fetch Upgrade denemesi
    const doReq = new Request('http://127.0.0.1/ws', {
      headers: {
        Upgrade: 'websocket',
        'X-User-Id': uid,
      },
    });
    const doRes = await profileStub.fetch(doReq);
    expect(doRes.status).toBe(410);

    // Ne profiles ne de user_presence tablosunda hiçbir satır oluşmamalı
    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'user_presence')).toBe(0);
  });

  it('3. Kullanıcı yazma yolları (ayar, takma ad, çerçeve, engel, rapor, mağaza, enerji) silinmiş hesapta satır yaratmaz', async () => {
    const { env } = createEnv();
    const uid = 'del_user_writes';
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
    await profileStub.getProfile(uid);
    await profileStub.deleteProfile(uid);

    const authHeader = { Authorization: `Bearer dev:${uid}` };
    const jsonHeaders = {
      ...authHeader,
      'Content-Type': 'application/json',
    };

    // a) PUT /me/nickname
    const nickRes = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: jsonHeaders,
        body: JSON.stringify({ nickname: 'NewName' }),
      }),
      env
    );
    expect(nickRes.status).toBe(410);
    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'nickname_changes')).toBe(0);

    // b) PUT /me/frame
    const frameRes = await worker.fetch(
      new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: jsonHeaders,
        body: JSON.stringify({ frameId: 'classic' }),
      }),
      env
    );
    expect(frameRes.status).toBe(410);
    expect(getTableCount(profileStub, 'profiles')).toBe(0);

    // c) POST /matches/:matchId/block
    const blockMatchRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/m_1/block', {
        method: 'POST',
        headers: jsonHeaders,
      }),
      env
    );
    expect(blockMatchRes.status).toBe(410);
    expect(getTableCount(profileStub, 'blocked_users')).toBe(0);

    // d) POST /users/:uid/block
    const blockUserRes = await worker.fetch(
      new Request('http://127.0.0.1/users/other_u/block', {
        method: 'POST',
        headers: jsonHeaders,
      }),
      env
    );
    expect(blockUserRes.status).toBe(410);
    expect(getTableCount(profileStub, 'blocked_users')).toBe(0);

    // e) DELETE /users/:uid/block
    const unblockUserRes = await worker.fetch(
      new Request('http://127.0.0.1/users/other_u/block', {
        method: 'DELETE',
        headers: jsonHeaders,
      }),
      env
    );
    expect(unblockUserRes.status).toBe(410);
    expect(getTableCount(profileStub, 'blocked_users')).toBe(0);

    // f) DELETE /me/blocks/:id
    const unblockIdRes = await worker.fetch(
      new Request('http://127.0.0.1/me/blocks/b_1', {
        method: 'DELETE',
        headers: jsonHeaders,
      }),
      env
    );
    expect(unblockIdRes.status).toBe(410);
    expect(getTableCount(profileStub, 'blocked_users')).toBe(0);

    // g) POST /matches/:matchId/report
    const repMatchRes = await worker.fetch(
      new Request('http://127.0.0.1/matches/m_1/report', {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ reason: 'cheating' }),
      }),
      env
    );
    expect(repMatchRes.status).toBe(410);

    // h) POST /users/:uid/report
    const repUserRes = await worker.fetch(
      new Request('http://127.0.0.1/users/other_u/report', {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ reason: 'cheating' }),
      }),
      env
    );
    expect(repUserRes.status).toBe(410);

    // i) POST /store/purchase
    const purchaseRes = await worker.fetch(
      new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ itemId: 'gold' }),
      }),
      env
    );
    expect(purchaseRes.status).toBe(410);
    expect(getTableCount(profileStub, 'owned_items')).toBe(0);

    // j) POST /store/energy
    const energyRes = await worker.fetch(
      new Request('http://127.0.0.1/store/energy', {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ pack: 'one' }),
      }),
      env
    );
    expect(energyRes.status).toBe(410);
    expect(getTableCount(profileStub, 'energy_purchases')).toBe(0);

    // k) POST /powerups/spend
    const spendRes = await worker.fetch(
      new Request('http://127.0.0.1/powerups/spend', {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ matchId: 'bot:valid_match_123', powerup: 'extra_time' }),
      }),
      env
    );
    expect(spendRes.status).toBe(410);
    expect(getTableCount(profileStub, 'powerup_purchases')).toBe(0);
  });

  it('4. Maç İsteği sistemi: Silinmiş hesap ne istek gönderebilir ne de istek alabilir, satır yaratılmaz', async () => {
    const { env } = createEnv();
    const deletedUid = 'del_user_match';
    const activeUid = 'active_user';

    const delProfile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(deletedUid));
    const actProfile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(activeUid));

    await delProfile.getProfile(deletedUid);
    await actProfile.getProfile(activeUid);

    await delProfile.deleteProfile(deletedUid);

    // 1. Alıcı silinmişken gelen maç isteği -> account_deleted döner
    const availRes = await delProfile.checkMatchRequestAvailability(activeUid);
    expect(availRes).toEqual({ ok: false, reason: 'account_deleted' });

    const incomingRes = await (delProfile as any).receiveMatchRequest({
      senderUid: activeUid,
      senderNickname: 'Active',
      senderFrame: 'classic',
      type: 'friendly',
      origin: 'profile',
    });
    expect(incomingRes).toEqual({ ok: false, reason: 'account_deleted' });

    // delProfile tablolarında hiçbir istek veya presence satırı oluşmamalı
    expect(getTableCount(delProfile, 'incoming_requests')).toBe(0);
    expect(getTableCount(delProfile, 'outgoing_requests')).toBe(0);
    expect(getTableCount(delProfile, 'match_request_rate_limits')).toBe(0);
    expect(getTableCount(delProfile, 'match_request_cooldowns')).toBe(0);

    // 2. Aktif kullanıcı silinmiş kullanıcıya istek göndermeyi denerse -> offline hatası döner
    const sendCalls: any[] = [];
    const fakeSocket = {
      send: (data: string) => sendCalls.push(JSON.parse(data)),
      close: vi.fn(),
    };
    (actProfile as any).ctx.acceptWebSocket(fakeSocket, [activeUid]);

    await actProfile.handleClientSendMatchRequest(activeUid, 'profile', deletedUid);
    expect(sendCalls).toEqual([
      { t: 'match_request_error', code: 'offline' },
    ]);

    // Silinmiş kullanıcı tarafında kesinlikle satır oluşmadığı doğrulanır
    expect(getTableCount(delProfile, 'incoming_requests')).toBe(0);
    expect(getTableCount(delProfile, 'profiles')).toBe(0);
  });

  it('5. migrateRetiredFrames ve alarm: Silinmiş hesapta hiçbir işlem yapmaz', async () => {
    const { env } = createEnv();
    const uid = 'del_user_misc';
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
    await profileStub.getProfile(uid);
    await profileStub.deleteProfile(uid);

    // migrateRetiredFrames silinmiş hesapta null döner ve DB'ye yazmaz
    const migRes = await profileStub.migrateRetiredFrames(uid, 12);
    expect(migRes).toBeNull();
    expect(getTableCount(profileStub, 'profiles')).toBe(0);

    // alarm çağrısı silinmiş hesapta diğer istekleri veya kayıtları işlemez
    await (profileStub as any).alarm();
    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'tombstone')).toBe(1);
  });
});
