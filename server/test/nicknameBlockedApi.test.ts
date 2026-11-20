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
import { sanitizePlayerName } from '../src/protocol';
import { validateNickname } from '../src/engine/nicknameValidator';

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
      get: async () => null,
      put: async () => {},
      delete: async () => false,
      list: async () => new Map(),
    },
    blockConcurrencyWhile: async (fn: any) => fn(),
    waitUntil: () => {},
    id: { toString: () => 'mock_user_id' },
  } as unknown as DurableObjectState;
}

function createTestEnv(): { env: Env; profilesMap: Map<string, UserProfile> } {
  const profilesMap = new Map<string, UserProfile>();
  const env: Env = {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {
      idFromName(name: string) {
        return { toString: () => `id_${name}` };
      },
      get(id: { toString: () => string }) {
        const key = id.toString();
        if (!profilesMap.has(key)) {
          profilesMap.set(key, new UserProfile(createMockCtx(), env));
        }
        return profilesMap.get(key)!;
      },
    } as any,
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    DISCONNECT_WIN_COINS: '30',
    DISCONNECT_LOSS_COINS: '0',
    DAILY_MATCH_COIN_CAP: '300',
  };
  return { env, profilesMap };
}

describe('Nickname Blocked API & Validation Integration', () => {
  it('PUT /me/nickname engellenen uygunsuz bir ad seçilmeye çalışılınca 422 nickname_blocked döner', async () => {
    const { env } = createTestEnv();

    const badSamples = [
      'orospu',
      '0r0spu',
      'o_r_o_s_p_u',
      'sikerim_99',
      's1k1s',
      '51k15',
      'pic123',
      'fucker_man',
    ];

    for (const badNick of badSamples) {
      const req = new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: 'Bearer dev:blocked_test_user',
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: badNick }),
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(422);

      const body = (await res.json()) as any;
      expect(body.error).toBe('nickname_blocked');
      expect(body.message).toBe('Bu takma ad kullanılamaz.');

      // Güvenlik Garantisi: Yanıtta eşleşen kelime veya kök ASLA sızdırılmamalıdır
      expect(JSON.stringify(body)).not.toContain(badNick);
    }
  });

  it('Reddedilen denemeler (422) takma ad değişiklik hakkını/sliding window kotasını TÜKETMEZ', async () => {
    const { env } = createTestEnv();
    const authHeader = 'Bearer dev:quota_test_user';

    // 0. İlk takma ad belirleme (serbest)
    const initReq = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: authHeader,
        'X-App-Build': '15',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'IlkGecerliAd' }),
    });
    const initRes = await worker.fetch(initReq, env);
    expect(initRes.status).toBe(200);

    // 1. Engellenen deneme 1: 422 döner
    const blocked1 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: authHeader,
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'orospu' }),
      }),
      env
    );
    expect(blocked1.status).toBe(422);

    // 2. Geçerli değişiklik 1 (Hak 1 kullanılır): 200 döner
    const valid1 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: authHeader,
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'IkinciGecerli' }),
      }),
      env
    );
    expect(valid1.status).toBe(200);

    // 3. Engellenen deneme 2: 422 döner (kota hâlâ 1 kalmış olmalı)
    const blocked2 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: authHeader,
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 's1k1s_pro' }),
      }),
      env
    );
    expect(blocked2.status).toBe(422);

    // 4. Geçerli değişiklik 2 (Hak 2 kullanılır): 200 döner
    const valid2 = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: authHeader,
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'UcuncuGecerli' }),
      }),
      env
    );
    expect(valid2.status).toBe(200);

    // 5. Geçerli değişiklik 3 (2 hak doldu): 429 Cooldown almalı
    const cooldownRes = await worker.fetch(
      new Request('http://127.0.0.1/me/nickname', {
        method: 'PUT',
        headers: {
          Authorization: authHeader,
          'X-App-Build': '15',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'DorduncuGecerli' }),
      }),
      env
    );
    expect(cooldownRes.status).toBe(429);
    const cdBody = (await cooldownRes.json()) as any;
    expect(cdBody.error).toBe('nickname_cooldown');
  });

  it('Rezerve sistem adları ve misafir kalıbı (M-####) 400 reserved_nickname dönmeye devam eder', async () => {
    const { env } = createTestEnv();

    const reqReserved = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:res_test_user',
        'X-App-Build': '15',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'admin' }),
    });
    const resReserved = await worker.fetch(reqReserved, env);
    expect(resReserved.status).toBe(400);
    const bodyReserved = (await resReserved.json()) as any;
    expect(bodyReserved.error).toBe('reserved_nickname');

    const reqGuestPattern = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:res_test_user',
        'X-App-Build': '15',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'M-4821' }),
    });
    const resGuestPattern = await worker.fetch(reqGuestPattern, env);
    expect(resGuestPattern.status).toBe(400);
    const bodyGuestPattern = (await resGuestPattern.json()) as any;
    expect(bodyGuestPattern.error).toBe('reserved_nickname');
  });

  it('Geçersiz uzunluk veya yasak karakterler 400 invalid_nickname döner', async () => {
    const { env } = createTestEnv();

    const reqTooShort = new Request('http://127.0.0.1/me/nickname', {
      method: 'PUT',
      headers: {
        Authorization: 'Bearer dev:invalid_test_user',
        'X-App-Build': '15',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ nickname: 'ab' }),
    });
    const resTooShort = await worker.fetch(reqTooShort, env);
    expect(resTooShort.status).toBe(400);
    const bodyTooShort = (await resTooShort.json()) as any;
    expect(bodyTooShort.error).toBe('invalid_nickname');
  });

  it('sanitizePlayerName uygunsuz adları filtreden geçirip "Oyuncu"ya dönüştürür', () => {
    expect(sanitizePlayerName('orospu')).toBe('Oyuncu');
    expect(sanitizePlayerName('0r0spu')).toBe('Oyuncu');
    expect(sanitizePlayerName('pic_99')).toBe('Oyuncu');
    expect(sanitizePlayerName('Zeynep_99')).toBe('Zeynep_99');
    expect(sanitizePlayerName('Ahmet')).toBe('Ahmet');
  });

  it('validateNickname uygunsuz takma ad için profanity hatası döner', () => {
    const res = validateNickname('0r0spu');
    expect(res.isValid).toBe(false);
    expect(res.error).toBe('profanity');
    expect(res.errorMessage).toBe('Bu takma ad uygunsuz ifadeler içeriyor.');
  });
});
