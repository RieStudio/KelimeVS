import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {},
}));

import {
  inspectSecretB64,
  checkPemFormat,
  sanitizeDetail,
  sanitizeErrorMessage,
  extractCauseCode,
  extractErrorMessage,
  logContentError,
  resetContentErrorLogger,
  parseServiceAccountB64,
  ServiceAccountTokenProvider,
  RealtimeDbContentProvider,
  type ContentErrorLogPayload,
} from '../src/content';
import { createContentProvider } from '../src/matchmaker';
import type { Env } from '../src';

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function generateValidServiceAccount() {
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
  return { keyPair, serviceAccountJson, serviceAccountB64, pem };
}

describe('İçerik Hattı Tanılama ve Güvenli Loglama (contentDiagnostics)', () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    resetContentErrorLogger();
    warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  afterEach(() => {
    warnSpy.mockRestore();
    resetContentErrorLogger();
  });

  describe('1. Aşama: secret_missing', () => {
    it('FIREBASE_DATABASE_URL eksik olduğunda stage: secret_missing ve tanı bayraklarını loglar', () => {
      const mockEnv: Env = {
        ALLOW_DEV_AUTH: 'false',
        CONTENT_SOURCE: 'realtime',
        FIREBASE_DATABASE_URL: '',
        FIREBASE_SERVICE_ACCOUNT_B64: 'some-placeholder',
      } as unknown as Env;

      expect(() => createContentProvider(mockEnv)).toThrow();
      expect(warnSpy).toHaveBeenCalledTimes(1);

      const logLine = warnSpy.mock.calls[0][0] as string;
      expect(logLine).not.toContain('\n'); // Tek satır
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('secret_missing');
      expect(parsed.errorName).toBe('ConfigError');
      expect(parsed.hasSecret).toBe(true);
      expect(typeof parsed.hasClientEmail).toBe('boolean');
      expect(typeof parsed.hasPrivateKey).toBe('boolean');
      expect(typeof parsed.isPemFormatValid).toBe('boolean');
    });

    it('FIREBASE_SERVICE_ACCOUNT_B64 eksik olduğunda stage: secret_missing loglar', () => {
      const mockEnv: Env = {
        ALLOW_DEV_AUTH: 'false',
        CONTENT_SOURCE: 'realtime',
        FIREBASE_DATABASE_URL: 'https://test-db.firebaseio.com',
        FIREBASE_SERVICE_ACCOUNT_B64: '',
      } as unknown as Env;

      expect(() => createContentProvider(mockEnv)).toThrow();
      expect(warnSpy).toHaveBeenCalledTimes(1);

      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.stage).toBe('secret_missing');
      expect(parsed.hasSecret).toBe(false);
      expect(parsed.hasClientEmail).toBe(false);
      expect(parsed.hasPrivateKey).toBe(false);
      expect(parsed.isPemFormatValid).toBe(false);
    });
  });

  describe('2. Aşama: secret_decode', () => {
    it('Bozuk base64 dizesinde stage: secret_decode ve DecodeError loglar', () => {
      expect(() => parseServiceAccountB64('@@@geçersiz-base64@@@')).toThrow();
      expect(warnSpy).toHaveBeenCalledTimes(1);

      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('secret_decode');
      expect(parsed.errorName).toBe('DecodeError');
      expect(parsed.hasSecret).toBe(true);
      expect(parsed.hasClientEmail).toBe(false);
    });

    it('Geçersiz JSON durumunda stage: secret_decode ve SyntaxError loglar', () => {
      const invalidJsonB64 = btoa('this is not json');
      expect(() => parseServiceAccountB64(invalidJsonB64)).toThrow();
      expect(warnSpy).toHaveBeenCalledTimes(1);

      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.stage).toBe('secret_decode');
      expect(parsed.errorName).toBe('SyntaxError');
    });

    it('Eksik client_email veya private_key durumunda stage: secret_decode ve ValidationError loglar', () => {
      const missingKeysB64 = btoa(JSON.stringify({ some_other_key: 'value' }));
      expect(() => parseServiceAccountB64(missingKeysB64)).toThrow();
      expect(warnSpy).toHaveBeenCalledTimes(1);

      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.stage).toBe('secret_decode');
      expect(parsed.errorName).toBe('ValidationError');
      expect(parsed.hasClientEmail).toBe(false);
      expect(parsed.hasPrivateKey).toBe(false);
    });
  });

  describe('3. Aşama: jwt_sign', () => {
    it('PKCS8 anahtar biçimi bozuk olduğunda Web Crypto importKey hatasını stage: jwt_sign olarak loglar', async () => {
      const corruptedPem = '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----';
      const saB64 = btoa(
        JSON.stringify({
          client_email: 'test@example.iam.gserviceaccount.com',
          private_key: corruptedPem,
        })
      );

      const provider = new ServiceAccountTokenProvider(saB64);
      await expect(provider.getAccessToken()).rejects.toThrow();

      expect(warnSpy).toHaveBeenCalled();
      const logLines = warnSpy.mock.calls.map(
        (c: unknown[]) => JSON.parse(c[0] as string) as ContentErrorLogPayload
      );
      const jwtSignLog = logLines.find((l: ContentErrorLogPayload) => l.stage === 'jwt_sign');

      expect(jwtSignLog).toBeDefined();
      expect(jwtSignLog?.event).toBe('content_error');
      expect(jwtSignLog?.stage).toBe('jwt_sign');
      expect(jwtSignLog?.errorName).toBe('DataError');
      expect(jwtSignLog?.hasPrivateKey).toBe(true);
      expect(jwtSignLog?.isPemFormatValid).toBe(true);
      // Anahtar içeriği ya da PEM loga sızmamalı
      expect(JSON.stringify(jwtSignLog)).not.toContain('BEGIN PRIVATE KEY');
    });
  });

  describe('4. Aşama: token_exchange', () => {
    it('Google OAuth2 uç noktası 400 invalid_grant döndürdüğünde durum kodu ve Google hata kodunu loglar', async () => {
      const { serviceAccountB64 } = await generateValidServiceAccount();

      const mockFetch = vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            error: 'invalid_grant',
            error_description: 'Invalid JWT Signature.',
          }),
          {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          }
        )
      );

      const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
        fetchFn: mockFetch,
      });

      await expect(provider.getAccessToken()).rejects.toThrow();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('token_exchange');
      expect(parsed.status).toBe(400);
      expect(parsed.errorName).toBe('OAuthTokenError');
      expect(parsed.code).toBe('invalid_grant');
      expect(parsed.detail).toContain('Invalid JWT Signature.');
      expect(parsed.hasSecret).toBe(true);
      expect(parsed.hasClientEmail).toBe(true);
      expect(parsed.hasPrivateKey).toBe(true);
      expect(parsed.isPemFormatValid).toBe(true);
    });

    it('Google OAuth2 yanıtında access_token eksik olduğunda stage: token_exchange loglar', async () => {
      const { serviceAccountB64 } = await generateValidServiceAccount();

      const mockFetch = vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ expires_in: 3600 }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
        fetchFn: mockFetch,
      });

      await expect(provider.getAccessToken()).rejects.toThrow();

      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.stage).toBe('token_exchange');
      expect(parsed.status).toBe(200);
      expect(parsed.errorName).toBe('OAuthTokenError');
    });
  });

  describe('5. Aşama: rtdb_fetch', () => {
    it('Firebase Realtime Database 401 döndürdüğünde durum kodu ve RTDB hata kodunu loglar', async () => {
      const mockFetch = vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: 'Permission denied' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
      });

      await expect(provider.fetchFromDatabase()).rejects.toThrow();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('rtdb_fetch');
      expect(parsed.status).toBe(401);
      expect(parsed.errorName).toBe('RtdbHttpError');
      expect(parsed.code).toBe('Permission denied');
      expect(parsed.detail).toBe('Permission denied');
    });

    it('Ağ hatasında (bağlantı kopması) stage: rtdb_fetch ve NetworkError loglar', async () => {
      const mockFetch = vi.fn().mockRejectedValue(new Error('Connection reset by peer'));

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
      });

      await expect(provider.fetchFromDatabase()).rejects.toThrow();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.stage).toBe('rtdb_fetch');
      expect(parsed.errorName).toBe('Error');
    });
  });

  describe('6. Aşama: parse', () => {
    it('RTDB yanıtı bozuk JSON olduğunda stage: parse ve SyntaxError loglar', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => {
          throw new SyntaxError('Unexpected token < in JSON at position 0');
        },
      } as unknown as Response);

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
      });

      await expect(provider.fetchFromDatabase()).rejects.toThrow();

      expect(warnSpy).toHaveBeenCalledTimes(1);
      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('parse');
      expect(parsed.errorName).toBe('SyntaxError');
    });

    it('Soru havuzunda 8\'den az soru döndüğünde stage: parse ve InsufficientQuestionsError loglar', async () => {
      const poolWithOnlyOneQuestion = {
        cat1: {
          q1: {
            question: 'Soru 1',
            acceptable_answers: { cevap: ['cevap'] },
          },
        },
      };

      const mockFetch = vi.fn().mockResolvedValue(
        new Response(JSON.stringify(poolWithOnlyOneQuestion), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
      });

      const result = await provider.fetchFromDatabase();
      expect(result.questions.length).toBe(1);

      expect(warnSpy).toHaveBeenCalledTimes(1);
      const logLine = warnSpy.mock.calls[0][0] as string;
      const parsed = JSON.parse(logLine);

      expect(parsed.event).toBe('content_error');
      expect(parsed.stage).toBe('parse');
      expect(parsed.errorName).toBe('InsufficientQuestionsError');
      expect(parsed.detail).toContain('found: 1');
    });
  });

  describe('Güvenlik ve Gizlilik Denetimleri (Leak Prevention)', () => {
    it('sanitizeDetail: email, URL sorgu parametreleri, JWT ve uzun anahtarları maskeler', () => {
      const raw =
        'Error at https://oauth2.googleapis.com/token?access_token=ya29.secret_token_123456789 from user@riestudio.com.tr with eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature_abc_1234567890';
      const clean = sanitizeDetail(raw);

      expect(clean).not.toContain('user@riestudio.com.tr');
      expect(clean).toContain('[REDACTED_EMAIL]');
      expect(clean).not.toContain('?access_token=');
      expect(clean).not.toContain('ya29');
      expect(clean).not.toContain('eyJhbGciOi');
    });

    it('sanitizeErrorMessage: 40+ ardışık karakteri [redacted] yapar, Bearer ve access_token kalıplarını siler, 120 karaktere keser', () => {
      const longSecret = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD_EFGH-IJKL';
      expect(longSecret.length).toBeGreaterThanOrEqual(40);

      const raw = `Failed to connect with Bearer secret_bearer_token and access_token=secret_query_token; key was ${longSecret}; plus extra padding characters to make this error message exceed one hundred and twenty characters in total length easily.`;
      const clean = sanitizeErrorMessage(raw);

      expect(clean).not.toContain('Bearer');
      expect(clean).not.toContain('access_token=');
      expect(clean).not.toContain(longSecret);
      expect(clean).toContain('[redacted]');
      expect(clean.length).toBeLessThanOrEqual(120);
    });

    it('extractCauseCode: cause.code ve code alanlarını doğru çıkarır', () => {
      const errWithCauseObj = new Error('fetch failed');
      (errWithCauseObj as unknown as { cause: { code: string } }).cause = { code: 'ENOTFOUND' };
      expect(extractCauseCode(errWithCauseObj)).toBe('ENOTFOUND');

      const errWithCauseStr = new Error('timeout');
      (errWithCauseStr as unknown as { cause: string }).cause = 'UND_ERR_CONNECT_TIMEOUT';
      expect(extractCauseCode(errWithCauseStr)).toBe('UND_ERR_CONNECT_TIMEOUT');

      const errWithCode = new Error('reset');
      (errWithCode as unknown as { code: string }).code = 'ECONNRESET';
      expect(extractCauseCode(errWithCode)).toBe('ECONNRESET');

      expect(extractCauseCode(new Error('normal'))).toBeUndefined();
      expect(extractCauseCode(null)).toBeUndefined();
    });

    it('Günlüğe yazılan JSON dizesinde secret, token, key veya query param geçmez; causeCode ve message güvenle yer alır', () => {
      const mockWarn = vi.fn();
      const secretToHide = 'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC6';

      logContentError(
        {
          event: 'content_error',
          stage: 'token_exchange',
          status: 400,
          errorName: 'TestError',
          code: 'invalid_grant',
          detail: `Failed for key ${secretToHide} with query ?access_token=ya29.token123`,
          causeCode: 'ENOTFOUND',
          message: `Request failed with Bearer ya29.secret and key ${secretToHide}`,
          hasSecret: true,
          hasClientEmail: true,
          hasPrivateKey: true,
          isPemFormatValid: true,
        },
        mockWarn
      );

      expect(mockWarn).toHaveBeenCalledTimes(1);
      const output = mockWarn.mock.calls[0][0] as string;

      expect(output).not.toContain(secretToHide);
      expect(output).not.toContain('?access_token=');
      expect(output).not.toContain('ya29.token123');
      expect(output).not.toContain('Bearer');

      // Yalnızca boolean değerler olduğunu doğrula
      const parsed = JSON.parse(output);
      expect(parsed.causeCode).toBe('ENOTFOUND');
      expect(parsed.message).toContain('[redacted]');
      expect(parsed.message.length).toBeLessThanOrEqual(120);
      expect(typeof parsed.hasSecret).toBe('boolean');
      expect(typeof parsed.hasClientEmail).toBe('boolean');
      expect(typeof parsed.hasPrivateKey).toBe('boolean');
      expect(typeof parsed.isPemFormatValid).toBe('boolean');
    });

    it('Günlük her zaman tek satırlık geçerli bir JSON olmalıdır', () => {
      const mockWarn = vi.fn();
      logContentError(
        {
          event: 'content_error',
          stage: 'parse',
          errorName: 'TestError',
          detail: 'Multiline\nerror\r\ndetail test',
        },
        mockWarn
      );

      const output = mockWarn.mock.calls[0][0] as string;
      expect(output.includes('\n')).toBe(false);
      expect(output.includes('\r')).toBe(false);
      expect(() => JSON.parse(output)).not.toThrow();
    });
  });

  describe('Dayanıklılık ve Yeniden Deneme (Resilience & Retry)', () => {
    it('ServiceAccountTokenProvider: Geçici ağ hatasında 1 kez 300 ms bekleyip yeniden dener ve başarılı olur', async () => {
      const { serviceAccountB64 } = await generateValidServiceAccount();
      let fetchCount = 0;
      const sleepSpy = vi.fn().mockResolvedValue(undefined);

      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        if (fetchCount === 1) {
          const typeErr = new TypeError('fetch failed');
          (typeErr as unknown as { cause: { code: string } }).cause = { code: 'ENOTFOUND' };
          throw typeErr;
        }
        return new Response(JSON.stringify({ access_token: 'valid_token_after_retry', expires_in: 3600 }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      });

      const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
        fetchFn: mockFetch,
        sleepFn: sleepSpy,
      });

      const token = await provider.getAccessToken();
      expect(token).toBe('valid_token_after_retry');
      expect(fetchCount).toBe(2);
      expect(sleepSpy).toHaveBeenCalledWith(300);
      expect(warnSpy).not.toHaveBeenCalled(); // Başarılı olduğu için hata günlüğü basılmaz
    });

    it('ServiceAccountTokenProvider: 5xx hatasında 1 kez yeniden dener', async () => {
      const { serviceAccountB64 } = await generateValidServiceAccount();
      let fetchCount = 0;
      const sleepSpy = vi.fn().mockResolvedValue(undefined);

      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        if (fetchCount === 1) {
          return new Response(JSON.stringify({ error: 'server_error' }), { status: 503 });
        }
        return new Response(JSON.stringify({ access_token: 'token_after_503', expires_in: 3600 }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      });

      const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
        fetchFn: mockFetch,
        sleepFn: sleepSpy,
      });

      const token = await provider.getAccessToken();
      expect(token).toBe('token_after_503');
      expect(fetchCount).toBe(2);
      expect(sleepSpy).toHaveBeenCalledWith(300);
    });

    it('ServiceAccountTokenProvider: 4xx hatasında (örn. 400 invalid_grant) yeniden DENENMEZ', async () => {
      const { serviceAccountB64 } = await generateValidServiceAccount();
      let fetchCount = 0;
      const sleepSpy = vi.fn().mockResolvedValue(undefined);

      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        return new Response(
          JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid signature' }),
          { status: 400 }
        );
      });

      const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
        fetchFn: mockFetch,
        sleepFn: sleepSpy,
      });

      await expect(provider.getAccessToken()).rejects.toThrow();
      expect(fetchCount).toBe(1); // Yalnızca 1 deneme
      expect(sleepSpy).not.toHaveBeenCalled(); // 4xx'te bekleme yapılmaz
    });

    it('RealtimeDbContentProvider: Ağ hatasında 1 kez yeniden dener ve başarılı olur', async () => {
      let fetchCount = 0;
      const sleepSpy = vi.fn().mockResolvedValue(undefined);

      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        if (fetchCount === 1) {
          throw new TypeError('fetch failed');
        }
        return new Response(JSON.stringify({ questions_pool: {} }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      });

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
        sleepFn: sleepSpy,
      });

      await provider.fetchFromDatabase();
      expect(fetchCount).toBe(2);
      expect(sleepSpy).toHaveBeenCalledWith(300);
    });

    it('RealtimeDbContentProvider: 4xx yetki hatasında (401/403) yeniden DENENMEZ', async () => {
      let fetchCount = 0;
      const sleepSpy = vi.fn().mockResolvedValue(undefined);

      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        return new Response(JSON.stringify({ error: 'Permission denied' }), { status: 401 });
      });

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
        sleepFn: sleepSpy,
      });

      await expect(provider.fetchFromDatabase()).rejects.toThrow();
      // Token yokken tek istek atılır ve 401 döner, 5xx veya ağ hatası olmadığı için 300ms yeniden deneme yapılmaz
      expect(sleepSpy).not.toHaveBeenCalled();
    });

    it('RealtimeDbContentProvider: Eşzamanlı getQuestions çağrıları tek bir yükleme isteği paylaşır (Single-flight)', async () => {
      let fetchCount = 0;
      const mockFetch = vi.fn().mockImplementation(async () => {
        fetchCount++;
        // Yapay gecikme
        await new Promise((resolve) => setTimeout(resolve, 20));
        return new Response(JSON.stringify({ questions_pool: {} }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      });

      const provider = new RealtimeDbContentProvider({
        databaseUrl: 'https://test-db.firebaseio.com',
        fetchFn: mockFetch,
      });

      // 3 eşzamanlı çağrı
      const [res1, res2, res3] = await Promise.all([
        provider.getQuestions(),
        provider.getQuestions(),
        provider.getQuestions(),
      ]);

      expect(res1).toBe(res2);
      expect(res2).toBe(res3);
      expect(fetchCount).toBe(2); // Tek bir initial yükleme (version + pool) yapıldı (3 eşzamanlı çağrı tek promise'i paylaştı)
    });
  });

  describe('Spam ve Mükerrer Günlük Engelleme (De-duplication)', () => {
    it('10 saniye içinde tekrarlanan aynı hatayı loglamaz, farklı hatayı loglar', () => {
      const mockWarn = vi.fn();
      let fakeTime = 100000;
      const nowFn = () => fakeTime;

      // 1. İlk hata: Loglanır
      const res1 = logContentError(
        {
          event: 'content_error',
          stage: 'rtdb_fetch',
          status: 500,
          detail: 'Database unavailable',
        },
        mockWarn,
        nowFn
      );
      expect(res1).toBe(true);
      expect(mockWarn).toHaveBeenCalledTimes(1);

      // 2. 2 saniye sonra aynı hata: Loglanmaz (spam önleme)
      fakeTime += 2000;
      const res2 = logContentError(
        {
          event: 'content_error',
          stage: 'rtdb_fetch',
          status: 500,
          detail: 'Database unavailable',
        },
        mockWarn,
        nowFn
      );
      expect(res2).toBe(false);
      expect(mockWarn).toHaveBeenCalledTimes(1);

      // 3. 2 saniye sonra farklı bir hata: Loglanır
      fakeTime += 2000;
      const res3 = logContentError(
        {
          event: 'content_error',
          stage: 'parse',
          status: 200,
          detail: 'Pool is empty',
        },
        mockWarn,
        nowFn
      );
      expect(res3).toBe(true);
      expect(mockWarn).toHaveBeenCalledTimes(2);

      // 4. 11 saniye sonra ilk hata tekrar gelirse: Loglanır (pencere aşıldı)
      fakeTime += 11000;
      const res4 = logContentError(
        {
          event: 'content_error',
          stage: 'rtdb_fetch',
          status: 500,
          detail: 'Database unavailable',
        },
        mockWarn,
        nowFn
      );
      expect(res4).toBe(true);
      expect(mockWarn).toHaveBeenCalledTimes(3);
    });
  });
});
