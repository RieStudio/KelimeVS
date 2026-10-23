import { describe, expect, it } from 'vitest';
import {
  parseQuestionsPoolWithStats,
  RealtimeDbContentProvider,
  ServiceAccountTokenProvider,
  findAliasCollisions,
  logAliasCollisions,
  type FetchFunction,
} from '../src/content';
import type { Question } from '../src/engine';

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

  const pkcs8Der = (await crypto.subtle.exportKey('pkcs8', keyPair.privateKey)) as ArrayBuffer;
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
    let poolFetchCount = 0;
    let currentTimeMs = 1000000;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        return new Response('null', { status: 200 });
      }
      poolFetchCount++;
      if (poolFetchCount === 1) {
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
    expect(poolFetchCount).toBe(1);

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
    expect(poolFetchCount).toBe(2);
  });
});

describe('RealtimeDbContentProvider (content_version Hızlı Senkronizasyon ve Arka Plan Yenileme)', () => {
  const poolV1 = {
    c1: {
      q1: {
        question: 'Versiyon 1 Soru',
        acceptable_answers: { a1: ['a1'] },
      },
    },
  };

  const poolV2 = {
    c1: {
      q1: {
        question: 'Versiyon 2 Soru',
        acceptable_answers: { a1: ['a1'] },
      },
      q2: {
        question: 'Yeni Eklenen Soru',
        acceptable_answers: { a2: ['a2'] },
      },
    },
  };

  it('1. Sürüm aynı kaldığında tam havuz ÇEKİLMEZ (Firebase Spark kotası korunur)', async () => {
    let poolFetchCount = 0;
    let versionFetchCount = 0;
    let currentTimeMs = 1000000;
    const currentVersion = 100;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        versionFetchCount++;
        return new Response(JSON.stringify(currentVersion), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        poolFetchCount++;
        return new Response(JSON.stringify(poolV1), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      versionCheckIntervalSeconds: 15,
      ttlSeconds: 3600,
      initialContentVersion: currentVersion,
    });

    // 1. İlk çekme (cache boş) -> havuz ve versiyon çekilir
    const q1 = await provider.getQuestions();
    expect(q1.length).toBe(1);
    expect(q1[0].text).toBe('Versiyon 1 Soru');
    expect(poolFetchCount).toBe(1);
    expect(versionFetchCount).toBe(1);

    // 2. 10 saniye sonra çağrı (15 sn eşiği dolmadı) -> sıfır ağ çağrısı
    currentTimeMs += 10 * 1000;
    const q2 = await provider.getQuestions();
    expect(q2.length).toBe(1);
    expect(poolFetchCount).toBe(1);
    expect(versionFetchCount).toBe(1);

    // 3. 20 saniye sonra çağrı (15 sn doldu, sürüm kontrolü tetiklenir)
    currentTimeMs += 10 * 1000; // toplam +20s
    const q3 = await provider.getQuestions();
    expect(q3.length).toBe(1);

    // Arka plan versiyon kontrolünün tamamlanmasını bekle
    if (provider.inFlightRefresh) {
      await provider.inFlightRefresh;
    }

    // Sürüm hala 100 olduğu için versiyon kontrolü yapıldı AMA tam havuz ÇEKİLMEDİ
    expect(versionFetchCount).toBe(2);
    expect(poolFetchCount).toBe(1);
  });

  it('2. Sürüm değiştiğinde mevcut çağrı eski veriyi anında döner, arka plan bitince sonraki çağrı yeni veriyi döner', async () => {
    let poolFetchCount = 0;
    let versionFetchCount = 0;
    let currentTimeMs = 1000000;
    let remoteVersion = 1;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        versionFetchCount++;
        return new Response(JSON.stringify(remoteVersion), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        poolFetchCount++;
        const pool = remoteVersion === 1 ? poolV1 : poolV2;
        return new Response(JSON.stringify(pool), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      versionCheckIntervalSeconds: 15,
      ttlSeconds: 3600,
      initialContentVersion: 1,
    });

    // 1. İlk çekme -> v1 havuzu yüklenir
    const q1 = await provider.getQuestions();
    expect(q1.length).toBe(1);
    expect(q1[0].text).toBe('Versiyon 1 Soru');
    expect(poolFetchCount).toBe(1);

    // 2. Panel içeriği günceller ve sürümü 2 yapar
    remoteVersion = 2;
    currentTimeMs += 20 * 1000; // 15 sn eşiği aşıldı

    // 3. getQuestions çağrısı eski veriyi (v1) ANINDA döner, maçı bekletmez!
    const q2 = await provider.getQuestions();
    expect(q2.length).toBe(1);
    expect(q2[0].text).toBe('Versiyon 1 Soru');

    // 4. Arka plandaki havuz yenileme tamamlanır
    expect(provider.inFlightRefresh).not.toBeNull();
    await provider.inFlightRefresh;

    // Sürüm 2 çekilmiş olmalı
    expect(poolFetchCount).toBe(2);
    expect(versionFetchCount).toBe(2);
    expect(provider.currentVersion).toBe(2);

    // 5. Bir sonraki getQuestions çağrısı artık YENİ veriyi (v2) döner
    const q3 = await provider.getQuestions();
    expect(q3.length).toBe(2);
    expect(q3.map((q) => q.text)).toEqual(['Versiyon 2 Soru', 'Yeni Eklenen Soru']);
  });

  it('3. Eşzamanlı isteklerde tek bir arka plan yenilemesi çalışır (in-flight promise paylaşımı)', async () => {
    let poolFetchCount = 0;
    let versionFetchCount = 0;
    let currentTimeMs = 1000000;
    let remoteVersion = 1;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        versionFetchCount++;
        await new Promise((r) => setTimeout(r, 10));
        return new Response(JSON.stringify(remoteVersion), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        poolFetchCount++;
        await new Promise((r) => setTimeout(r, 10));
        const pool = remoteVersion === 1 ? poolV1 : poolV2;
        return new Response(JSON.stringify(pool), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      versionCheckIntervalSeconds: 15,
      initialContentVersion: 1,
    });

    await provider.getQuestions(); // ilk yükleme
    expect(poolFetchCount).toBe(1);

    // Sürüm değişti ve 15 sn geçti
    remoteVersion = 2;
    currentTimeMs += 20 * 1000;

    // Aynı anda 5 eşzamanlı getQuestions çağrısı gelir
    const results = await Promise.all([
      provider.getQuestions(),
      provider.getQuestions(),
      provider.getQuestions(),
      provider.getQuestions(),
      provider.getQuestions(),
    ]);

    // Hepsi eski cache'i anında alır (arayanlar bloke olmaz)
    for (const res of results) {
      expect(res.length).toBe(1);
    }

    // Arka plan görevinin bitmesini bekle
    await provider.inFlightRefresh;

    // Yalnızca tek bir versiyon ve tek bir havuz çekimi yapıldı (initial 1 + background 1)
    expect(versionFetchCount).toBe(2);
    expect(poolFetchCount).toBe(2);
  });

  it('4. Arka plan yenilemesi hata verirse eski cache korunur ve oyun durmaz', async () => {
    let currentTimeMs = 1000000;
    let remoteVersion = 1;
    let poolFail = false;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        return new Response(JSON.stringify(remoteVersion), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        if (poolFail) {
          return new Response('Internal Server Error', { status: 500 });
        }
        return new Response(JSON.stringify(poolV1), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      versionCheckIntervalSeconds: 15,
      initialContentVersion: 1,
    });

    const q1 = await provider.getQuestions();
    expect(q1.length).toBe(1);

    // Sürüm 2 oldu ancak RTDB havuz için 500 veriyor
    remoteVersion = 2;
    poolFail = true;
    currentTimeMs += 20 * 1000;

    // Çağrı anında döner
    const q2 = await provider.getQuestions();
    expect(q2.length).toBe(1);

    // Arka plan hatasını bekle
    await provider.inFlightRefresh;

    // Eski önbellek sapasağlam durmalı
    const q3 = await provider.getQuestions();
    expect(q3.length).toBe(1);
    expect(q3[0].text).toBe('Versiyon 1 Soru');
    // Sürüm güncellenmemiş olmalı (hata yüzünden eski sürümde kaldı)
    expect(provider.currentVersion).toBe(1);
  });

  it('5. content_version düğümü yoksa (null) TTL süresine kadar havuz tekrar çekilmez', async () => {
    let poolFetchCount = 0;
    let versionFetchCount = 0;
    let currentTimeMs = 1000000;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        versionFetchCount++;
        return new Response('null', { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        poolFetchCount++;
        return new Response(JSON.stringify(poolV1), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      versionCheckIntervalSeconds: 15,
      ttlSeconds: 3600,
    });

    await provider.getQuestions();
    expect(poolFetchCount).toBe(1);

    // 20 sn sonra çağrı -> versiyon kontrolü null döner
    currentTimeMs += 20 * 1000;
    await provider.getQuestions();
    if (provider.inFlightRefresh) {
      await provider.inFlightRefresh;
    }

    expect(versionFetchCount).toBe(2);
    expect(poolFetchCount).toBe(1); // Havuz çekilmedi

    // 40 sn sonra çağrı -> yine null döner, havuz yine çekilmez
    currentTimeMs += 20 * 1000;
    await provider.getQuestions();
    if (provider.inFlightRefresh) {
      await provider.inFlightRefresh;
    }

    expect(versionFetchCount).toBe(3);
    expect(poolFetchCount).toBe(1);
  });
});

describe('findAliasCollisions & logAliasCollisions (Alias Çakışma Uyarı Raporu)', () => {
  it('aynı soru içinde farklı cevaplar aynı normalize alias’ı paylaştığında çakışmayı tespit eder', () => {
    const questions: Question[] = [
      {
        id: 'q1',
        categoryId: 'c1',
        text: 'Meyveler',
        answers: [
          { id: 'elma', display: 'Elma', aliases: ['elma', 'amasya'] },
          { id: 'armut', display: 'Armut', aliases: ['armut', 'amasya'] },
        ],
      },
      {
        id: 'q2',
        categoryId: 'c1',
        text: 'Ülkeler',
        answers: [
          { id: 'kore', display: 'Kore', aliases: ['kore'] },
          { id: 'guney_kore', display: 'Güney Kore', aliases: ['guney kore', 'kore'] },
        ],
      },
      {
        id: 'q3_temiz',
        categoryId: 'c1',
        text: 'Renkler',
        answers: [
          { id: 'mavi', display: 'Mavi', aliases: ['mavi'] },
          { id: 'kirmizi', display: 'Kırmızı', aliases: ['kirmizi', 'al'] },
        ],
      },
    ];

    const collisions = findAliasCollisions(questions);
    expect(collisions.length).toBe(2);

    expect(collisions[0]).toEqual({
      questionId: 'q1',
      categoryId: 'c1',
      alias: 'amasya',
      answerDisplay1: 'Elma',
      answerDisplay2: 'Armut',
    });

    expect(collisions[1]).toEqual({
      questionId: 'q2',
      categoryId: 'c1',
      alias: 'kore',
      answerDisplay1: 'Kore',
      answerDisplay2: 'Güney Kore',
    });

    const logged: string[] = [];
    logAliasCollisions(collisions, (msg) => logged.push(msg));
    expect(logged.length).toBe(2);
    const parsed = JSON.parse(logged[0]);
    expect(parsed.event).toBe('content_warning');
    expect(parsed.stage).toBe('alias_collision');
    expect(parsed.questionId).toBe('q1');
  });
});

describe('RealtimeDbContentProvider (content_refreshed Loglama)', () => {
  const pool = {
    c1: {
      q1: {
        question: 'Soru 1',
        acceptable_answers: { a1: ['a1'] },
      },
      q2: {
        question: 'Soru 2',
        acceptable_answers: { a2: ['a2'] },
      },
    },
    c2: {
      q3: {
        question: 'Soru 3',
        acceptable_answers: { a3: ['a3'] },
      },
    },
  };

  it('havuz başarıyla yüklendiğinde (initial ve version_change) yapılandırılmış content_refreshed log basar', async () => {
    const logs: string[] = [];
    let version = 1;
    let currentTimeMs = 1000000;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        return new Response(JSON.stringify(version), { status: 200 });
      }
      return new Response(JSON.stringify(pool), { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      logFn: (msg) => logs.push(msg),
      initialContentVersion: 1,
      versionCheckIntervalSeconds: 15,
    });

    // 1. İlk yükleme -> reason: "initial"
    await provider.getQuestions();
    expect(logs.length).toBe(1);
    const initialLog = JSON.parse(logs[0]);
    expect(initialLog).toEqual({
      event: 'content_refreshed',
      reason: 'initial',
      version: 1,
      questionCount: 3,
      categoryCount: 2,
    });

    // 2. Sürüm değişimi sonrası arka plan yenileme -> reason: "version_change"
    version = 2;
    currentTimeMs += 20 * 1000;
    await provider.getQuestions();
    await provider.inFlightRefresh;

    expect(logs.length).toBe(2);
    const versionChangeLog = JSON.parse(logs[1]);
    expect(versionChangeLog).toEqual({
      event: 'content_refreshed',
      reason: 'version_change',
      version: 2,
      questionCount: 3,
      categoryCount: 2,
    });
  });
});

describe('fetchContentVersion & content_version Teşhis, Ayrıştırma ve Hata Loglama', () => {
  const pool = {
    c1: {
      q1: {
        question: 'Soru 1',
        acceptable_answers: { a1: ['a1'] },
      },
    },
  };

  it('13 haneli sayısal timestamp versiyonu (1792708977290) doğru okunur, ilk yüklemede cachedContentVersion kaydedilir ve logda görünür', async () => {
    const logs: string[] = [];
    const timestampVersion = 1792708977290;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        return new Response(JSON.stringify(timestampVersion), { status: 200 });
      }
      return new Response(JSON.stringify(pool), { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
    });

    const parsedVersion = await provider.fetchContentVersion();
    expect(parsedVersion).toBe(timestampVersion);
    expect(typeof parsedVersion).toBe('number');

    // İlk yüklemede getQuestions() çağrısı cachedContentVersion'ı doldurmalı
    const questions = await provider.getQuestions();
    expect(questions.length).toBe(1);
    expect(provider.currentVersion).toBe(timestampVersion);

    // content_refreshed logunda version 1792708977290 olmalı
    expect(logs.length).toBe(1);
    const refreshedLog = JSON.parse(logs[0]);
    expect(refreshedLog).toEqual({
      event: 'content_refreshed',
      reason: 'initial',
      version: timestampVersion,
      questionCount: 1,
      categoryCount: 1,
    });
  });

  it('dize formatındaki versiyon ("v2.4.1") doğru ayrıştırılır', async () => {
    const mockFetch: FetchFunction = async () => {
      return new Response(JSON.stringify('v2.4.1'), { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBe('v2.4.1');
  });

  it('content_version düğümü yoksa (null) content_version_missing logu basılır ve null döner', async () => {
    const logs: string[] = [];

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        return new Response(JSON.stringify(null), { status: 200 });
      }
      return new Response(JSON.stringify(pool), { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBeNull();

    expect(logs.length).toBe(1);
    const missingLog = JSON.parse(logs[0]);
    expect(missingLog).toEqual({
      event: 'content_version_missing',
    });

    // İlk yüklemede questions yine çekilir, missing + initial refresh (version: null) logları basılır
    await provider.getQuestions();
    expect(logs.length).toBe(3); // 1. fetchContentVersion doğrudan çağrısı, 2. getQuestions içindeki missing, 3. content_refreshed
    const refreshLog = JSON.parse(logs[2]);
    expect(refreshLog).toEqual({
      event: 'content_refreshed',
      reason: 'initial',
      version: null,
      questionCount: 1,
      categoryCount: 1,
    });
  });

  it('HTTP 401/403 yetki hatasında content_version_fetch_failed logu basılır ve null döner', async () => {
    const logs: string[] = [];

    const mockFetch: FetchFunction = async () => {
      return new Response(JSON.stringify({ error: 'Permission denied' }), { status: 403 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBeNull();

    expect(logs.length).toBe(1);
    const failedLog = JSON.parse(logs[0]);
    expect(failedLog).toEqual({
      event: 'content_version_fetch_failed',
      status: 403,
      reason: 'Permission denied',
    });
  });

  it('HTTP 500 sunucu hatasında content_version_fetch_failed logu basılır ve null döner', async () => {
    const logs: string[] = [];

    const mockFetch: FetchFunction = async () => {
      return new Response('Internal Server Error', { status: 500 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
      sleepFn: async () => {}, // Hızlı tekrar deneme
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBeNull();

    expect(logs.length).toBe(1);
    const failedLog = JSON.parse(logs[0]);
    expect(failedLog).toEqual({
      event: 'content_version_fetch_failed',
      status: 500,
      reason: 'HTTP 500',
    });
  });

  it('ağ hatası (network error) durumunda content_version_fetch_failed (status: undefined) logu basılır', async () => {
    const logs: string[] = [];

    const mockFetch: FetchFunction = async () => {
      throw new Error('ECONNRESET: connection reset by peer');
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
      sleepFn: async () => {},
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBeNull();

    // logs array'inde content_version_fetch_failed logu olmalı
    const fetchFailedLog = logs.map((l) => JSON.parse(l)).find((l) => l.event === 'content_version_fetch_failed');
    expect(fetchFailedLog).toBeDefined();
    expect(fetchFailedLog).toEqual({
      event: 'content_version_fetch_failed',
      status: undefined,
      reason: 'ECONNRESET: connection reset by peer',
    });
  });

  it('bozuk JSON yanıtında content_version_fetch_failed logu basılır', async () => {
    const logs: string[] = [];

    const mockFetch: FetchFunction = async () => {
      return new Response('{ not-valid-json', { status: 200 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      logFn: (msg) => logs.push(msg),
    });

    const version = await provider.fetchContentVersion();
    expect(version).toBeNull();

    expect(logs.length).toBe(1);
    const failedLog = JSON.parse(logs[0]);
    expect(failedLog.event).toBe('content_version_fetch_failed');
    expect(failedLog.status).toBe(200);
    expect(failedLog.reason).toBeTruthy();
  });

  it('ilk yüklemede content_version.json çağrısı questions_pool.json çağrısından ÖNCE tamamlanır', async () => {
    const callOrder: string[] = [];
    let versionCompleted = false;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        callOrder.push('version_start');
        await new Promise((r) => setTimeout(r, 10));
        versionCompleted = true;
        callOrder.push('version_end');
        return new Response(JSON.stringify(1792708977290), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        callOrder.push('pool_start');
        expect(versionCompleted).toBe(true);
        callOrder.push('pool_end');
        return new Response(JSON.stringify(pool), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
    });

    await provider.getQuestions();

    expect(callOrder).toEqual([
      'version_start',
      'version_end',
      'pool_start',
      'pool_end',
    ]);
    expect(provider.currentVersion).toBe(1792708977290);
  });

  it('TTL dolumu sonrası tam yenilemede (triggerBackgroundFullRefresh) content_version havuzdan ÖNCE tamamlanır', async () => {
    const callOrder: string[] = [];
    let currentTimeMs = 1000;

    const mockFetch: FetchFunction = async (url) => {
      if (url.includes('content_version.json')) {
        callOrder.push('version');
        return new Response(JSON.stringify(100), { status: 200 });
      }
      if (url.includes('questions_pool.json')) {
        callOrder.push('pool');
        return new Response(JSON.stringify(pool), { status: 200 });
      }
      return new Response('Not found', { status: 404 });
    };

    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
      nowFn: () => currentTimeMs,
      ttlSeconds: 60,
    });

    // 1. İlk yükleme
    await provider.getQuestions();
    callOrder.length = 0;

    // 2. TTL dolsun
    currentTimeMs += 70 * 1000;
    await provider.getQuestions();
    await provider.inFlightRefresh;

    expect(callOrder).toEqual(['version', 'pool']);
  });
});

