import { describe, expect, it } from 'vitest';
import {
  authenticateRequest,
  createKeyCache,
  verifyToken,
  type AuthEnv,
  type FetchFunction,
  type JwkKey,
} from '../src/auth';

function uint8ArrayToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function utf8ToBase64Url(str: string): string {
  const bytes = new TextEncoder().encode(str);
  return uint8ArrayToBase64Url(bytes);
}

async function generateTestKeyPair(kid = 'key-1') {
  const keyPair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify']
  )) as CryptoKeyPair;

  const exported = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JwkKey;
  const jwk: JwkKey = {
    ...exported,
    kid,
    alg: 'RS256',
    use: 'sig',
  };

  return { keyPair, jwk };
}

async function signJwt(header: object, payload: object, privateKey: CryptoKey): Promise<string> {
  const headerB64 = utf8ToBase64Url(JSON.stringify(header));
  const payloadB64 = utf8ToBase64Url(JSON.stringify(payload));
  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const sigBytes = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, data);
  const sigB64 = uint8ArrayToBase64Url(new Uint8Array(sigBytes));
  return `${headerB64}.${payloadB64}.${sigB64}`;
}

async function signHmacJwt(header: object, payload: object, secret: string): Promise<string> {
  const headerB64 = utf8ToBase64Url(JSON.stringify(header));
  const payloadB64 = utf8ToBase64Url(JSON.stringify(payload));
  const hmacKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const sigBytes = await crypto.subtle.sign('HMAC', hmacKey, data);
  const sigB64 = uint8ArrayToBase64Url(new Uint8Array(sigBytes));
  return `${headerB64}.${payloadB64}.${sigB64}`;
}

describe('Firebase ID Token & Dev Auth (Adım 4.3b)', () => {
  const TEST_PROJECT_ID = 'kelimego-prod';
  const validEnv: AuthEnv = {
    FIREBASE_PROJECT_ID: TEST_PROJECT_ID,
  };

  const nowMs = 1728518400000; // Sabit zaman referansı
  const nowSec = Math.floor(nowMs / 1000);

  function createValidPayload(overrides: Record<string, unknown> = {}) {
    return {
      aud: TEST_PROJECT_ID,
      iss: `https://securetoken.google.com/${TEST_PROJECT_ID}`,
      sub: 'user_firebase_123',
      iat: nowSec - 100,
      auth_time: nowSec - 100,
      exp: nowSec + 3600,
      ...overrides,
    };
  }

  function createMockFetch(initialKeys: JwkKey[], maxAge = 3600) {
    let currentKeys = [...initialKeys];
    let fetchCount = 0;

    const fetchFn: FetchFunction = async () => {
      fetchCount++;
      return new Response(JSON.stringify({ keys: currentKeys }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${maxAge}, must-revalidate`,
        },
      });
    };

    return {
      fetchFn,
      getFetchCount: () => fetchCount,
      setKeys: (newKeys: JwkKey[]) => {
        currentKeys = newKeys;
      },
    };
  }

  // --------------------------------------------------------------------------
  // 1. Temel Başarılı Doğrulama
  // --------------------------------------------------------------------------
  it('geçerli RS256 Firebase ID token başarıyla doğrulanır ve uid döner', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBe('user_firebase_123');
    expect(mock.getFetchCount()).toBe(1);
  });

  // --------------------------------------------------------------------------
  // 2. Süre Kontrolleri (exp, iat, auth_time ve 60 sn tolerans)
  // --------------------------------------------------------------------------
  it('süresi 60 saniyeden fazla geçmiş (expired) token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ exp: nowSec - 70 }), // 70 sn önce dolmuş (> 60 sn tolerans)
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('süresi 30 saniye önce dolmuş token 60 sn saat sapması toleransı sayesinde kabul edilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ exp: nowSec - 30 }), // 30 sn önce dolmuş (<= 60 sn tolerans)
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBe('user_firebase_123');
  });

  it('iat gelecekte (> 60 sn) olan token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ iat: nowSec + 70 }), // 70 sn gelecekte
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('auth_time gelecekte (> 60 sn) olan token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ auth_time: nowSec + 80 }),
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  // --------------------------------------------------------------------------
  // 3. Talep Kontrolleri (aud, iss, sub)
  // --------------------------------------------------------------------------
  it('yanlış aud içeren token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ aud: 'baska-bir-proje' }),
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('yanlış iss içeren token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ iss: 'https://hacker.com/evil' }),
      keyPair.privateKey
    );

    const uid = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('sub eksik, boş veya 128 karakterden uzun ise reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    // sub eksik
    const tokenNoSub = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ sub: undefined }),
      keyPair.privateKey
    );
    expect(
      await verifyToken(tokenNoSub, validEnv, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBeNull();

    // sub boş
    const tokenEmptySub = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ sub: '' }),
      keyPair.privateKey
    );
    expect(
      await verifyToken(tokenEmptySub, validEnv, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBeNull();

    // sub > 128 karakter
    const tokenLongSub = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ sub: 'a'.repeat(129) }),
      keyPair.privateKey
    );
    expect(
      await verifyToken(tokenLongSub, validEnv, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBeNull();
  });

  // --------------------------------------------------------------------------
  // 4. İmza Bozulması ve Güvenlik Saldırıları (alg: none, HS256)
  // --------------------------------------------------------------------------
  it('imzası bozuk olan token reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    // İmzayı tahrif et (son karakteri değiştir)
    const corruptToken = token.slice(0, -2) + 'XX';

    const uid = await verifyToken(corruptToken, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('alg: "none" saldırısı kesinlikle reddedilir', async () => {
    const headerB64 = utf8ToBase64Url(JSON.stringify({ alg: 'none', kid: 'key-1' }));
    const payloadB64 = utf8ToBase64Url(JSON.stringify(createValidPayload()));
    const tokenNone = `${headerB64}.${payloadB64}.`;

    const uid = await verifyToken(tokenNone, validEnv, { nowMs });
    expect(uid).toBeNull();
  });

  it('alg: "HS256" anahtar karışıklığı saldırısı (key confusion attack) kesinlikle reddedilir', async () => {
    const { jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    // Saldırgan genel anahtarı HMAC sırrı olarak kullanarak imzalar
    const tokenHs256 = await signHmacJwt(
      { alg: 'HS256', kid: 'key-1' },
      createValidPayload(),
      jwk.n
    );

    const uid = await verifyToken(tokenHs256, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('başlıkta kid eksikse reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const tokenNoKid = await signJwt(
      { alg: 'RS256' }, // kid yok
      createValidPayload(),
      keyPair.privateKey
    );

    const uid = await verifyToken(tokenNoKid, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });

    expect(uid).toBeNull();
  });

  it('bozuk biçimli token (3 parçalı olmayan, geçersiz base64, bozuk JSON) reddedilir', async () => {
    expect(await verifyToken('tek_parca', validEnv)).toBeNull();
    expect(await verifyToken('iki.parca', validEnv)).toBeNull();
    expect(await verifyToken('dort.parca.cok.fazla', validEnv)).toBeNull();
    expect(await verifyToken('gecersiz_b64.gecersiz_b64.gecersiz_b64', validEnv)).toBeNull();
    expect(
      await verifyToken(
        `${utf8ToBase64Url('{bozuk_json')}.${utf8ToBase64Url('{bozuk_json')}.sig`,
        validEnv
      )
    ).toBeNull();
  });

  // --------------------------------------------------------------------------
  // 5. Anahtar Önbellekleme, Bilinmeyen kid ve Hız Sınırı (Rate Limit)
  // --------------------------------------------------------------------------
  it('ikinci doğrulamada aynı kid için ağ çağrısı yapılmaz (önbellek çalışır)', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    const uid1 = await verifyToken(token, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });
    expect(uid1).toBe('user_firebase_123');
    expect(mock.getFetchCount()).toBe(1);

    // İkinci doğrulama
    const uid2 = await verifyToken(token, validEnv, {
      nowMs: nowMs + 1000,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });
    expect(uid2).toBe('user_firebase_123');
    expect(mock.getFetchCount()).toBe(1); // Ağ çağrısı artmadı
  });

  it('yeni bir kid geldiğinde anahtarlar yeniden çekilir (anahtar rotasyonu)', async () => {
    const { keyPair: kp1, jwk: jwk1 } = await generateTestKeyPair('key-1');
    const { keyPair: kp2, jwk: jwk2 } = await generateTestKeyPair('key-2');

    const mock = createMockFetch([jwk1]);
    const cache = createKeyCache();

    // 1. Token (key-1)
    const token1 = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload({ sub: 'user_1' }),
      kp1.privateKey
    );
    expect(
      await verifyToken(token1, validEnv, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBe('user_1');
    expect(mock.getFetchCount()).toBe(1);

    // Google anahtarları güncellenir (key-2 eklenir)
    mock.setKeys([jwk1, jwk2]);

    // 61 saniye sonra key-2 ile yeni token gelir
    const token2 = await signJwt(
      { alg: 'RS256', kid: 'key-2' },
      createValidPayload({ sub: 'user_2' }),
      kp2.privateKey
    );
    expect(
      await verifyToken(token2, validEnv, {
        nowMs: nowMs + 65_000,
        keyCache: cache,
        fetchFn: mock.fetchFn,
      })
    ).toBe('user_2');
    expect(mock.getFetchCount()).toBe(2); // Yeniden çekildi
  });

  it('bilinmeyen kid ile sürekli istek atıldığında dakikada en fazla 1 kez ağ çağrısı yapılır (rate limit)', async () => {
    const { keyPair: kp1, jwk: jwk1 } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk1]);
    const cache = createKeyCache();

    // 1. Bilinmeyen kid -> fetch yapılır
    const tokenUnknown1 = await signJwt(
      { alg: 'RS256', kid: 'fake-kid-1' },
      createValidPayload(),
      kp1.privateKey
    );
    expect(
      await verifyToken(tokenUnknown1, validEnv, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBeNull();
    expect(mock.getFetchCount()).toBe(1);

    // 10 saniye sonra başka bir sahte kid -> 60 saniye dolmadığı için fetch yapılmaz!
    const tokenUnknown2 = await signJwt(
      { alg: 'RS256', kid: 'fake-kid-2' },
      createValidPayload(),
      kp1.privateKey
    );
    expect(
      await verifyToken(tokenUnknown2, validEnv, {
        nowMs: nowMs + 10_000,
        keyCache: cache,
        fetchFn: mock.fetchFn,
      })
    ).toBeNull();
    expect(mock.getFetchCount()).toBe(1); // Ağ çağrısı yapılmadı, koruma devrede!
  });

  // --------------------------------------------------------------------------
  // 6. Geliştirme Modu ve FIREBASE_PROJECT_ID Yapılandırması
  // --------------------------------------------------------------------------
  it('ALLOW_DEV_AUTH true iken dev:<uid> kabul edilir, false iken veya yokken reddedilir', async () => {
    expect(await verifyToken('dev:alice', { ALLOW_DEV_AUTH: 'true' })).toBe('alice');
    expect(await verifyToken('dev:alice', { ALLOW_DEV_AUTH: 'false' })).toBeNull();
    expect(await verifyToken('dev:alice', {})).toBeNull();
  });

  it('FIREBASE_PROJECT_ID eksikse veya yer tutucu ise Firebase doğrulaması reddedilir', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    // Eksik
    expect(
      await verifyToken(token, {}, { nowMs, keyCache: cache, fetchFn: mock.fetchFn })
    ).toBeNull();

    // Yer tutucu (REPLACE_WITH_FIREBASE_PROJECT_ID)
    expect(
      await verifyToken(
        token,
        { FIREBASE_PROJECT_ID: 'REPLACE_WITH_FIREBASE_PROJECT_ID' },
        { nowMs, keyCache: cache, fetchFn: mock.fetchFn }
      )
    ).toBeNull();
  });

  // --------------------------------------------------------------------------
  // 7. İstemci İstek Kimlik Doğrulaması (authenticateRequest)
  // --------------------------------------------------------------------------
  it('authenticateRequest: Authorization: Bearer başlığıyla gelen geçerli token doğrulanır', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    const req = new Request('http://localhost/ws/matchmaking', {
      headers: { Authorization: `Bearer ${token}` },
    });

    const uid = await authenticateRequest(req, validEnv, {
      nowMs,
      keyCache: cache,
      fetchFn: mock.fetchFn,
    });
    expect(uid).toBe('user_firebase_123');
  });

  it('authenticateRequest: Üretim modunda (?token=) sorgu parametresi KESİNLİKLE reddedilir', async () => {
    // Üretim modu: ALLOW_DEV_AUTH tanımsız
    const req = new Request('http://localhost/ws/matchmaking?token=dev:alice');
    const uid = await authenticateRequest(req, { FIREBASE_PROJECT_ID: TEST_PROJECT_ID });
    expect(uid).toBeNull();
  });

  it('authenticateRequest: Geliştirme modunda (?token=dev:<uid>) kabul edilir', async () => {
    const req = new Request('http://localhost/ws/matchmaking?token=dev:alice');
    const uid = await authenticateRequest(req, {
      ALLOW_DEV_AUTH: 'true',
      FIREBASE_PROJECT_ID: TEST_PROJECT_ID,
    });
    expect(uid).toBe('alice');
  });

  it('authenticateRequest: Geliştirme modunda bile Firebase token sorgu parametresiyle (?token=) gönderilemez', async () => {
    const { keyPair, jwk } = await generateTestKeyPair('key-1');
    const mock = createMockFetch([jwk]);
    const cache = createKeyCache();

    const token = await signJwt(
      { alg: 'RS256', kid: 'key-1' },
      createValidPayload(),
      keyPair.privateKey
    );

    // Geliştirme modunda olsa bile sorgu parametresinde Firebase token'ı geçersizdir
    const req = new Request(`http://localhost/ws/matchmaking?token=${token}`);
    const uid = await authenticateRequest(
      req,
      { ALLOW_DEV_AUTH: 'true', FIREBASE_PROJECT_ID: TEST_PROJECT_ID },
      { nowMs, keyCache: cache, fetchFn: mock.fetchFn }
    );
    expect(uid).toBeNull();
  });
});
