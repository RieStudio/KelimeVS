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

function createEnv(overrides?: Partial<Env>) {
  const profilesMap = new Map<string, UserProfile>();
  let reportStoreInstance: ReportStore | null = null;
  const rsCtx = createMockCtx();

  let matchContextMock: any = {
    ok: true,
    context: {
      reporterUid: 'test_user',
      reportedUid: 'opponent_user',
      reportedNickname: 'Rakip123',
      answers: ['cevap1', 'cevap2'],
    },
  };

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

  const reportStoreNamespace = {
    idFromName(name: string) {
      return { toString: () => `id_${name}` };
    },
    get(_id: any) {
      if (!reportStoreInstance) {
        reportStoreInstance = new ReportStore(rsCtx, fullEnv);
      }
      return reportStoreInstance;
    },
  } as unknown as DurableObjectNamespace<ReportStore>;

  const matchRoomNamespace = {
    idFromName(name: string) {
      return { toString: () => name };
    },
    get(_id: any) {
      return {
        getMatchReportContext: async (_callerUid: string) => matchContextMock,
      };
    },
  } as unknown as DurableObjectNamespace<any>;

  const fullEnv: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: matchRoomNamespace,
    USER_PROFILE: userProfileNamespace,
    REPORT_STORE: reportStoreNamespace,
    ADMIN_TOKEN: 'super-secret-admin-token',
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    MAX_REPORTS_PER_DAY: '5',
    MAX_BLOCKS_PER_USER: '5',
    ...overrides,
  };

  return {
    env: fullEnv,
    setMatchContext: (ctx: any) => {
      matchContextMock = ctx;
    },
  };
}

describe('API Routes: Reports & Blocks Endpoints', () => {
  it('1. POST /matches/:matchId/report yetkisiz istekte 401 döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: 'cheating' }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(401);
  });

  it('2. POST /matches/:matchId/report geçersiz sebebe 400 döner', async () => {
    const { env } = createEnv();
    const req = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:test_user',
      },
      body: JSON.stringify({ reason: 'invalid_reason_string' }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(400);
    const body = (await res.json()) as any;
    expect(body.error).toBe('invalid_reason');
  });

  it('3. POST /matches/:matchId/report maç 10 dk sonra silinmişse 410 match_expired döner', async () => {
    const { env, setMatchContext } = createEnv();
    setMatchContext(null); // MatchRoom clean up olmuş

    const req = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:test_user',
      },
      body: JSON.stringify({ reason: 'cheating' }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(410);
    const body = (await res.json()) as any;
    expect(body.error).toBe('match_expired');
  });

  it('4. POST /matches/:matchId/report başarılı bildirimde 200 döner, tekrarında 409 döner', async () => {
    const { env } = createEnv();
    const req1 = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:test_user',
      },
      body: JSON.stringify({ reason: 'inappropriate_nickname' }),
    });

    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);

    // Aynı maçı tekrar bildirme
    const req2 = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:test_user',
      },
      body: JSON.stringify({ reason: 'inappropriate_content' }),
    });

    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(409);
    const body2 = (await res2.json()) as any;
    expect(body2.error).toBe('already_reported');
  });

  it('5. POST /matches/:matchId/block rakibi engeller, GET /me/blocks listesinde opak ID ile görünür', async () => {
    const { env } = createEnv();
    const blockReq = new Request('http://127.0.0.1/matches/m1/block', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer dev:test_user',
      },
    });

    const blockRes = await worker.fetch(blockReq, env);
    expect(blockRes.status).toBe(200);
    const blockBody = (await blockRes.json()) as any;
    expect(blockBody.ok).toBe(true);
    expect(blockBody.id).toBeDefined();

    // GET /me/blocks
    const listReq = new Request('http://127.0.0.1/me/blocks', {
      method: 'GET',
      headers: {
        Authorization: 'Bearer dev:test_user',
      },
    });

    const listRes = await worker.fetch(listReq, env);
    expect(listRes.status).toBe(200);
    const list = (await listRes.json()) as any[];
    expect(list.length).toBe(1);
    expect(list[0].id).toBe(blockBody.id);
    expect(list[0].nickname).toBe('Rakip123');

    // DELETE /me/blocks/:id
    const delReq = new Request(`http://127.0.0.1/me/blocks/${blockBody.id}`, {
      method: 'DELETE',
      headers: {
        Authorization: 'Bearer dev:test_user',
      },
    });

    const delRes = await worker.fetch(delReq, env);
    expect(delRes.status).toBe(200);

    // Liste boş olmalı
    const listRes2 = await worker.fetch(listReq, env);
    expect((await listRes2.json()) as any[]).toEqual([]);
  });

  it('6. Silinmiş hesap (tombstone) yeni uçlarda 410 account_deleted alır', async () => {
    const { env } = createEnv();
    const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName('deleted_user'));
    await profileStub.deleteProfile('deleted_user');

    // Rapor rotası
    const req1 = new Request('http://127.0.0.1/matches/m1/report', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer dev:deleted_user',
      },
      body: JSON.stringify({ reason: 'cheating' }),
    });
    expect((await worker.fetch(req1, env)).status).toBe(410);

    // Blok rotası
    const req2 = new Request('http://127.0.0.1/matches/m1/block', {
      method: 'POST',
      headers: { Authorization: 'Bearer dev:deleted_user' },
    });
    expect((await worker.fetch(req2, env)).status).toBe(410);

    // Engellenenler listesi
    const req3 = new Request('http://127.0.0.1/me/blocks', {
      method: 'GET',
      headers: { Authorization: 'Bearer dev:deleted_user' },
    });
    expect((await worker.fetch(req3, env)).status).toBe(410);
  });

  it('7. GET /admin/reports token olmadan 401, token ile 200 döner', async () => {
    const { env } = createEnv();

    // Tokensız
    const reqNoToken = new Request('http://127.0.0.1/admin/reports', { method: 'GET' });
    expect((await worker.fetch(reqNoToken, env)).status).toBe(401);

    // Yanlış token
    const reqWrong = new Request('http://127.0.0.1/admin/reports', {
      method: 'GET',
      headers: { Authorization: 'Bearer wrong-token' },
    });
    expect((await worker.fetch(reqWrong, env)).status).toBe(401);

    // Doğru token
    const reqAdmin = new Request('http://127.0.0.1/admin/reports', {
      method: 'GET',
      headers: { Authorization: 'Bearer super-secret-admin-token' },
    });
    const res = await worker.fetch(reqAdmin, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.reports).toBeDefined();

    // Summary view
    const reqSummary = new Request('http://127.0.0.1/admin/reports?view=summary', {
      method: 'GET',
      headers: { Authorization: 'Bearer super-secret-admin-token' },
    });
    const resSummary = await worker.fetch(reqSummary, env);
    expect(resSummary.status).toBe(200);
    const bodySummary = (await resSummary.json()) as any;
    expect(bodySummary.summary).toBeDefined();
  });
});

