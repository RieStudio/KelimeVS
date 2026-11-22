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
        removeFromQueue: vi.fn().mockResolvedValue(true),
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
        deleteUserData: vi.fn().mockResolvedValue(true),
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
    ENERGY_ENABLED: 'true',
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

  it('6. Başarımlar ve solo maçlar uyumluluğu: deleteProfile sonrası user_achievements, daily_solo_matches, processed_matches ve profile sayaçları silinir; GET /me ve POST /matches/solo 410 döner ve satır dirilmez', async () => {
    const { env } = createEnv();
    const uid = 'del_user_achieve_solo';
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));

    // 1. Profil başlatılır
    await profileStub.getProfile(uid);

    // 2. 1 online ranked galibiyet maçı işlenir -> başarımlar açılır, seriler güncellenir
    await profileStub.applyMatchReward({
      uid,
      matchId: 'online_m_del_1',
      outcome: 'win',
    });

    // 3. 1 solo galibiyet maçı işlenir -> daily_solo_matches, played_solo/won_solo, processed_matches güncellenir
    const soloReq = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        matchId: 'bot:del_compliance_match_1',
        outcome: 'win',
        myScore: 2,
        oppScore: 1,
        correctAnswers: 5,
        durationSeconds: 28,
        endedBy: 'normal',
      }),
    });
    const soloRes = await worker.fetch(soloReq, env);
    expect(soloRes.status).toBe(200);

    // Silme öncesi durumu doğrula:
    expect(getTableCount(profileStub, 'profiles')).toBe(1);
    expect(getTableCount(profileStub, 'user_achievements')).toBeGreaterThanOrEqual(2);
    expect(getTableCount(profileStub, 'daily_solo_matches')).toBe(1);
    expect(getTableCount(profileStub, 'processed_matches')).toBe(2);
    expect(getTableCount(profileStub, 'tombstone')).toBe(0);

    // 4. Hesabı sil (DELETE /me)
    const delReq = new Request('http://127.0.0.1/me', {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer dev:${uid}`,
      },
    });
    const delRes = await worker.fetch(delReq, env);
    expect(delRes.status).toBe(200);
    const delBody = (await delRes.json()) as any;
    expect(delBody.ok).toBe(true);

    // 5. Silme sonrası tüm tablolarda verilerin silindiğini ve tombstone oluştuğunu doğrula
    expect(getTableCount(profileStub, 'tombstone')).toBe(1);
    expect(getTableCount(profileStub, 'profiles')).toBe(0); // current_streak, max_streak, achievements_initialized, played_solo, won_solo profiles satırıyla birlikte otomatik silinir
    expect(getTableCount(profileStub, 'user_achievements')).toBe(0);
    expect(getTableCount(profileStub, 'daily_solo_matches')).toBe(0);
    expect(getTableCount(profileStub, 'processed_matches')).toBe(0); // hem online hem bot:... solo maçları tamamen silindi

    // 6. GET /me -> 410 dönmeli ve hiçbir satır yeniden OLUŞMAMALI
    const getMeReq = new Request('http://127.0.0.1/me', {
      headers: {
        Authorization: `Bearer dev:${uid}`,
      },
    });
    const getMeRes = await worker.fetch(getMeReq, env);
    expect(getMeRes.status).toBe(410);
    const getMeBody = (await getMeRes.json()) as any;
    expect(getMeBody).toEqual({ error: 'account_deleted', message: 'Hesap silinmiş' });

    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'user_achievements')).toBe(0);

    // 7. POST /matches/solo -> 410 dönmeli ve hiçbir satır yeniden OLUŞMAMALI
    const postSoloReq = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        matchId: 'bot:after_del_match',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });
    const postSoloRes = await worker.fetch(postSoloReq, env);
    expect(postSoloRes.status).toBe(410);
    const postSoloBody = (await postSoloRes.json()) as any;
    expect(postSoloBody).toEqual({ ok: false, error: 'account_deleted' });

    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'user_achievements')).toBe(0);
    expect(getTableCount(profileStub, 'daily_solo_matches')).toBe(0);
    expect(getTableCount(profileStub, 'processed_matches')).toBe(0);

    // 8. DO seviyesinde applyBotMatchReward doğrudan çağrılırsa hata fırlatmalı ve satır diriltmemeli
    await expect(
      profileStub.applyBotMatchReward({
        uid,
        matchId: 'bot:direct_do_after_del',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      })
    ).rejects.toThrow();

    expect(getTableCount(profileStub, 'profiles')).toBe(0);
    expect(getTableCount(profileStub, 'user_achievements')).toBe(0);
    expect(getTableCount(profileStub, 'daily_solo_matches')).toBe(0);
    expect(getTableCount(profileStub, 'processed_matches')).toBe(0);
  });
});
