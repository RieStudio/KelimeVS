import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';

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

import {
  RealtimeDbContentProvider,
  ServiceAccountTokenProvider,
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

describe('Strict Invocation / "this" Context Regression Tests (Cloudflare Workers Uyumluluğu)', () => {
  const originalFetch = globalThis.fetch;
  const originalImportKey = crypto.subtle.importKey;
  const originalSign = crypto.subtle.sign;

  let serviceAccountB64: string;

  beforeEach(async () => {
    const sa = await generateTestServiceAccount();
    serviceAccountB64 = sa.serviceAccountB64;

    // SIKI SAHTE: globalThis.fetch
    // Eğer `this` globalThis veya undefined değilse (yani bir sınıf nesnesi alanı üzerinden çağrılmışsa)
    // Cloudflare Workers'taki gibi "Illegal invocation" fırlatır.
    globalThis.fetch = function (
      this: unknown,
      input: RequestInfo | URL,
      init?: RequestInit
    ): Promise<Response> {
      if (this !== globalThis && this !== undefined) {
        throw new TypeError(
          'Illegal invocation: function called with incorrect `this` reference'
        );
      }

      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;

      // Google OAuth token isteği
      if (url.includes('oauth2.googleapis.com/token')) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              access_token: 'fake-oauth2-access-token',
              expires_in: 3600,
            }),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
          )
        );
      }

      // RTDB questions_pool isteği
      if (url.includes('questions_pool.json')) {
        const catQuestions: Record<string, unknown> = {};
        for (let i = 1; i <= 10; i++) {
          catQuestions[`q${i}`] = {
            question: `Soru ${i}`,
            acceptable_answers: {
              [`Cevap ${i}`]: [`cevap ${i}`],
            },
          };
        }
        const mockPool = { cat1: catQuestions };
        return Promise.resolve(
          new Response(JSON.stringify(mockPool), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          })
        );
      }

      return Promise.resolve(new Response('ok', { status: 200 }));
    } as typeof fetch;

    // SIKI SAHTE: crypto.subtle.importKey
    // Eğer `this` crypto.subtle değilse "Illegal invocation" fırlatır.
    crypto.subtle.importKey = function (
      this: unknown,
      ...args: Parameters<typeof originalImportKey>
    ): ReturnType<typeof originalImportKey> {
      if (this !== crypto.subtle) {
        throw new TypeError(
          'Illegal invocation: function called with incorrect `this` reference'
        );
      }
      return originalImportKey.apply(crypto.subtle, args);
    };

    // SIKI SAHTE: crypto.subtle.sign
    // Eğer `this` crypto.subtle değilse "Illegal invocation" fırlatır.
    crypto.subtle.sign = function (
      this: unknown,
      ...args: Parameters<typeof originalSign>
    ): ReturnType<typeof originalSign> {
      if (this !== crypto.subtle) {
        throw new TypeError(
          'Illegal invocation: function called with incorrect `this` reference'
        );
      }
      return originalSign.apply(crypto.subtle, args);
    };
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    crypto.subtle.importKey = originalImportKey;
    crypto.subtle.sign = originalSign;
  });

  it('ServiceAccountTokenProvider: VARSAYILAN bağımlılıklarla getAccessToken() sıkı sahte ile başarılı olmalıdır', async () => {
    // options.fetchFn VERİLMİYOR - varsayılan ortam fetch'ini kullanmalı
    const provider = new ServiceAccountTokenProvider(serviceAccountB64);
    const token = await provider.getAccessToken();
    expect(token).toBe('fake-oauth2-access-token');
  });

  it('RealtimeDbContentProvider: VARSAYILAN bağımlılıklarla fetchFromDatabase() sıkı sahte ile başarılı olmalıdır', async () => {
    // options.fetchFn VERİLMİYOR
    const provider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      serviceAccountB64,
    });
    const result = await provider.fetchFromDatabase();
    expect(result.questions.length).toBeGreaterThanOrEqual(8);
  });

  it('createContentProvider & getQuestions(): VARSAYILAN bağımlılıklarla sıkı sahte ile başarılı olmalıdır', async () => {
    const env = {
      FIREBASE_DATABASE_URL: 'https://test-db.firebaseio.com',
      FIREBASE_SERVICE_ACCOUNT_B64: serviceAccountB64,
    } as unknown as Env;

    const provider = createContentProvider(env);
    const questions = await provider.getQuestions();
    expect(questions.length).toBeGreaterThanOrEqual(8);
  });

  it('Özel (enjekte edilen) fetchFn sahtesi verildiğinde doğru şekilde çağrılmalı ve çalışmalıdır', async () => {
    let customFetchCalled = false;
    const customFetch = vi.fn(async () => {
      customFetchCalled = true;
      return new Response(
        JSON.stringify({
          access_token: 'custom-token',
          expires_in: 3600,
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    });

    const provider = new ServiceAccountTokenProvider(serviceAccountB64, {
      fetchFn: customFetch,
    });
    const token = await provider.getAccessToken();
    expect(token).toBe('custom-token');
    expect(customFetchCalled).toBe(true);
  });

  it('Sıkı sahte: Yanlış this ile çağrılan fetch veya crypto doğrudan Illegal invocation fırlatmalıdır', async () => {
    const wrongThis = { name: 'not-global' };

    // Sıkı fetch
    expect(() => {
      (globalThis.fetch as unknown as (this: unknown, url: string) => Promise<Response>).call(wrongThis, 'https://example.com');
    }).toThrow(/Illegal invocation/);

    // Sıkı crypto.subtle.importKey
    expect(() => {
      (crypto.subtle.importKey as unknown as (this: unknown, ...args: unknown[]) => Promise<CryptoKey>).call(wrongThis, 'raw', new Uint8Array(), 'AES-GCM', false, ['encrypt']);
    }).toThrow(/Illegal invocation/);

    // Sıkı crypto.subtle.sign
    expect(() => {
      (crypto.subtle.sign as unknown as (this: unknown, ...args: unknown[]) => Promise<ArrayBuffer>).call(wrongThis, 'HMAC', {} as CryptoKey, new Uint8Array());
    }).toThrow(/Illegal invocation/);
  });
});

