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
import {
  generateSeedPlayers,
  validateLocalServerUrl,
  parseCliArgs,
  SEED_FRAMES,
} from '../tools/seed-leaderboard';

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

  return {
    env: fullEnv,
    leaderboardDO: (leaderboardNamespace.get as any)({ toString: () => 'id_global' }) as Leaderboard,
  };
}

describe('seed-leaderboard: Güvenlik, URL Doğrulama ve Oyuncu Üretimi', () => {
  it('1. validateLocalServerUrl: yalnızca 127.0.0.1 ve localhost kabul eder, canlı ve harici sunucuları reddeder', () => {
    // Geçerli yerel URL'ler
    expect(validateLocalServerUrl('http://127.0.0.1:8787')).toBe('http://127.0.0.1:8787');
    expect(validateLocalServerUrl('http://localhost:8787')).toBe('http://localhost:8787');
    expect(validateLocalServerUrl('http://127.0.0.1')).toBe('http://127.0.0.1');

    // Canlı sunucu (api.riestudio.com.tr) KESİNLİKLE reddedilmeli
    expect(() => validateLocalServerUrl('https://api.riestudio.com.tr')).toThrowError(
      /GÜVENLİK ENGELİ/
    );
    expect(() => validateLocalServerUrl('http://api.riestudio.com.tr')).toThrowError(
      /GÜVENLİK ENGELİ/
    );

    // Harici IP veya domainler reddedilmeli
    expect(() => validateLocalServerUrl('http://192.168.1.100:8787')).toThrowError(
      /GÜVENLİK ENGELİ/
    );
    expect(() => validateLocalServerUrl('http://example.com')).toThrowError(
      /GÜVENLİK ENGELİ/
    );

    // Geçersiz protokoller
    expect(() => validateLocalServerUrl('https://localhost:8787')).toThrowError(
      /GÜVENLİK ENGELİ/
    );
    expect(() => validateLocalServerUrl('invalid-url')).toThrowError(
      /Geçersiz URL formatı/
    );
  });

  it('2. generateSeedPlayers: 100 oyuncu, 1-40 galibiyet dağılımı, tüm görsel çerçeveler ve eşitlik senaryoları', () => {
    const nowMs = new Date('2026-10-14T12:00:00Z').getTime();
    const players = generateSeedPlayers(nowMs);

    // Toplam 100 oyuncu
    expect(players).toHaveLength(100);

    // UID ve Takma ad formatı
    expect(players[0].uid).toBe('seed_001');
    expect(players[0].nickname).toBe('Test 001');
    expect(players[99].uid).toBe('seed_100');
    expect(players[99].nickname).toBe('Test 100');

    // Galibiyet aralığı 1 ile 40 arasında
    for (const p of players) {
      expect(p.wins).toBeGreaterThanOrEqual(1);
      expect(p.wins).toBeLessThanOrEqual(40);
      expect(p.losses).toBeGreaterThanOrEqual(0);
      expect(typeof p.reachedAt).toBe('number');
    }

    // 10 çerçevenin (classic + 9 görsel) hepsi eşit olarak yer almalıdır
    const usedFrames = new Set(players.map((p) => p.frame));
    for (const frame of SEED_FRAMES) {
      expect(usedFrames.has(frame)).toBe(true);
      // Her çerçeve tam 10 kez kullanılmalıdır
      const count = players.filter((p) => p.frame === frame).length;
      expect(count).toBe(10);
    }

    // Eşitlik durumları testi:
    // a) Eşit galibiyet (38), farklı mağlubiyet (1 vs 4)
    expect(players[2].wins).toBe(38);
    expect(players[3].wins).toBe(38);
    expect(players[2].losses).toBe(1);
    expect(players[3].losses).toBe(4);

    // b) Eşit galibiyet (37), eşit mağlubiyet (2), farklı süre (15:00 vs 18:00)
    expect(players[4].wins).toBe(37);
    expect(players[5].wins).toBe(37);
    expect(players[4].losses).toBe(2);
    expect(players[5].losses).toBe(2);
    expect(players[4].reachedAt).toBeLessThan(players[5].reachedAt);

    // c) Eşit galibiyet (36), eşit mağlubiyet (3), eşit süre -> uid tie-break (seed_007 vs seed_008)
    expect(players[6].wins).toBe(36);
    expect(players[7].wins).toBe(36);
    expect(players[6].losses).toBe(3);
    expect(players[7].losses).toBe(3);
    expect(players[6].reachedAt).toBe(players[7].reachedAt);
  });
});

describe('Worker API Routes: /admin/leaderboard/seed ve /admin/leaderboard/clear', () => {
  it('1. ALLOW_DEV_AUTH kapalıyken (veya tanımsızken) rotalar 404 Not Found döner', async () => {
    // ALLOW_DEV_AUTH yokken (canlı ortam varsayılanı)
    const { env: prodEnv } = createEnv({ ALLOW_DEV_AUTH: undefined });

    const seedReq = new Request('https://api.riestudio.com.tr/admin/leaderboard/seed', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ entries: [] }),
    });

    const resSeed = await worker.fetch(seedReq, prodEnv);
    expect(resSeed.status).toBe(404);

    const clearReq = new Request('https://api.riestudio.com.tr/admin/leaderboard/clear', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    const resClear = await worker.fetch(clearReq, prodEnv);
    expect(resClear.status).toBe(404);

    // ALLOW_DEV_AUTH === 'false' iken de 404 dönmeli
    const { env: falseEnv } = createEnv({ ALLOW_DEV_AUTH: 'false' });
    const resSeedFalse = await worker.fetch(seedReq, falseEnv);
    expect(resSeedFalse.status).toBe(404);
  });

  it('2. ALLOW_DEV_AUTH=true iken seed ve clear uçtan uca çalışır (wrangler dev custom domain hostname simülasyonu dahil)', async () => {
    const { env } = createEnv({ ALLOW_DEV_AUTH: 'true' });
    const players = generateSeedPlayers();

    // 1) Seed (wrangler dev custom_domain yüzünden gelen api.riestudio.com.tr adresiyle test)
    const seedReq = new Request('https://api.riestudio.com.tr/admin/leaderboard/seed', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ entries: players }),
    });

    const resSeed = await worker.fetch(seedReq, env);
    expect(resSeed.status).toBe(200);
    const bodySeed = (await resSeed.json()) as { success: boolean; inserted: number };
    expect(bodySeed.success).toBe(true);
    expect(bodySeed.inserted).toBe(100);

    // GET /leaderboard ile 100 oyuncunun listelendiğini doğrula
    const getReq = new Request('http://127.0.0.1:8787/leaderboard', {
      method: 'GET',
      headers: {
        Authorization: 'Bearer dev:seed_001',
      },
    });
    const resGet = await worker.fetch(getReq, env);
    expect(resGet.status).toBe(200);
    const bodyGet = (await resGet.json()) as {
      top: Array<{ rank: number; nickname: string; wins: number; frame: string }>;
      me: { rank: number; wins: number };
    };
    expect(bodyGet.top).toHaveLength(100);
    expect(bodyGet.top[0].nickname).toBe('Test 001');
    expect(bodyGet.top[0].wins).toBe(40);
    expect(bodyGet.me).toEqual({ rank: 1, wins: 40 });

    // 2) Clear
    const clearReq = new Request('https://api.riestudio.com.tr/admin/leaderboard/clear', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    const resClear = await worker.fetch(clearReq, env);
    expect(resClear.status).toBe(200);
    const bodyClear = (await resClear.json()) as { success: boolean; deleted: number };
    expect(bodyClear.success).toBe(true);
    expect(bodyClear.deleted).toBe(100);

    // Tekrar GET /leaderboard çağrıldığında liste boş olmalıdır
    const resGetAfter = await worker.fetch(getReq, env);
    const bodyGetAfter = (await resGetAfter.json()) as { top: any[] };
    expect(bodyGetAfter.top).toHaveLength(0);
  });

  it('3. seed rotası yalnızca seed_ önekli uid kabul eder, diğerlerini yoksayar', async () => {
    const { env } = createEnv({ ALLOW_DEV_AUTH: 'true' });

    const mixedEntries = [
      {
        uid: 'seed_valid_1',
        nickname: 'Gecerli Test 1',
        wins: 10,
        losses: 0,
        reachedAt: Date.now(),
        frame: 'classic',
      },
      {
        uid: 'real_user_xyz',
        nickname: 'Gecersiz Gercek',
        wins: 50,
        losses: 0,
        reachedAt: Date.now(),
        frame: 'vine',
      },
      {
        uid: 'seed_valid_2',
        nickname: 'Gecerli Test 2',
        wins: 5,
        losses: 1,
        reachedAt: Date.now(),
        frame: 'sakura',
      },
    ];

    const seedReq = new Request('http://127.0.0.1:8787/admin/leaderboard/seed', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ entries: mixedEntries }),
    });

    const res = await worker.fetch(seedReq, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; inserted: number };
    expect(body.success).toBe(true);
    // Yalnızca 2 adet seed_ kabul edilmiş olmalı
    expect(body.inserted).toBe(2);

    // Tabloyu kontrol et
    const getReq = new Request('http://127.0.0.1:8787/leaderboard', {
      method: 'GET',
      headers: {
        Authorization: 'Bearer dev:seed_valid_1',
      },
    });
    const resGet = await worker.fetch(getReq, env);
    const bodyGet = (await resGet.json()) as {
      top: Array<{ nickname: string }>;
    };
    expect(bodyGet.top).toHaveLength(2);
    expect(bodyGet.top.some((e) => e.nickname === 'Gecersiz Gercek')).toBe(false);
  });

  it('4. parseCliArgs: --count, --me-uid, --me-rank, --clear ve --clear-me parametrelerini doğru ayrıştırır', () => {
    const args1 = parseCliArgs([
      '--count=200',
      '--me-uid=usr_custom_167',
      '--me-rank=167',
      '--server=http://localhost:8787',
    ]);
    expect(args1.count).toBe(200);
    expect(args1.meUid).toBe('usr_custom_167');
    expect(args1.meRank).toBe(167);
    expect(args1.serverUrl).toBe('http://localhost:8787');
    expect(args1.isClear).toBe(false);
    expect(args1.clearMeUid).toBeUndefined();

    const args2 = parseCliArgs(['--clear', '--clear-me=usr_custom_167']);
    expect(args2.isClear).toBe(true);
    expect(args2.clearMeUid).toBe('usr_custom_167');
  });

  it('5. generateSeedPlayers: 200 oyuncu üretimi ve me-uid tam 167. sıraya yerleşimi (deterministik sıra garantisi)', () => {
    const players = generateSeedPlayers({
      count: 200,
      meUid: 'me_rank_167',
      meRank: 167,
    });

    expect(players).toHaveLength(200);

    // 167. eleman (indeks 166) me_rank_167 olmalıdır
    const meSlot = players[166];
    expect(meSlot.uid).toBe('me_rank_167');
    expect(meSlot.nickname).toBe('Sen (Test)');

    // 166. eleman (indeks 165) bir önceki sıradır
    const prevSlot = players[165];
    // 168. eleman (indeks 167) bir sonraki sıradır
    const nextSlot = players[167];

    // Önceki slot meSlot'un kesinlikle önünde olmalıdır:
    // (wins daha yüksek, veya eşitse losses daha az, veya eşitse reachedAt daha erken)
    const prevBeatsMe =
      prevSlot.wins > meSlot.wins ||
      (prevSlot.wins === meSlot.wins && prevSlot.losses < meSlot.losses) ||
      (prevSlot.wins === meSlot.wins &&
        prevSlot.losses === meSlot.losses &&
        prevSlot.reachedAt < meSlot.reachedAt);
    expect(prevBeatsMe).toBe(true);

    // meSlot nextSlot'un kesinlikle önünde olmalıdır:
    const meBeatsNext =
      meSlot.wins > nextSlot.wins ||
      (meSlot.wins === nextSlot.wins && meSlot.losses < nextSlot.losses) ||
      (meSlot.wins === nextSlot.wins &&
        meSlot.losses === nextSlot.losses &&
        meSlot.reachedAt < nextSlot.reachedAt);
    expect(meBeatsNext).toBe(true);
  });

  it('6. "Ben 167.yim" senaryosu: 200 oyuncu tohumlanır, me 167. sırada döner, --clear meUidyi korur, clearMeUid ile silinir', async () => {
    const { env } = createEnv({ ALLOW_DEV_AUTH: 'true' });
    const meUid = 'my_local_dev_user';

    const players = generateSeedPlayers({
      count: 200,
      meUid,
      meRank: 167,
    });

    // 1) 200 oyuncuyu tohumla
    const seedReq = new Request('http://127.0.0.1:8787/admin/leaderboard/seed', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ entries: players, meUid }),
    });

    const resSeed = await worker.fetch(seedReq, env);
    expect(resSeed.status).toBe(200);
    const bodySeed = (await resSeed.json()) as { success: boolean; inserted: number };
    expect(bodySeed.success).toBe(true);
    expect(bodySeed.inserted).toBe(200);

    // 2) GET /leaderboard isteği yap (Authorization: Bearer dev:my_local_dev_user)
    const getReq = new Request('http://127.0.0.1:8787/leaderboard', {
      method: 'GET',
      headers: {
        Authorization: `Bearer dev:${meUid}`,
      },
    });

    const resGet = await worker.fetch(getReq, env);
    expect(resGet.status).toBe(200);
    const bodyGet = (await resGet.json()) as {
      top: Array<{ rank: number; nickname: string; wins: number; frame: string }>;
      me: { rank: number; wins: number };
    };

    // İlk 100 sınırı: top listesi tam 100 eleman içermelidir
    expect(bodyGet.top).toHaveLength(100);
    // 167. sıradaki kullanıcı ilk 100 listesinde YER ALMAZ
    expect(bodyGet.top.some((e) => (e as any).uid === meUid)).toBe(false);

    // Fakat me objesi kullanıcının tam 167. sırada olduğunu doğrulamalıdır!
    expect(bodyGet.me).toBeDefined();
    expect(bodyGet.me.rank).toBe(167);
    const expectedMeSlot = players.find((p) => p.uid === meUid);
    expect(bodyGet.me.wins).toBe(expectedMeSlot!.wins);

    // 3) Standart --clear çalıştırıldığında seed_ ön ekli kayıtlar silinmeli, meUid KORUNMALIDIR!
    const clearSeedReq = new Request('http://127.0.0.1:8787/admin/leaderboard/clear', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    const resClearSeed = await worker.fetch(clearSeedReq, env);
    const bodyClearSeed = (await resClearSeed.json()) as { deleted: number };
    expect(bodyClearSeed.deleted).toBe(199); // 199 seed oyuncusu silindi

    // Liderlik tablosunu tekrar sorgula: top listesinde yalnızca meUid kalmış olmalı (1. sıraya yükselir)
    const resGetAfterSeedClear = await worker.fetch(getReq, env);
    const bodyAfterSeedClear = (await resGetAfterSeedClear.json()) as {
      top: Array<{ rank: number; nickname: string }>;
      me: { rank: number };
    };
    expect(bodyAfterSeedClear.top).toHaveLength(1);
    expect(bodyAfterSeedClear.me.rank).toBe(1);

    // 4) clearMeUid ile meUid de temizlenebilir
    const clearMeReq = new Request('http://127.0.0.1:8787/admin/leaderboard/clear', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clearMeUid: meUid }),
    });
    const resClearMe = await worker.fetch(clearMeReq, env);
    const bodyClearMe = (await resClearMe.json()) as { deleted: number };
    expect(bodyClearMe.deleted).toBe(1);

    // Artık tablo tamamen boştur
    const resGetFinal = await worker.fetch(getReq, env);
    const bodyFinal = (await resGetFinal.json()) as { top: any[]; me: unknown };
    expect(bodyFinal.top).toHaveLength(0);
    expect(bodyFinal.me).toBeNull();
  });
});

