import * as fs from 'node:fs';
import * as path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, expect, it, vi } from 'vitest';

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
import { Leaderboard } from '../src/leaderboard';

function loadStoreContractVectors(): any {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/store_contract.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/store_contract.json'),
    path.resolve(__dirname, '../../shared/test-vectors/store_contract.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8'));
    }
  }
  throw new Error('shared/test-vectors/store_contract.json bulunamadı');
}

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
          'The Durable Object storage SQLite database does not allow manual transactions.'
        );
      }
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('WITH') ||
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
      setAlarm: vi.fn(),
      getAlarm: vi.fn().mockResolvedValue(null),
      deleteAlarm: vi.fn(),
      deleteAll: vi.fn(),
    },
  } as unknown as DurableObjectState;
}

function createEnv(profile: UserProfile, leaderboard: Leaderboard): Env {
  return {
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
    START_COINS: '250',
    WIN_COINS: '30',
    LOSS_COINS: '5',
    ALLOW_DEV_AUTH: 'true',
  };
}

describe('Store HTTP API Contract Tests against shared/test-vectors/store_contract.json', () => {
  const contract = loadStoreContractVectors();

  it('1. GET /store yanıtı sözleşme vektörüyle birebir alan adı ve tipleri açısından uyuşmalıdır', async () => {
    const ctx = createMockCtx();
    const lbCtx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const leaderboard = new Leaderboard(lbCtx, {} as any);
    const env = createEnv(profile, leaderboard);

    const uid = 'contract_user_1';
    // Kullanıcıya gold çerçevesi verelim (vektördeki gold isOwned: true örneğine uyum için)
    await profile.adminGrant({ uid, frameIds: ['gold'], coins: 150 }); // 100 başlangıç + 150 = 250 jeton

    const req = new Request('http://127.0.0.1/store', {
      method: contract.get_store.method,
      headers: {
        Authorization: `Bearer dev:${uid}`,
      },
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(contract.get_store.response_200.status);

    const body = (await res.json()) as any;
    expect(typeof body.coins).toBe('number');
    expect(body.coins).toBe(contract.get_store.response_200.body.coins);
    expect(body.equippedFrame).toBe(contract.get_store.response_200.body.equippedFrame);
    expect(Array.isArray(body.items)).toBe(true);

    // Sözleşmedeki item alan adlarını doğrula: 'cost' kullanılmalı, 'price' OLMAMALI!
    for (const item of body.items) {
      expect(typeof item.id).toBe('string');
      expect(typeof item.name).toBe('string');
      expect(typeof item.cost).toBe('number'); // CRITICAL: 'cost', not 'price'
      expect(typeof item.description).toBe('string');
      expect(typeof item.order).toBe('number');
      expect(typeof item.isOwned).toBe('boolean'); // CRITICAL: 'isOwned', not 'owned'
      expect(typeof item.isEquipped).toBe('boolean');
    }

    // Klasik çerçeve varsayılan olarak sahip ve kuşanılmış olmalıdır
    const classicItem = body.items.find((i: any) => i.id === 'classic');
    expect(classicItem).toBeDefined();
    expect(classicItem.isOwned).toBe(true);
    expect(classicItem.isEquipped).toBe(true);
    expect(classicItem.cost).toBe(0);

    // Gold çerçeve adminGrant ile verildiği için isOwned: true, isEquipped: false olmalıdır
    const goldItem = body.items.find((i: any) => i.id === 'gold');
    expect(goldItem).toBeDefined();
    expect(goldItem.isOwned).toBe(true);
    expect(goldItem.isEquipped).toBe(false);
    expect(goldItem.cost).toBe(300);
  });

  it('1b. GET /store: X-App-Build: 11 başlığı ile 12 öğeli tam sözleşme kataloğu döner', async () => {
    const ctx = createMockCtx();
    const lbCtx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const leaderboard = new Leaderboard(lbCtx, {} as any);
    const env = createEnv(profile, leaderboard);

    const uid = 'contract_user_v2';
    const req = new Request('http://127.0.0.1/store', {
      method: contract.get_store.method,
      headers: {
        Authorization: `Bearer dev:${uid}`,
        'X-App-Build': '11',
      },
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.items.length).toBe(contract.get_store.response_200.body.items.length);

    for (const contractItem of contract.get_store.response_200.body.items) {
      const found = body.items.find((i: any) => i.id === contractItem.id);
      expect(found, `${contractItem.id} öğesi katalogda bulunmalı`).toBeDefined();
      expect(found.name).toBe(contractItem.name);
      expect(found.cost).toBe(contractItem.cost);
      expect(found.kind).toBe(contractItem.kind);
      if (contractItem.tier) {
        expect(found.tier).toBe(contractItem.tier);
      }
    }
  });

  it('2. POST /store/purchase sözleşme vektörü istek ve yanıtlarını tam karşılamalıdır (200, 402, 400)', async () => {
    const ctx = createMockCtx();
    const lbCtx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const leaderboard = new Leaderboard(lbCtx, {} as any);
    const env = createEnv(profile, leaderboard);

    const uid = 'contract_user_buy';
    // 250 jetonla başlasın
    await profile.adminGrant({ uid, coins: 150 });

    // A. 200 Başarılı Satın Alma (Nane: 100 jeton)
    const req200 = new Request('http://127.0.0.1/store/purchase', {
      method: contract.purchase_item.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(contract.purchase_item.request),
    });

    const res200 = await worker.fetch(req200, env);
    expect(res200.status).toBe(contract.purchase_item.response_200.status);
    const body200 = (await res200.json()) as any;
    expect(body200.success).toBe(contract.purchase_item.response_200.body.success);
    expect(body200.itemId).toBe(contract.purchase_item.response_200.body.itemId);
    expect(body200.coins).toBe(contract.purchase_item.response_200.body.coins); // 250 - 100 = 150

    // B. 400 Zaten Sahip Olunan Ürün (Nane tekrar alınamaz)
    const reqAlready = new Request('http://127.0.0.1/store/purchase', {
      method: contract.purchase_item.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(contract.purchase_item.request),
    });
    const resAlready = await worker.fetch(reqAlready, env);
    expect(resAlready.status).toBe(contract.purchase_item.response_400_already_owned.status);
    const bodyAlready = (await resAlready.json()) as any;
    expect(bodyAlready.error).toBe(contract.purchase_item.response_400_already_owned.body.error);

    // C. 402 Yetersiz Bakiye (150 jeton varken 300 jetonluk gold almaya çalışma)
    const reqNoCoins = new Request('http://127.0.0.1/store/purchase', {
      method: contract.purchase_item.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ itemId: 'gold' }),
    });
    const resNoCoins = await worker.fetch(reqNoCoins, env);
    expect(resNoCoins.status).toBe(contract.purchase_item.response_402_not_enough_coins.status);
    const bodyNoCoins = (await resNoCoins.json()) as any;
    expect(bodyNoCoins.error).toBe(contract.purchase_item.response_402_not_enough_coins.body.error);
    expect(typeof bodyNoCoins.coins).toBe('number');

    // D. 400 Geçersiz Ürün
    const reqInvalid = new Request('http://127.0.0.1/store/purchase', {
      method: contract.purchase_item.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ itemId: 'non_existent_item' }),
    });
    const resInvalid = await worker.fetch(reqInvalid, env);
    expect(resInvalid.status).toBe(contract.purchase_item.response_400_invalid_item.status);
    const bodyInvalid = (await resInvalid.json()) as any;
    expect(bodyInvalid.error).toBe(contract.purchase_item.response_400_invalid_item.body.error);

    // E. 400 Yetersiz Build ile Satın Alma (unsupported_client_version)
    const reqUnsupported = new Request('http://127.0.0.1/store/purchase', {
      method: contract.purchase_item.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
        'X-App-Build': '10',
      },
      body: JSON.stringify({ itemId: 'gold_leaf' }),
    });
    const resUnsupported = await worker.fetch(reqUnsupported, env);
    expect(resUnsupported.status).toBe(contract.purchase_item.response_400_unsupported_client_version.status);
    const bodyUnsupported = (await resUnsupported.json()) as any;
    expect(bodyUnsupported.error).toBe(contract.purchase_item.response_400_unsupported_client_version.body.error);
    expect(bodyUnsupported.message).toBe(contract.purchase_item.response_400_unsupported_client_version.body.message);
  });

  it('3. PUT /me/frame sözleşme vektörü istek ve yanıtlarını tam karşılamalıdır (200, 400)', async () => {
    const ctx = createMockCtx();
    const lbCtx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const leaderboard = new Leaderboard(lbCtx, {} as any);
    const env = createEnv(profile, leaderboard);

    const uid = 'contract_user_equip';
    // Nane satın al
    await profile.purchaseItem('mint', uid);

    // A. 400 Sahip olunmayan çerçeve kuşanma
    const reqNotOwned = new Request('http://127.0.0.1/me/frame', {
      method: contract.equip_frame.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ frameId: 'gold' }),
    });
    const resNotOwned = await worker.fetch(reqNotOwned, env);
    expect(resNotOwned.status).toBe(contract.equip_frame.response_400_item_not_owned.status);
    const bodyNotOwned = (await resNotOwned.json()) as any;
    expect(bodyNotOwned.error).toBe(contract.equip_frame.response_400_item_not_owned.body.error);

    // B. 400 Geçersiz çerçeve kimliği
    const reqInvalidFrame = new Request('http://127.0.0.1/me/frame', {
      method: contract.equip_frame.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({ frameId: 'invalid_xyz' }),
    });
    const resInvalidFrame = await worker.fetch(reqInvalidFrame, env);
    expect(resInvalidFrame.status).toBe(contract.equip_frame.response_400_invalid_frame.status);
    const bodyInvalidFrame = (await resInvalidFrame.json()) as any;
    expect(bodyInvalidFrame.error).toBe(contract.equip_frame.response_400_invalid_frame.body.error);

    // C. 200 Başarılı kuşanma (frameId gövdesi ile)
    const reqEquip = new Request('http://127.0.0.1/me/frame', {
      method: contract.equip_frame.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(contract.equip_frame.request),
    });
    const resEquip = await worker.fetch(reqEquip, env);
    expect(resEquip.status).toBe(contract.equip_frame.response_200.status);
    const bodyEquip = (await resEquip.json()) as any;
    expect(bodyEquip.success).toBe(contract.equip_frame.response_200.body.success);
    expect(bodyEquip.equippedFrame).toBe(contract.equip_frame.response_200.body.equippedFrame);

    // D. 200 Başarılı kuşanma (istemcinin gönderdiği çift anahtarlı payload ile)
    const reqClientPayload = new Request('http://127.0.0.1/me/frame', {
      method: contract.equip_frame.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(contract.equip_frame.request_client_payload),
    });
    const resClientPayload = await worker.fetch(reqClientPayload, env);
    expect(resClientPayload.status).toBe(200);
    const bodyClientPayload = (await resClientPayload.json()) as any;
    expect(bodyClientPayload.success).toBe(true);
    expect(bodyClientPayload.equippedFrame).toBe('mint');
  });

  it('4. Genel hata yanıtları sözleşme formatına uymalıdır (401, 410)', async () => {
    const ctx = createMockCtx();
    const lbCtx = createMockCtx();
    const profile = new UserProfile(ctx, {} as any);
    const leaderboard = new Leaderboard(lbCtx, {} as any);
    const env = createEnv(profile, leaderboard);

    // 401 Yetkisiz istek
    const reqNoAuth = new Request('http://127.0.0.1/store', { method: 'GET' });
    const resNoAuth = await worker.fetch(reqNoAuth, env);
    expect(resNoAuth.status).toBe(contract.common_errors.response_401_unauthorized.status);
    const bodyNoAuth = (await resNoAuth.json()) as any;
    expect(bodyNoAuth.error).toBe(contract.common_errors.response_401_unauthorized.body.error);

    // 410 Silinmiş hesap
    const uid = 'deleted_user';
    await profile.deleteProfile(uid);
    const reqDeleted = new Request('http://127.0.0.1/store', {
      method: 'GET',
      headers: { Authorization: `Bearer dev:${uid}` },
    });
    const resDeleted = await worker.fetch(reqDeleted, env);
    expect(resDeleted.status).toBe(contract.common_errors.response_410_account_deleted.status);
    const bodyDeleted = (await resDeleted.json()) as any;
    expect(bodyDeleted.error).toBe(contract.common_errors.response_410_account_deleted.body.error);
  });
});

