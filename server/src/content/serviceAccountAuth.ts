// Firebase Servis Hesabı OAuth2 Token Sağlayıcısı (Web Crypto)

export type FetchFunction = (url: string, init?: RequestInit) => Promise<Response>;

export interface ServiceAccountCredentials {
  readonly client_email: string;
  readonly private_key: string;
}

export interface CachedToken {
  readonly token: string;
  readonly expiresAtMs: number;
}

export interface ServiceAccountAuthOptions {
  readonly fetchFn?: FetchFunction;
  readonly nowFn?: () => number;
}

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_SCOPES =
  'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email';
const TOKEN_LIFETIME_SECONDS = 3600;
const EXPIRY_BUFFER_SECONDS = 300; // Vadesinden 5 dakika önce yenile

function base64ToUtf8(b64: string): string {
  const binary = atob(b64.trim());
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN[ A-Z0-9_-]+-----/g, '')
    .replace(/-----END[ A-Z0-9_-]+-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

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

/**
 * Base64 ile kodlanmış servis hesabı JSON dizesini ayrıştırır.
 */
export function parseServiceAccountB64(serviceAccountB64: string): ServiceAccountCredentials {
  try {
    const jsonStr = base64ToUtf8(serviceAccountB64);
    const parsed = JSON.parse(jsonStr) as Record<string, unknown>;

    if (
      typeof parsed.client_email !== 'string' ||
      parsed.client_email.trim().length === 0 ||
      typeof parsed.private_key !== 'string' ||
      parsed.private_key.trim().length === 0
    ) {
      throw new Error('Missing client_email or private_key in service account credentials.');
    }

    return {
      client_email: parsed.client_email.trim(),
      private_key: parsed.private_key.trim(),
    };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Invalid format';
    throw new Error(`Failed to parse service account credentials: ${msg}`);
  }
}

export class ServiceAccountTokenProvider {
  private readonly credentials: ServiceAccountCredentials;
  private readonly fetchFn: FetchFunction;
  private readonly nowFn: () => number;

  private cachedToken: CachedToken | null = null;
  private inFlightPromise: Promise<string> | null = null;
  private privateKeyPromise: Promise<CryptoKey> | null = null;

  constructor(serviceAccountB64: string, options?: ServiceAccountAuthOptions) {
    this.credentials = parseServiceAccountB64(serviceAccountB64);
    this.fetchFn = options?.fetchFn ?? fetch;
    this.nowFn = options?.nowFn ?? Date.now;
  }

  /**
   * Özel anahtarı (PKCS8 PEM) Web Crypto CryptoKey nesnesine dönüştürür.
   */
  private async getCryptoKey(): Promise<CryptoKey> {
    if (!this.privateKeyPromise) {
      this.privateKeyPromise = (async () => {
        const pkcs8Bytes = pemToPkcs8Bytes(this.credentials.private_key);
        return crypto.subtle.importKey(
          'pkcs8',
          pkcs8Bytes,
          {
            name: 'RSASSA-PKCS1-v1_5',
            hash: 'SHA-256',
          },
          false,
          ['sign']
        );
      })();
    }
    return this.privateKeyPromise;
  }

  /**
   * Google OAuth2 için imzalı JWT bearer assertion üretir.
   */
  async createAssertionJwt(nowSec?: number): Promise<string> {
    const issuedAt = nowSec ?? Math.floor(this.nowFn() / 1000);
    const expiresAt = issuedAt + TOKEN_LIFETIME_SECONDS;

    const header = { alg: 'RS256', typ: 'JWT' };
    const payload = {
      iss: this.credentials.client_email,
      scope: GOOGLE_SCOPES,
      aud: GOOGLE_TOKEN_URL,
      iat: issuedAt,
      exp: expiresAt,
    };

    const headerB64 = utf8ToBase64Url(JSON.stringify(header));
    const payloadB64 = utf8ToBase64Url(JSON.stringify(payload));
    const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);

    const privateKey = await this.getCryptoKey();
    const signatureBytes = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, signedData);
    const signatureB64 = uint8ArrayToBase64Url(new Uint8Array(signatureBytes));

    return `${headerB64}.${payloadB64}.${signatureB64}`;
  }

  /**
   * Geçerli bir Google OAuth2 access_token döndürür.
   * Vadesinden 5 dakika öncesine kadar bellekte tutar.
   * Eşzamanlı çağrılar aynı uçuş isteğini paylaşır (single-flight).
   */
  async getAccessToken(): Promise<string> {
    const nowMs = this.nowFn();

    // 1. Önbellekte geçerli bir token var mı?
    if (this.cachedToken && nowMs < this.cachedToken.expiresAtMs) {
      return this.cachedToken.token;
    }

    // 2. Halihazırda devam eden bir istek var mı? (Single-flight)
    if (this.inFlightPromise) {
      return this.inFlightPromise;
    }

    this.inFlightPromise = (async () => {
      try {
        const assertion = await this.createAssertionJwt();
        const body = `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${encodeURIComponent(
          assertion
        )}`;

        const res = await this.fetchFn(GOOGLE_TOKEN_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body,
        });

        if (!res.ok) {
          throw new Error(`OAuth2 token exchange failed with HTTP status ${res.status}`);
        }

        const data = (await res.json()) as {
          access_token?: string;
          expires_in?: number;
        };

        if (typeof data.access_token !== 'string' || !data.access_token) {
          throw new Error('OAuth2 response did not contain access_token.');
        }

        const expiresIn =
          typeof data.expires_in === 'number' && data.expires_in > 0
            ? data.expires_in
            : TOKEN_LIFETIME_SECONDS;

        const currentNowMs = this.nowFn();
        const safeLifetimeMs = Math.max(60, expiresIn - EXPIRY_BUFFER_SECONDS) * 1000;

        this.cachedToken = {
          token: data.access_token,
          expiresAtMs: currentNowMs + safeLifetimeMs,
        };

        return data.access_token;
      } finally {
        this.inFlightPromise = null;
      }
    })();

    return this.inFlightPromise;
  }
}

