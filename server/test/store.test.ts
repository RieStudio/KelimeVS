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
import { Leaderboard } from '../src/leaderboard';
import { FRAME_CATALOG } from '../src/frames';
import worker, { type Env } from '../src/index';

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
      if (trimmed.toUpperCase().startsWith('SELECT') || trimmed.toUpperCase().startsWith('WITH') || trimmed.toUpperCase().startsWith('PRAGMA')) {
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
  } as unknown as DurableObjectState;
}

function createEnv(overrides?: Partial<Env>): Env {
  return {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    LEADERBOARD: {} as any,
    START_COINS: '100',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    ...overrides,
  };
}

describe('Store & Avatar Frames - Server Tests', () => {
  it('1. getStoreState katalog listesi, başlangıç bakiyesi ve varsayılan classic çerçeveyi döner', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    const storeState = await profile.getStoreState('user_1');
    expect(storeState.coins).toBe(100);
    expect(storeState.equippedFrame).toBe('classic');
    // Varsayılan çağrıda (clientBuild = 0) sadece 8 prosedürel çerçeve döner
    expect(storeState.items.length).toBe(8);

    // clientBuild >= 11 verildiğinde 7 aktif çerçeve döner (classic + 6 görsel, 7 emekli hariç)
    const fullStoreState = await profile.getStoreState('user_1', 11);
    expect(fullStoreState.items.length).toBe(7);

    const classic = storeState.items.find((i) => i.id === 'classic');
    expect(classic).toBeDefined();
    expect(classic!.isOwned).toBe(true);
    expect(classic!.isEquipped).toBe(true);
    expect(classic!.cost).toBe(0);

    const mint = storeState.items.find((i) => i.id === 'mint');
    expect(mint).toBeDefined();
    expect(mint!.isOwned).toBe(false);
    expect(mint!.isEquipped).toBe(false);
    expect(mint!.cost).toBe(100);
  });

  it('2. purchaseItem: bakiye yetersizliğinde not_enough_coins döner ve bakiye değişmez', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    // 100 jeton varken 300 jetonluk gold alımı
    const result = await profile.purchaseItem('gold', 'user_1');
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toBe('not_enough_coins');
      expect(result.coins).toBe(100);
    }

    const state = await profile.getStoreState('user_1');
    expect(state.coins).toBe(100);
    expect(state.items.find((i) => i.id === 'gold')!.isOwned).toBe(false);
  });

  it('3. purchaseItem: yeterli bakiyeyle başarılı satın alma, mükerrer alım engeli ve bakiye düşüşü', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    // 100 jeton varken 100 jetonluk mint alımı
    const res1 = await profile.purchaseItem('mint', 'user_1');
    expect(res1.success).toBe(true);
    if (res1.success) {
      expect(res1.itemId).toBe('mint');
      expect(res1.coins).toBe(0);
    }

    // Satın alım sonrası kuşanılmadı durumunda olmalı
    const state = await profile.getStoreState('user_1');
    expect(state.coins).toBe(0);
    const mint = state.items.find((i) => i.id === 'mint');
    expect(mint!.isOwned).toBe(true);
    expect(mint!.isEquipped).toBe(false);

    // Aynı ürün tekrar alınamaz (already_owned)
    const res2 = await profile.purchaseItem('mint', 'user_1');
    expect(res2.success).toBe(false);
    if (!res2.success) {
      expect(res2.error).toBe('already_owned');
    }
  });

  it('4. purchaseItem: geçersiz ürün kimliği invalid_item ve classic için already_owned döner', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    const resInvalid = await profile.purchaseItem('super_dragon', 'user_1');
    expect(resInvalid.success).toBe(false);
    if (!resInvalid.success) {
      expect(resInvalid.error).toBe('invalid_item');
    }

    const resClassic = await profile.purchaseItem('classic', 'user_1');
    expect(resClassic.success).toBe(false);
    if (!resClassic.success) {
      expect(resClassic.error).toBe('already_owned');
    }
  });

  it('5. equipFrame: sahip olunmayan çerçeve engellenir, sahip olunan ve classic kuşanılabilir', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    // Sahip olunmayan gold kuşanma denemesi
    const res1 = await profile.equipFrame('gold', 'user_1');
    expect(res1.success).toBe(false);
    if (!res1.success) {
      expect(res1.error).toBe('item_not_owned');
    }

    // mint satın al
    await profile.purchaseItem('mint', 'user_1');

    // mint kuşan
    const res2 = await profile.equipFrame('mint', 'user_1');
    expect(res2.success).toBe(true);
    if (res2.success) {
      expect(res2.equippedFrame).toBe('mint');
    }

    const state = await profile.getStoreState('user_1');
    expect(state.equippedFrame).toBe('mint');
    expect(state.items.find((i) => i.id === 'mint')!.isEquipped).toBe(true);
    expect(state.items.find((i) => i.id === 'classic')!.isEquipped).toBe(false);

    // Tekrar classic kuşanabilme
    const res3 = await profile.equipFrame('classic', 'user_1');
    expect(res3.success).toBe(true);
    if (res3.success) {
      expect(res3.equippedFrame).toBe('classic');
    }
  });

  it('6. deleteProfile: hesap silindiğinde satın alınan öğeler temizlenir ve store uçları 410 atar', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    await profile.purchaseItem('mint', 'user_1');
    await profile.equipFrame('mint', 'user_1');

    // Hesabı sil
    await profile.deleteProfile('user_1');

    // Tombstone kontrolü
    await expect(profile.getStoreState('user_1')).rejects.toThrow('account_deleted');
    await expect(profile.purchaseItem('ocean', 'user_1')).rejects.toThrow('account_deleted');
    await expect(profile.equipFrame('classic', 'user_1')).rejects.toThrow('account_deleted');
  });

  it('7. Leaderboard week_wins.frame ve updateFrame entegrasyonu', async () => {
    const lbCtx = createMockCtx();
    const env = createEnv();
    const leaderboard = new Leaderboard(lbCtx, env);

    // Maç sonucu kaydet (frame parametreli)
    await leaderboard.recordMatchResult({
      matchId: 'match_100',
      winnerUid: 'user_winner',
      winnerNickname: 'Şampiyon',
      winnerFrame: 'sunset',
      loserUid: 'user_loser',
      loserNickname: 'İkinci',
    });

    const lb1 = await leaderboard.getLeaderboard();
    expect(lb1.top.length).toBe(1);
    expect(lb1.top[0].nickname).toBe('Şampiyon');
    expect(lb1.top[0].frame).toBe('sunset');

    // updateFrame ile çerçeve güncellemesi
    await leaderboard.updateFrame('user_winner', 'gold');

    const lb2 = await leaderboard.getLeaderboard();
    expect(lb2.top[0].frame).toBe('gold');
  });

  it('8. PRAGMA table_info ile şema güvenliği: tekrar tekrar çağrıldığında ALTER hata vermez', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    // getStoreState içindeki ensureSchema çağrılır
    await profile.getStoreState('user_schema_test');

    // İkinci çağrıda initialized=false yapılsa dahi PRAGMA table_info kontrolü ile ALTER tekrar çalıştırılmaz
    (profile as any).initialized = false;
    await expect(profile.getStoreState('user_schema_test')).resolves.toBeDefined();
  });

  it('9. UserProfile.adminGrant atomik, idempotent ve silinmiş hesaplara kapalıdır', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const profile = new UserProfile(ctx, env);

    // İlk durum: 100 jeton
    const res1 = await profile.adminGrant({
      uid: 'user_grant',
      coins: 1000,
      frameIds: ['gold', 'diamond', 'invalid_frame', 'classic'],
    });

    expect(res1.success).toBe(true);
    if (res1.success) {
      expect(res1.coins).toBe(1100); // 100 + 1000
      expect(res1.grantedFrames).toEqual(['gold', 'diamond']); // invalid ve classic filtrelenir
    }

    // İkinci çağrı (idempotent): altın ve elmas tekrar verilir, hata almaz
    const res2 = await profile.adminGrant({
      uid: 'user_grant',
      coins: 0,
      frameIds: ['gold', 'sunset'],
    });
    expect(res2.success).toBe(true);
    if (res2.success) {
      expect(res2.coins).toBe(1100);
      expect(res2.grantedFrames).toEqual(['gold', 'sunset']);
    }

    // Kuşanma kontrolü: artık altın ve elmas kuşanılabilir
    const equipRes = await profile.equipFrame('gold', 'user_grant');
    expect(equipRes.success).toBe(true);

    // Silinmiş hesaba grant uygulanamaz
    await profile.deleteProfile('user_grant');
    const resDeleted = await profile.adminGrant({
      uid: 'user_grant',
      coins: 500,
      frameIds: ['neon'],
    });
    expect(resDeleted.success).toBe(false);
    if (!resDeleted.success) {
      expect(resDeleted.error).toBe('account_deleted');
    }
  });

  it('10. POST /admin/grant API ucu timing-safe yetkilendirme ve parametre kontrolleri', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const env = {
      ...createEnv(),
      ADMIN_TOKEN: 'super-secret-admin-token',
      USER_PROFILE: {
        get: () => profile,
        idFromName: () => ({}) as any,
      } as any,
    };

    // 1. Yetkisiz istek (Token yok) -> 401
    const reqNoAuth = new Request('http://127.0.0.1/admin/grant', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid: 'user_api', coins: 500 }),
    });
    const resNoAuth = await worker.fetch(reqNoAuth, env);
    expect(resNoAuth.status).toBe(401);

    // 2. Yanlış token -> 401
    const reqWrongAuth = new Request('http://127.0.0.1/admin/grant', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer wrong-token',
      },
      body: JSON.stringify({ uid: 'user_api', coins: 500 }),
    });
    const resWrongAuth = await worker.fetch(reqWrongAuth, env);
    expect(resWrongAuth.status).toBe(401);

    // 3. Eksik uid -> 400
    const reqNoUid = new Request('http://127.0.0.1/admin/grant', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer super-secret-admin-token',
      },
      body: JSON.stringify({ coins: 500 }),
    });
    const resNoUid = await worker.fetch(reqNoUid, env);
    expect(resNoUid.status).toBe(400);

    // 4. Başarılı grant -> 200
    const reqSuccess = new Request('http://127.0.0.1/admin/grant', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer super-secret-admin-token',
      },
      body: JSON.stringify({
        uid: 'user_api',
        coins: 1000,
        frameIds: ['gold', 'diamond'],
      }),
    });
    const resSuccess = await worker.fetch(reqSuccess, env);
    expect(resSuccess.status).toBe(200);
    const dataSuccess = (await resSuccess.json()) as any;
    expect(dataSuccess.success).toBe(true);
    expect(dataSuccess.coins).toBe(1100);
    expect(dataSuccess.grantedFrames).toEqual(['gold', 'diamond']);
  });

  it('11. Çerçeve değiştirme: classic -> A kuşan -> B kuşan -> A kuşan -> classic kuşan sıralaması (satın alınan ve adminGrant ile verilen)', async () => {
    const ctx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const lbCtx = createMockCtx();
    const leaderboard = new Leaderboard(lbCtx, {} as any);

    const env = {
      ...createEnv(),
      ALLOW_DEV_AUTH: 'true',
      USER_PROFILE: {
        get: () => profile,
        idFromName: () => ({}) as any,
      } as any,
      LEADERBOARD: {
        get: () => leaderboard,
        idFromName: () => ({}) as any,
      } as any,
    };

    const uid = 'user_equip_cycle';

    // 1. Kullanıcı başlangıçta classic çerçeveye sahiptir
    const initialStore = await profile.getStoreState(uid);
    expect(initialStore.equippedFrame).toBe('classic');

    // 2. A çerçevesini satın al (mint: 100 jeton)
    const buyRes = await profile.purchaseItem('mint', uid);
    expect(buyRes.success).toBe(true);

    // Satın alma sonrası equipped_frame DEĞİŞMEZ (otomatik kuşanma yok)
    const storeAfterBuy = await profile.getStoreState(uid);
    expect(storeAfterBuy.equippedFrame).toBe('classic');
    const profileAfterBuy = await profile.getProfile(uid);
    expect(profileAfterBuy.equippedFrame).toBe('classic');
    const mintItem = storeAfterBuy.items.find((i) => i.id === 'mint');
    expect(mintItem?.isOwned).toBe(true);
    expect(mintItem?.isEquipped).toBe(false);

    // 3. B çerçevesini adminGrant ile ver (gold)
    const grantRes = await profile.adminGrant({
      uid,
      frameIds: ['gold'],
    });
    expect(grantRes.success).toBe(true);

    // Sıralama fonksiyonu: PUT /me/frame çağırır
    async function equipViaHttp(body: Record<string, any>) {
      const req = new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify(body),
      });
      const res = await worker.fetch(req, env);
      const data = (await res.json()) as any;
      return { status: res.status, data };
    }

    // Step A: A kuşan ('mint') - { frameId: 'mint' }
    const step1 = await equipViaHttp({ frameId: 'mint' });
    expect(step1.status).toBe(200);
    expect(step1.data.success).toBe(true);
    expect(step1.data.equippedFrame).toBe('mint');
    expect((await profile.getStoreState(uid)).equippedFrame).toBe('mint');

    // Step B: B kuşan ('gold') - { frameId: 'gold' }
    const step2 = await equipViaHttp({ frameId: 'gold' });
    expect(step2.status).toBe(200);
    expect(step2.data.success).toBe(true);
    expect(step2.data.equippedFrame).toBe('gold');
    expect((await profile.getStoreState(uid)).equippedFrame).toBe('gold');

    // Step C: Tekrar A kuşan ('mint') - { frameId: 'mint' }
    const step3 = await equipViaHttp({ frameId: 'mint' });
    expect(step3.status).toBe(200);
    expect(step3.data.success).toBe(true);
    expect(step3.data.equippedFrame).toBe('mint');
    expect((await profile.getStoreState(uid)).equippedFrame).toBe('mint');

    // Step D: classic kuşan ('classic') - { frameId: 'classic' }
    const step4 = await equipViaHttp({ frameId: 'classic' });
    expect(step4.status).toBe(200);
    expect(step4.data.success).toBe(true);
    expect(step4.data.equippedFrame).toBe('classic');
    expect((await profile.getStoreState(uid)).equippedFrame).toBe('classic');

    // Step E: İstemcinin gönderdiği { frame: '...' } formatında deneme (HATA YENİDEN ÜRETİMİ)
    const stepClientA = await equipViaHttp({ frame: 'mint' });
    // Bu adım sunucuda body.frameId kontrolü yapıldığında 400 bad_request vererek başarısız oluyordu!
    expect(stepClientA.status).toBe(200);
    expect(stepClientA.data.success).toBe(true);
    expect(stepClientA.data.equippedFrame).toBe('mint');

    const stepClientB = await equipViaHttp({ frame: 'gold' });
    expect(stepClientB.status).toBe(200);
    expect(stepClientB.data.success).toBe(true);
    expect(stepClientB.data.equippedFrame).toBe('gold');
  });

  describe('Client Build Filtering & Visual Frames (X-App-Build)', () => {
    function setupServer(overrides?: Partial<Env>) {
      const ctx = createMockCtx();
      const lbCtx = createMockCtx();
      let profile: UserProfile;
      const env: Env = {
        MATCHMAKER: {} as any,
        MATCH_ROOM: {} as any,
        USER_PROFILE: {
          get: () => profile,
          idFromName: () => ({}) as any,
        } as any,
        LEADERBOARD: {
          get: () => leaderboard,
          idFromName: () => ({}) as any,
        } as any,
        START_COINS: '1000',
        WIN_COINS: '30',
        LOSS_COINS: '5',
        ALLOW_DEV_AUTH: 'true',
        ...overrides,
      };
      const leaderboard = new Leaderboard(lbCtx, env);
      profile = new UserProfile(ctx, env);
      return { profile, leaderboard, env };
    }

    it('A. GET /store: başlık yok, 0, 10 ve geçersiz başlıklarda sadece 8 eski çerçeve döner', async () => {
      const { env } = setupServer();
      const testCases = [
        { name: 'başlık yok', header: undefined },
        { name: 'X-App-Build: 0', header: '0' },
        { name: 'X-App-Build: 10', header: '10' },
        { name: 'geçersiz metin (abc)', header: 'abc' },
        { name: 'negatif sayı (-1)', header: '-1' },
        { name: 'boş string ("")', header: '' },
      ];

      for (const tc of testCases) {
        const headers: Record<string, string> = {
          Authorization: 'Bearer dev:user_build_test',
        };
        if (tc.header !== undefined) {
          headers['X-App-Build'] = tc.header;
        }

        const req = new Request('http://127.0.0.1/store', {
          method: 'GET',
          headers,
        });

        const res = await worker.fetch(req, env);
        expect(res.status, `${tc.name} durum kodu 200 olmalı`).toBe(200);
        const data = (await res.json()) as any;
        expect(data.items.length, `${tc.name} durumunda sadece 8 çerçeve dönmeli`).toBe(8);

        // Hiçbir görsel çerçeve bulunmamalı
        const visualItems = data.items.filter((i: any) => i.kind === 'visual');
        expect(visualItems.length, `${tc.name} durumunda görsel çerçeve olmamalı`).toBe(0);

        // 8 prosedürel çerçeve eksiksiz bulunmalı
        const proceduralIds = data.items.map((i: any) => i.id);
        expect(proceduralIds).toEqual([
          'classic',
          'mint',
          'sunset',
          'ocean',
          'gold',
          'neon',
          'rainbow',
          'diamond',
        ]);
      }
    });

    it('B. GET /store: X-App-Build >= 11 olduğunda classic + 6 görsel çerçeve döner (emekliler gizlenir)', async () => {
      const { env } = setupServer();

      for (const build of ['11', '12', '100']) {
        const req = new Request('http://127.0.0.1/store', {
          method: 'GET',
          headers: {
            Authorization: 'Bearer dev:user_build_11',
            'X-App-Build': build,
          },
        });

        const res = await worker.fetch(req, env);
        expect(res.status).toBe(200);
        const data = (await res.json()) as any;
        expect(data.items.length).toBe(7);

        // Yeni görsel çerçeveleri doğrula
        const vine = data.items.find((i: any) => i.id === 'vine');
        expect(vine).toBeDefined();
        expect(vine.name).toBe('Sarmaşık');
        expect(vine.cost).toBe(900);
        expect(vine.kind).toBe('visual');
        expect(vine.tier).toBe('premium');
        expect(vine.order).toBe(12);

        const goldLeaf = data.items.find((i: any) => i.id === 'gold_leaf');
        expect(goldLeaf).toBeDefined();
        expect(goldLeaf.name).toBe('Altın Yaprak');
        expect(goldLeaf.cost).toBe(600);
        expect(goldLeaf.kind).toBe('visual');
        expect(goldLeaf.tier).toBe('medium');
        expect(goldLeaf.order).toBe(11);

        const silver = data.items.find((i: any) => i.id === 'silver_engraved');
        expect(silver).toBeDefined();
        expect(silver.name).toBe('Gümüş Oyma');
        expect(silver.cost).toBe(400);
        expect(silver.kind).toBe('visual');
        expect(silver.tier).toBe('basic');
        expect(silver.order).toBe(10);

        const bronze = data.items.find((i: any) => i.id === 'bronze_engraved');
        expect(bronze).toBeDefined();
        expect(bronze.name).toBe('Bronz Oyma');
        expect(bronze.cost).toBe(250);
        expect(bronze.kind).toBe('visual');
        expect(bronze.tier).toBe('basic');
        expect(bronze.order).toBe(9);

        const emerald = data.items.find((i: any) => i.id === 'emerald');
        expect(emerald).toBeDefined();
        expect(emerald.name).toBe('Zümrüt');
        expect(emerald.cost).toBe(150);
        expect(emerald.kind).toBe('visual');
        expect(emerald.tier).toBe('medium');
        expect(emerald.order).toBe(13);

        const sakura = data.items.find((i: any) => i.id === 'sakura');
        expect(sakura).toBeDefined();
        expect(sakura.name).toBe('Kiraz Çiçeği');
        expect(sakura.cost).toBe(700);
        expect(sakura.kind).toBe('visual');
        expect(sakura.tier).toBe('premium');
        expect(sakura.order).toBe(14);
      }
    });

    it('C. POST /store/purchase: yetersiz build ile yeni çerçeve alımı açık hata (400 unsupported_client_version) ile reddedilir', async () => {
      const { env, profile } = setupServer();
      const uid = 'user_legacy_buyer';
      await profile.adminGrant({ uid, coins: 500 }); // 1000 + 500 = 1500

      // Başlık yokken gold_leaf alma denemesi
      const reqNoHeader = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ itemId: 'gold_leaf' }),
      });

      const resNoHeader = await worker.fetch(reqNoHeader, env);
      expect(resNoHeader.status).toBe(400);
      const dataNoHeader = (await resNoHeader.json()) as any;
      expect(dataNoHeader.error).toBe('unsupported_client_version');
      expect(dataNoHeader.message).toBe('Bu çerçeveyi satın almak için uygulamanızı güncelleyin');

      // Jeton düşmemiş olmalı
      const profAfter1 = await profile.getProfile(uid);
      expect(profAfter1.coins).toBe(1500);

      // Build 10 ile vine alma denemesi
      const reqBuild10 = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '10',
        },
        body: JSON.stringify({ itemId: 'vine' }),
      });

      const resBuild10 = await worker.fetch(reqBuild10, env);
      expect(resBuild10.status).toBe(400);
      const dataBuild10 = (await resBuild10.json()) as any;
      expect(dataBuild10.error).toBe('unsupported_client_version');

      const profAfter2 = await profile.getProfile(uid);
      expect(profAfter2.coins).toBe(1500);
    });

    it('D. POST /store/purchase: yeterli build (>=11) ile yeni çerçeve satın alınır, bakiye düşer ve kuşanılabilir', async () => {
      const { env, profile } = setupServer();
      const uid = 'user_modern_buyer';
      await profile.adminGrant({ uid, coins: 500 }); // 1000 + 500 = 1500

      // 1. bronze_engraved (250 jeton) satın al
      const reqBuy = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
        body: JSON.stringify({ itemId: 'bronze_engraved' }),
      });

      const resBuy = await worker.fetch(reqBuy, env);
      expect(resBuy.status).toBe(200);
      const dataBuy = (await resBuy.json()) as any;
      expect(dataBuy.success).toBe(true);
      expect(dataBuy.itemId).toBe('bronze_engraved');
      expect(dataBuy.coins).toBe(1250); // 1500 - 250 = 1250

      // 2. PUT /me/frame ile kuşan
      const reqEquip = new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ frameId: 'bronze_engraved' }),
      });

      const resEquip = await worker.fetch(reqEquip, env);
      expect(resEquip.status).toBe(200);
      const dataEquip = (await resEquip.json()) as any;
      expect(dataEquip.success).toBe(true);
      expect(dataEquip.equippedFrame).toBe('bronze_engraved');

      // Profilde ve mağazada kuşanılmış görünmeli
      const profileData = await profile.getProfile(uid);
      expect(profileData.equippedFrame).toBe('bronze_engraved');

      const storeData = await profile.getStoreState(uid, 11);
      const bronzeItem = storeData.items.find((i) => i.id === 'bronze_engraved');
      expect(bronzeItem?.isOwned).toBe(true);
      expect(bronzeItem?.isEquipped).toBe(true);
    });

    it('E. Mevcut çerçeveler başlıktan bağımsız her zaman satın alınabilir ve kuşanılabilir', async () => {
      const { env, profile } = setupServer();
      const uid = 'user_legacy_items';
      await profile.adminGrant({ uid, coins: 500 }); // 1000 + 500 = 1500

      // mint (100 jeton) başlıksız satın al
      const reqBuyMint = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ itemId: 'mint' }),
      });

      const resBuyMint = await worker.fetch(reqBuyMint, env);
      expect(resBuyMint.status).toBe(200);
      const dataBuyMint = (await resBuyMint.json()) as any;
      expect(dataBuyMint.success).toBe(true);
      expect(dataBuyMint.itemId).toBe('mint');
      expect(dataBuyMint.coins).toBe(1400); // 1500 - 100 = 1400

      // mint kuşan
      const reqEquipMint = new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
        },
        body: JSON.stringify({ frameId: 'mint' }),
      });
      const resEquipMint = await worker.fetch(reqEquipMint, env);
      expect(resEquipMint.status).toBe(200);
      expect((await profile.getProfile(uid)).equippedFrame).toBe('mint');
    });

    it('F. VISUAL_FRAMES_MIN_BUILD ve RETIRED_FRAMES_BUILD ortam değişkeni ile eşikler değiştirilebilir', async () => {
      const { env } = setupServer({ VISUAL_FRAMES_MIN_BUILD: '15', RETIRED_FRAMES_BUILD: '15' });

      // Build 11 ile sorguladığımızda (eşik 15 olduğu için) 8 prosedürel çerçeve döner
      const req11 = new Request('http://127.0.0.1/store', {
        method: 'GET',
        headers: {
          Authorization: 'Bearer dev:user_env_test',
          'X-App-Build': '11',
        },
      });
      const res11 = await worker.fetch(req11, env);
      const data11 = (await res11.json()) as any;
      expect(data11.items.length).toBe(8);

      // Build 15 ile sorguladığımızda 7 modern çerçeve döner (classic + 6 görsel, emekliler hariç)
      const req15 = new Request('http://127.0.0.1/store', {
        method: 'GET',
        headers: {
          Authorization: 'Bearer dev:user_env_test',
          'X-App-Build': '15',
        },
      });
      const res15 = await worker.fetch(req15, env);
      const data15 = (await res15.json()) as any;
      expect(data15.items.length).toBe(7);
    });
  });

  describe('Emekli Çerçeveler ve İadeli Geçiş (Build >= 11) Testleri', () => {
    function setupServerWithLeaderboard(overrides?: Partial<Env>) {
      const ctx = createMockCtx();
      const lbCtx = createMockCtx();
      let profile: UserProfile;
      const leaderboard = new Leaderboard(lbCtx, {} as any);
      const env: Env = {
        MATCHMAKER: {} as any,
        MATCH_ROOM: {} as any,
        USER_PROFILE: {
          get: () => profile,
          idFromName: () => ({}) as any,
        } as any,
        LEADERBOARD: {
          get: () => leaderboard,
          idFromName: () => ({}) as any,
        } as any,
        START_COINS: '500',
        DAILY_MATCH_COIN_CAP: '300',
        ALLOW_DEV_AUTH: 'true',
        ...overrides,
      };
      profile = new UserProfile(ctx, env);
      return { ctx, lbCtx, env, profile, leaderboard };
    }

    it('1. Mağaza listeleri: Build 0, 10 ve 11 için doğru katalog filtrelemesi yapılır', async () => {
      const { env } = setupServerWithLeaderboard();

      // Build 0: Eski 8 prosedürel çerçeve döner
      const req0 = new Request('http://127.0.0.1/store', {
        headers: { Authorization: 'Bearer dev:u_build_0' },
      });
      const res0 = await worker.fetch(req0, env);
      const data0 = (await res0.json()) as any;
      expect(data0.items.length).toBe(8);
      expect(data0.items.map((i: any) => i.id)).toEqual([
        'classic', 'mint', 'sunset', 'ocean', 'gold', 'neon', 'rainbow', 'diamond'
      ]);

      // Build 10: minClientBuild 11 olanlar gizli, emekliler henüz emekli değil -> 8 çerçeve döner
      const req10 = new Request('http://127.0.0.1/store', {
        headers: { Authorization: 'Bearer dev:u_build_10', 'X-App-Build': '10' },
      });
      const res10 = await worker.fetch(req10, env);
      const data10 = (await res10.json()) as any;
      expect(data10.items.length).toBe(8);

      // Build 11: Emekliler filtrelenir; classic + 6 görsel çerçeve döner (toplam 7)
      const req11 = new Request('http://127.0.0.1/store', {
        headers: { Authorization: 'Bearer dev:u_build_11', 'X-App-Build': '11' },
      });
      const res11 = await worker.fetch(req11, env);
      const data11 = (await res11.json()) as any;
      expect(data11.items.length).toBe(7);
      expect(data11.items.map((i: any) => i.id)).toEqual([
        'classic',
        'bronze_engraved',
        'silver_engraved',
        'gold_leaf',
        'vine',
        'emerald',
        'sakura',
      ]);
    });

    it('2. Emekli çerçeveler build >= 11 istemcide satın alınamaz ve kuşanılamaz (400 item_retired)', async () => {
      const { env, profile } = setupServerWithLeaderboard();
      const uid = 'u_ret_reject';
      await profile.adminGrant({ uid, coins: 1000 });

      // Build 11 ile emekli 'mint' satın alma denemesi
      const reqBuy = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
        body: JSON.stringify({ itemId: 'mint' }),
      });
      const resBuy = await worker.fetch(reqBuy, env);
      expect(resBuy.status).toBe(400);
      const dataBuy = (await resBuy.json()) as any;
      expect(dataBuy.error).toBe('item_retired');
      expect(dataBuy.message).toBe('Bu çerçeve emekliye ayrılmıştır ve artık satın alınamaz');

      // Bakiye düşmemeli
      const prof = await profile.getProfile(uid, 11);
      expect(prof.coins).toBe(1500); // 500 başlangıç + 1000 adminGrant

      // Build 11 ile kuşanma denemesi
      const reqEquip = new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
        body: JSON.stringify({ frameId: 'mint' }),
      });
      const resEquip = await worker.fetch(reqEquip, env);
      expect(resEquip.status).toBe(400);
      const dataEquip = (await resEquip.json()) as any;
      expect(dataEquip.error).toBe('item_retired');
      expect(dataEquip.message).toBe('Bu çerçeve emekliye ayrılmıştır ve kuşanılamaz');
    });

    it('3. Emekli çerçeveler build < 11 istemcide satın alınabilir ve kuşanılabilir', async () => {
      const { env, profile } = setupServerWithLeaderboard();
      const uid = 'u_ret_legacy';
      await profile.adminGrant({ uid, coins: 500 }); // 500 + 500 = 1000

      // Build 10 ile mint (100) satın al
      const reqBuy = new Request('http://127.0.0.1/store/purchase', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '10',
        },
        body: JSON.stringify({ itemId: 'mint' }),
      });
      const resBuy = await worker.fetch(reqBuy, env);
      expect(resBuy.status).toBe(200);
      const dataBuy = (await resBuy.json()) as any;
      expect(dataBuy.success).toBe(true);
      expect(dataBuy.itemId).toBe('mint');
      expect(dataBuy.coins).toBe(900); // 1000 - 100 = 900

      // Build 10 ile kuşan
      const reqEquip = new Request('http://127.0.0.1/me/frame', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '10',
        },
        body: JSON.stringify({ frameId: 'mint' }),
      });
      const resEquip = await worker.fetch(reqEquip, env);
      expect(resEquip.status).toBe(200);
      const dataEquip = (await resEquip.json()) as any;
      expect(dataEquip.success).toBe(true);
      expect(dataEquip.equippedFrame).toBe('mint');
    });

    it('4. İadeli Geçiş: [mint, neon sahip, neon kuşanılmış, bakiye X] -> bakiye X+400, owned_items temiz, equipped classic, haftalık sıralama classic, frameMigration döner', async () => {
      const { env, profile, leaderboard, ctx } = setupServerWithLeaderboard();
      const uid = 'u_migration_test';
      const updateFrameSpy = vi.spyOn(leaderboard, 'updateFrame');

      // Başlangıç: 500 jeton, mint ve neon çerçeveleri verelim
      await profile.adminGrant({ uid, coins: 0, frameIds: ['mint', 'neon'] });
      // neon'u kuşandıralım (build < 11 ile)
      await profile.equipFrame('neon', uid, 10);

      // Doğrulama: geçiş öncesi durum
      const beforeProf = await profile.getProfile(uid, 0);
      expect(beforeProf.coins).toBe(500);
      expect(beforeProf.equippedFrame).toBe('neon');

      // ADIM 1: Build 11 ile GET /me isteği gönderilir
      const reqMe = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resMe = await worker.fetch(reqMe, env);
      expect(resMe.status).toBe(200);
      const dataMe = (await resMe.json()) as any;

      // İade: mint (100) + neon (300) = 400 jeton iade edilir -> 500 + 400 = 900
      expect(dataMe.coins).toBe(900);
      expect(dataMe.equippedFrame).toBe('classic');

      // frameMigration alanı eklenmiş olmalı
      expect(dataMe.frameMigration).toBeDefined();
      expect(dataMe.frameMigration.refundedCoins).toBe(400);
      expect(dataMe.frameMigration.removedFrames).toEqual(['mint', 'neon']);

      // owned_items'ta mint ve neon kalmamalı
      const ownedRows = ctx.storage.sql
        .exec<{ item_id: string }>('SELECT item_id FROM owned_items')
        .toArray();
      expect(ownedRows.map((r) => r.item_id)).toEqual([]);

      // Leaderboard güncellenmiş olmalı
      expect(updateFrameSpy).toHaveBeenCalledWith(uid, 'classic');

      // ADIM 2: İkinci istek (idempotent kontrolü): Tekrar iade yapılmaz, frameMigration dönmez
      const reqMe2 = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resMe2 = await worker.fetch(reqMe2, env);
      expect(resMe2.status).toBe(200);
      const dataMe2 = (await resMe2.json()) as any;
      expect(dataMe2.coins).toBe(900); // 900 sabit, tekrar eklenmedi
      expect(dataMe2.frameMigration).toBeUndefined(); // Sadece ilk geçiş anında döner
    });

    it('5. Build < 11 isteklerinde geçiş çalışmaz', async () => {
      const { env, profile, ctx } = setupServerWithLeaderboard();
      const uid = 'u_no_migration_old';
      await profile.adminGrant({ uid, coins: 0, frameIds: ['mint', 'gold'] });
      await profile.equipFrame('mint', uid, 10);

      // Build 10 ile GET /me
      const reqMe = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '10',
        },
      });
      const resMe = await worker.fetch(reqMe, env);
      const dataMe = (await resMe.json()) as any;

      expect(dataMe.coins).toBe(500); // İade yok
      expect(dataMe.equippedFrame).toBe('mint');
      expect(dataMe.frameMigration).toBeUndefined();

      // owned_items korunmalı
      const ownedRows = ctx.storage.sql
        .exec<{ item_id: string }>('SELECT item_id FROM owned_items')
        .toArray();
      expect(ownedRows.map((r) => r.item_id).sort()).toEqual(['gold', 'mint']);
    });

    it('6. İadeli geçiş günlük kazanç tavanını (DAILY_MATCH_COIN_CAP) etkilemez', async () => {
      const { env, profile, ctx } = setupServerWithLeaderboard();
      const uid = 'u_cap_test';
      await profile.adminGrant({ uid, coins: 0, frameIds: ['diamond'] }); // 800 jetonluk elmas

      // Build 11 ile geçiş tetiklensin: 800 jeton iade edilir
      const reqMe = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resMe = await worker.fetch(reqMe, env);
      const dataMe = (await resMe.json()) as any;
      expect(dataMe.coins).toBe(1300); // 500 + 800

      // daily_coins tablosunu kontrol et: geçiş yüzünden hiçbir günlük kazanç yazılmamış olmalı
      const dailyRows = ctx.storage.sql
        .exec<{ day_key: string; earned: number }>('SELECT day_key, earned FROM daily_coins')
        .toArray();
      expect(dailyRows.length).toBe(0);

      // Kullanıcı ranked maç kazansın (+30 jeton)
      const matchReward = await profile.applyMatchReward({
        matchId: 'm_after_migration',
        outcome: 'win',
        opponentUid: 'opp_1',
        uid,
      });
      expect(matchReward.coinsAwarded).toBe(30);

      // daily_coins tablosunda sadece maç kazancı (30) görünmeli
      const dailyRowsAfter = ctx.storage.sql
        .exec<{ day_key: string; earned: number }>('SELECT day_key, earned FROM daily_coins')
        .toArray();
      expect(dailyRowsAfter.length).toBe(1);
      expect(dailyRowsAfter[0].earned).toBe(30);
    });

    it('7. Emekli çerçeveye sahip olmayan kullanıcıda geçiş çalışmaz, frameMigration dönmez', async () => {
      const { env } = setupServerWithLeaderboard();
      const uid = 'u_clean_user';

      const reqMe = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resMe = await worker.fetch(reqMe, env);
      const dataMe = (await resMe.json()) as any;

      expect(dataMe.coins).toBe(500);
      expect(dataMe.equippedFrame).toBe('classic');
      expect(dataMe.frameMigration).toBeUndefined();
    });

    it('8. Hesap silme akışı (DELETE /me) emekli çerçevelerle de bozulmadan çalışır', async () => {
      const { env, profile } = setupServerWithLeaderboard();
      const uid = 'u_delete_test';
      await profile.adminGrant({ uid, frameIds: ['mint'] });

      const reqDelete = new Request('http://127.0.0.1/me', {
        method: 'DELETE',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resDelete = await worker.fetch(reqDelete, env);
      expect(resDelete.status).toBe(200);

      // Sonraki istekler 410 account_deleted dönmeli
      const reqMe = new Request('http://127.0.0.1/me', {
        method: 'GET',
        headers: {
          Authorization: `Bearer dev:${uid}`,
          'X-App-Build': '11',
        },
      });
      const resMe = await worker.fetch(reqMe, env);
      expect(resMe.status).toBe(410);
    });
  });
});

