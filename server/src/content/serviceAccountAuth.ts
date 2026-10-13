// Firebase Servis Hesabı OAuth2 Token Sağlayıcısı (Web Crypto)
import {
  inspectSecretB64,
  logContentError,
  extractCauseCode,
  extractErrorMessage,
} from './contentDiagnostics';

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
  readonly sleepFn?: (ms: number) => Promise<void>;
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
  const diag = inspectSecretB64(serviceAccountB64);
  try {
    let jsonStr: string;
    try {
      jsonStr = base64ToUtf8(serviceAccountB64);
    } catch {
      logContentError({
        event: 'content_error',
        stage: 'secret_decode',
        errorName: 'DecodeError',
        detail: 'Base64 decoding failed for service account secret',
        ...diag,
      });
      throw new Error('Failed to parse service account credentials: Base64 decoding failed');
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(jsonStr) as Record<string, unknown>;
    } catch {
      logContentError({
        event: 'content_error',
        stage: 'secret_decode',
        errorName: 'SyntaxError',
        detail: 'JSON parsing failed for service account secret',
        ...diag,
      });
      throw new Error('Failed to parse service account credentials: JSON parsing failed');
    }

    if (
      typeof parsed.client_email !== 'string' ||
      parsed.client_email.trim().length === 0 ||
      typeof parsed.private_key !== 'string' ||
      parsed.private_key.trim().length === 0
    ) {
      logContentError({
        event: 'content_error',
        stage: 'secret_decode',
        errorName: 'ValidationError',
        detail: 'Missing client_email or private_key in service account credentials',
        ...diag,
      });
      throw new Error('Missing client_email or private_key in service account credentials.');
    }

    return {
      client_email: parsed.client_email.trim(),
      private_key: parsed.private_key.trim(),
    };
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw err;
    }
    throw new Error('Failed to parse service account credentials');
  }
}

export class ServiceAccountTokenProvider {
  private readonly credentials: ServiceAccountCredentials;
  private readonly fetchFn: FetchFunction;
  private readonly nowFn: () => number;
  private readonly sleepFn: (ms: number) => Promise<void>;
  private readonly diagnosticFlags: {
    readonly hasSecret: boolean;
    readonly hasClientEmail: boolean;
    readonly hasPrivateKey: boolean;
    readonly isPemFormatValid: boolean;
  };

  private cachedToken: CachedToken | null = null;
  private inFlightPromise: Promise<string> | null = null;
  private privateKeyPromise: Promise<CryptoKey> | null = null;

  constructor(serviceAccountB64: string, options?: ServiceAccountAuthOptions) {
    this.diagnosticFlags = inspectSecretB64(serviceAccountB64);
    this.credentials = parseServiceAccountB64(serviceAccountB64);
    const injectedFetch = options?.fetchFn;
    this.fetchFn = injectedFetch
      ? ((url: string, init?: RequestInit) => injectedFetch(url, init))
      : ((url: string, init?: RequestInit) => fetch(url, init));

    const injectedNow = options?.nowFn;
    this.nowFn = injectedNow
      ? (() => injectedNow())
      : (() => Date.now());

    const injectedSleep = options?.sleepFn;
    this.sleepFn = injectedSleep
      ? ((ms: number) => injectedSleep(ms))
      : ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  }

  get diagnostics(): {
    readonly hasSecret: boolean;
    readonly hasClientEmail: boolean;
    readonly hasPrivateKey: boolean;
    readonly isPemFormatValid: boolean;
  } {
    return this.diagnosticFlags;
  }

  /**
   * Özel anahtarı (PKCS8 PEM) Web Crypto CryptoKey nesnesine dönüştürür.
   */
  private async getCryptoKey(): Promise<CryptoKey> {
    if (!this.privateKeyPromise) {
      this.privateKeyPromise = (async () => {
        try {
          const pkcs8Bytes = pemToPkcs8Bytes(this.credentials.private_key);
          return await crypto.subtle.importKey(
            'pkcs8',
            pkcs8Bytes,
            {
              name: 'RSASSA-PKCS1-v1_5',
              hash: 'SHA-256',
            },
            false,
            ['sign']
          );
        } catch (err: unknown) {
          logContentError({
            event: 'content_error',
            stage: 'jwt_sign',
            errorName: err instanceof Error ? err.name : 'CryptoKeyImportError',
            detail: 'Web Crypto PKCS8 private key import failed',
            ...this.diagnosticFlags,
          });
          throw err;
        }
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
    let signatureBytes: ArrayBuffer;
    try {
      signatureBytes = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, signedData);
    } catch (err: unknown) {
      logContentError({
        event: 'content_error',
        stage: 'jwt_sign',
        errorName: err instanceof Error ? err.name : 'CryptoSignError',
        detail: 'Web Crypto RSASSA-PKCS1-v1_5 signature generation failed',
        ...this.diagnosticFlags,
      });
      throw err;
    }
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
        const params = new URLSearchParams();
        params.set('grant_type', 'urn:ietf:params:oauth:grant-type:jwt-bearer');
        params.set('assertion', assertion);
        const body = params.toString();

        let lastFetchErr: unknown = null;
        let res: Response | null = null;

        for (let attempt = 1; attempt <= 2; attempt++) {
          try {
            res = await this.fetchFn(GOOGLE_TOKEN_URL, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                Accept: 'application/json',
              },
              body,
            });

            // 5xx ise ve ilk deneme ise 300 ms bekle ve yeniden dene
            if (res.status >= 500 && attempt === 1) {
              await this.sleepFn(300);
              continue;
            }

            // Başarılı (2xx), 4xx (yeniden denenmez) veya 2. denemedeki 5xx -> çık
            break;
          } catch (fetchErr: unknown) {
            lastFetchErr = fetchErr;
            if (attempt === 1) {
              await this.sleepFn(300);
              continue;
            }
          }
        }

        if (!res) {
          logContentError({
            event: 'content_error',
            stage: 'token_exchange',
            errorName: lastFetchErr instanceof Error ? lastFetchErr.name : 'NetworkError',
            detail: 'Network failure during OAuth2 token exchange request',
            causeCode: extractCauseCode(lastFetchErr),
            message: extractErrorMessage(lastFetchErr),
            ...this.diagnosticFlags,
          });
          throw lastFetchErr;
        }

        if (!res.ok) {
          let googleErrorCode: string | undefined;
          let googleErrorDesc: string | undefined;
          try {
            const errData = (await res.json()) as Record<string, unknown>;
            if (typeof errData.error === 'string') {
              googleErrorCode = errData.error;
            }
            if (typeof errData.error_description === 'string') {
              googleErrorDesc = errData.error_description;
            }
          } catch {
            // Yanıt JSON değilse hata kodunu okumayı atla
          }

          logContentError({
            event: 'content_error',
            stage: 'token_exchange',
            status: res.status,
            errorName: 'OAuthTokenError',
            code: googleErrorCode,
            detail:
              googleErrorDesc ||
              googleErrorCode ||
              `OAuth2 token exchange failed with HTTP status ${res.status}`,
            ...this.diagnosticFlags,
          });

          throw new Error(`OAuth2 token exchange failed with HTTP status ${res.status}`);
        }

        let data: { access_token?: string; expires_in?: number };
        try {
          data = (await res.json()) as { access_token?: string; expires_in?: number };
        } catch (jsonErr: unknown) {
          logContentError({
            event: 'content_error',
            stage: 'token_exchange',
            status: res.status,
            errorName: jsonErr instanceof Error ? jsonErr.name : 'SyntaxError',
            detail: 'Failed to parse OAuth2 token exchange response as JSON',
            ...this.diagnosticFlags,
          });
          throw jsonErr;
        }

        if (typeof data.access_token !== 'string' || !data.access_token) {
          logContentError({
            event: 'content_error',
            stage: 'token_exchange',
            status: res.status,
            errorName: 'OAuthTokenError',
            detail: 'OAuth2 response did not contain access_token',
            ...this.diagnosticFlags,
          });
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

