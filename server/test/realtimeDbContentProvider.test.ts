import { describe, expect, it } from 'vitest';
import {
  parseQuestionsPoolWithStats,
  RealtimeDbContentProvider,
  ServiceAccountTokenProvider,
  type FetchFunction,
  type JwkKey,
} from '../src/content';

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function generateTestServiceAccount() {
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

  const pkcs8Der = await crypto.subtle.exportKey('pkcs8', keyPair.privateKey);
  const pkcs8B64 = uint8ArrayToBase64(new Uint8Array(pkcs8Der));
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8B64}\n-----END PRIVATE KEY-----`;

  const serviceAccountJson = {
    client_email: 'test-sa@project.iam.gserviceaccount.com',
    private_key: pem,
  };

  const serviceAccountB64 = btoa(JSON.stringify(serviceAccountJson));
  return { keyPair, serviceAccountJson, serviceAccountB64 };
}

function base64UrlToUint8Array(str: string): Uint8Array {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4 !== 0) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

describe('ServiceAccountTokenProvider (OAuth2 JWT Bearer Flow)', () => {
  it('JWT assertion doğru claims ile üretilir ve RSA anahtarıyla imzası doğrulanır', async () => {
    const { keyPair, serviceAccountB64 } = await generateTestServiceAccount();
    const tokenProvider = new ServiceAccountTokenProvider(serviceAccountB64);

    const nowSec = 1728518400;
    const assertionJwt = await tokenProvider.createAssertionJwt(nowSec);

    const parts = assertionJwt.split('.');
    expect(parts.length).toBe(3);

    const [headerB64, payloadB64, sigB64] = parts;
    const header = JSON.parse(new TextDecoder().decode(base64UrlToUint8Array(headerB64)));
    const payload = JSON.parse(new TextDecoder().decode(base64UrlToUint8Array(payloadB64)));

    expect(header.alg).toBe('RS256');
    expect(header.typ).toBe('JWT');
    expect(payload.iss).toBe('test-sa@project.iam.gserviceaccount.com');
    expect(payload.aud).toBe('https://oauth2.googleapis.com/token');
    expect(payload.iat).toBe(nowSec);
    expect(payload.exp).toBe(nowSec + 3600);

    // İmzayı public key ile doğrula
    const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const sigBytes = base64UrlToUint8Array(sigB64);
    const valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      keyPair.publicKey,
      sigBytes,
      signedData
    );
    expect(valid).toBe(true);
  });

  it('access_token alınır, önbelleğe yazılır ve vadeden önce tekrar çağrıldığında ağ çağrısı yapılmaz', async () => {
    const { serviceAccountB64 } = await generateTestServiceAccount();

    let fetchCount = 0;
    const mockFetch: FetchFunction = async (url) => {
      fetchCount++;
      expect(url).toBe('https://oauth2.googleapis.com/token');
      return new Response(
        JSON.stringify({
          access_token: `token_${fetchCount}`,
          expires_in: 3600,
          token_type: 'Bearer',
        }),
        { status: 200 }
      );
    };

    let currentTimeMs = 1728518400000;
    const tokenProvider = new ServiceAccountTokenProvider(serviceAccountB64, {
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
    });

    // 1. İlk token alımı
    const token1 = await tokenProvider.getAccessToken();
    expect(token1).toBe('token_1');
    expect(fetchCount).toBe(1);

    // 2. 10 dakika sonra tekrar çağır (vadesine 50 dk var, önbellekten gelmeli)
    currentTimeMs += 600 * 1000;
    const token2 = await tokenProvider.getAccessToken();
    expect(token2).toBe('token_1');
    expect(fetchCount).toBe(1);

    // 3. Vadesine 4 dakika kala (3600s - 300s = 3300s sonra, yani vadeden 5 dk önceki eşiği geçtiğinde) yenilemeli
    currentTimeMs += 2800 * 1000; // Toplam 3400 sn geçti
    const token3 = await tokenProvider.getAccessToken();
    expect(token3).toBe('token_2');
    expect(fetchCount).toBe(2);
  });

  it('eşzamanlı çağrılar tek bir token isteğini paylaşır (single-flight)', async () => {
    const { serviceAccountB64 } = await generateTestServiceAccount();

    let fetchCount = 0;
    const mockFetch: FetchFunction = async () => {
      fetchCount++;
      await new Promise((r) => setTimeout(r, 20));
      return new Response(
        JSON.stringify({
          access_token: 'concurrent_token',
          expires_in: 3600,
        }),
        { status: 200 }
      );
    };

    const tokenProvider = new ServiceAccountTokenProvider(serviceAccountB64, {
      fetchFn: mockFetch,
    });

    const [t1, t2, t3] = await Promise.all([
      tokenProvider.getAccessToken(),
      tokenProvider.getAccessToken(),
      tokenProvider.getAccessToken(),
    ]);

    expect(t1).toBe('concurrent_token');
    expect(t2).toBe('concurrent_token');
    expect(t3).toBe('concurrent_token');
    expect(fetchCount).toBe(1); // Yalnızca tek bir ağ isteği yapıldı
  });
});

describe('parseQuestionsPoolWithStats (İçerik Ayrıştırma ve Bozuk Soru Filtreleme)', () => {
  it('geçerli soruları ayrıştırır, eksik ve bozuk soruları atlar', () => {
    const rawData = {
      genel_kultur: {
        q_valid_1: {
          question: 'Türkiye başkenti',
          acceptable_answers: {
            ankara: ['ankara', 'ankra'],
          },
        },
        q_valid_2: {
          question: 'Fransa başkenti',
          acceptable_answers: {
            paris: ['paris'],
          },
        },
        q_empty_question: {
          question: '   ',
          acceptable_answers: {
            ankara: ['ankara'],
          },
        },
        q_no_answers: {
          question: 'Cevapsız soru',
          acceptable_answers: {},
        },
        q_corrupt: null,
      },
      bos_kategori: {},
    };

    const { questions, stats } = parseQuestionsPoolWithStats(rawData);

    expect(questions.length).toBe(2);
    expect(stats.questionsCount).toBe(2);
    expect(stats.categoriesCount).toBe(2);
    expect(stats.answersCount).toBe(2);
    expect(stats.skippedQuestionsCount).toBe(3); // q_empty_question, q_no_answers, q_corrupt
  });
});

describe('RealtimeDbContentProvider (RTDB Sorgusu, Önbellek, TTL ve Hata Yönetimi)', () => {
  const samplePool = {
    c1: {
      q1: {
        question: 'Soru 1',
        acceptable_answers: { a1: ['a1'] },
      },
    },
  };

  it('önce Authorization: Bearer başlığını kullanır ve başarılı olur', async () => {
    let usedAuthHeader: string | null = null;

    const mockFetch: FetchFunction = async (_url, init) => {
      usedAuthHeader = (init?.headers as Record<string, string>)?.['Authorization'] ?? null;
      return new Response(JSON.stringify(samplePool), { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
    });

    const res = await provider.fetchFromDatabase();
    expect(res.questions.length).toBe(1);
    expect(res.authMethod).toBe('none'); // tokenProvider yokken doğrudan dener
  });

  it('Bearer başlığı 401 döndürürse ?access_token= sorgu parametresine geçer', async () => {
    let callCount = 0;
    let fallbackUrlCalled = false;

    const mockFetch: FetchFunction = async (url, init) => {
      callCount++;
      const authHeader = (init?.headers as Record<string, string>)?.['Authorization'];

      if (authHeader) {
        // Bearer başlığı reddedilir
        return new Response('Unauthorized', { status: 401 });
      }

      if (url.includes('access_token=dummy_token')) {
        fallbackUrlCalled = true;
        return new Response(JSON.stringify(samplePool), { status: 200 });
      }

      return new Response('Forbidden', { status: 403 });
    };

    // Sahte bir tokenProvider enjekte et
    const mockTokenProvider = {
      getAccessToken: async () => 'dummy_token',
    } as unknown as ServiceAccountTokenProvider;

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      tokenProvider: mockTokenProvider,
      fetchFn: mockFetch,
    });

    const res = await provider.fetchFromDatabase();
    expect(fallbackUrlCalled).toBe(true);
    expect(res.authMethod).toBe('query_param');
    expect(res.questions.length).toBe(1);
    expect(callCount).toBe(2);
  });

  it('önbellek yokken çekme başarısız olursa açık hata fırlatır', async () => {
    const mockFetch: FetchFunction = async () => {
      return new Response('Database error', { status: 500 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
    });

    await expect(provider.getQuestions()).rejects.toThrow(
      'Realtime Database request failed with HTTP 500'
    );
  });

  it('TTL süresi dolunca eski önbellekle döner ve arka planda yeniler, yenileme hatasında eskiyi korur', async () => {
    let fetchCount = 0;
    let currentTimeMs = 1000000;

    const mockFetch: FetchFunction = async () => {
      fetchCount++;
      if (fetchCount === 1) {
        return new Response(JSON.stringify(samplePool), { status: 200 });
      }
      // Arka plan yenilemesinde hata al
      return new Response('Temporary error', { status: 503 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      ttlSeconds: 60,
    });

    // 1. İlk çekme -> başarılı
    const q1 = await provider.getQuestions();
    expect(q1.length).toBe(1);
    expect(fetchCount).toBe(1);

    // 2. TTL süresi geçti (70 saniye sonra)
    currentTimeMs += 70 * 1000;

    // getQuestions() anında eski önbelleği döndürür ve arka plan yenilemesini tetikler
    const q2 = await provider.getQuestions();
    expect(q2.length).toBe(1);

    // Kısa bir bekleme ile arka plan promise'inin bitmesini sağla
    await new Promise((r) => setTimeout(r, 10));

    // Yenileme 503 ile patlamış olsa dahi eski önbellek sağlam kalır
    const q3 = await provider.getQuestions();
    expect(q3.length).toBe(1);
    expect(fetchCount).toBe(2);
  });
});

