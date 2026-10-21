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
    expect(storeState.items.length).toBe(FRAME_CATALOG.length);

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
});

