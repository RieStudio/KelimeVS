export interface AuthEnv {
  readonly ALLOW_DEV_AUTH?: string;
  readonly FIREBASE_PROJECT_ID?: string;
}

export interface JwkKey {
  readonly kid: string;
  readonly kty: string;
  readonly alg?: string;
  readonly n: string;
  readonly e: string;
  readonly use?: string;
}

export interface JwkResponse {
  readonly keys: readonly JwkKey[];
}

export interface KeyCache {
  readonly keys: Map<string, JwkKey>;
  readonly cryptoKeys: Map<string, CryptoKey>;
  expiresAtMs: number;
  lastFetchedAtMs: number;
}

export type FetchFunction = (url: string, init?: RequestInit) => Promise<Response>;

export interface VerifyTokenOptions {
  readonly nowMs?: number;
  readonly keyCache?: KeyCache;
  readonly fetchFn?: FetchFunction;
}

export const GOOGLE_JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

const CLOCK_SKEW_TOLERANCE_SECONDS = 60;
const REFETCH_RATE_LIMIT_MS = 60_000; // Bilinmeyen kid için dakikada en fazla 1 kez yeniden çek
const ERROR_BACKOFF_MS = 15_000; // Google JWK çekim hatası durumunda 15 saniye geri çekilme

export function createKeyCache(): KeyCache {
  return {
    keys: new Map<string, JwkKey>(),
    cryptoKeys: new Map<string, CryptoKey>(),
    expiresAtMs: 0,
    lastFetchedAtMs: 0,
  };
}

let defaultKeyCache: KeyCache = createKeyCache();

export function resetDefaultKeyCache(): void {
  defaultKeyCache = createKeyCache();
}

/** Base64URL dizesini Uint8Array baytlarına dönüştürür. */
export function base64UrlToUint8Array(str: string): Uint8Array {
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

/** Base64URL dizesini UTF-8 metne dönüştürür. */
export function base64UrlToUtf8(str: string): string {
  const bytes = base64UrlToUint8Array(str);
  return new TextDecoder().decode(bytes);
}

function parseCacheControlMaxAge(header: string | null): number {
  if (!header) return 3600;
  const match = header.match(/max-age=(\d+)/i);
  if (!match) return 3600;
  const parsed = parseInt(match[1], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 3600;
}

interface JwtHeader {
  readonly alg?: string;
  readonly kid?: string;
  readonly typ?: string;
}

interface JwtPayload {
  readonly aud?: string;
  readonly iss?: string;
  readonly sub?: string;
  readonly exp?: number;
  readonly iat?: number;
  readonly auth_time?: number;
  readonly firebase?: {
    readonly sign_in_provider?: string;
    readonly identities?: Record<string, unknown>;
  };
  readonly provider_id?: string;
}

export interface AuthContext {
  readonly uid: string;
  readonly isGuest: boolean;
  readonly provider: string;
}

/**
 * Google securetoken JWK anahtarlarını çeker veya önbellekten alır.
 */
async function getOrFetchKey(
  kid: string,
  cache: KeyCache,
  fetchFn: FetchFunction,
  nowMs: number
): Promise<CryptoKey | null> {
  // Önbellekte CryptoKey zaten hazır mı?
  const existingCryptoKey = cache.cryptoKeys.get(kid);
  if (existingCryptoKey && nowMs < cache.expiresAtMs) {
    return existingCryptoKey;
  }

  // Yeniden çekme gereksinimi kontrolü:
  // 1. Önbellek süresi dolmuşsa
  // 2. Önbellek boşsa
  // 3. kid önbellekte yoksa VE son çekmeden bu yana en az 60 sn geçmişse
  // 4. Son çekimden bu yana en az 15 sn hata geri çekilmesi geçmişse
  const isExpired = nowMs >= cache.expiresAtMs;
  const isEmpty = cache.keys.size === 0;
  const isUnknownKid = !cache.keys.has(kid);
  const canRefetchRateLimit = nowMs - cache.lastFetchedAtMs >= REFETCH_RATE_LIMIT_MS;
  const hasErrorBackoff = nowMs - cache.lastFetchedAtMs < ERROR_BACKOFF_MS;

  const shouldFetch =
    !hasErrorBackoff && (isExpired || isEmpty || (isUnknownKid && canRefetchRateLimit));

  if (shouldFetch) {
    try {
      const res = await fetchFn(GOOGLE_JWK_URL, {
        signal: AbortSignal.timeout(5000),
      });
      if (res.ok) {
        const data = (await res.json()) as JwkResponse;
        if (data && Array.isArray(data.keys)) {
          cache.keys.clear();
          cache.cryptoKeys.clear();

          const maxAge = parseCacheControlMaxAge(res.headers.get('Cache-Control'));
          cache.expiresAtMs = nowMs + maxAge * 1000;
          cache.lastFetchedAtMs = nowMs;

          for (const k of data.keys) {
            if (k.kid && k.kty === 'RSA') {
              cache.keys.set(k.kid, k);
            }
          }
        } else {
          cache.lastFetchedAtMs = nowMs;
        }
      } else {
        // Ağ HTTP hatası (5xx, 4xx) durumunda ~15 sn geri çekil
        cache.lastFetchedAtMs = nowMs;
      }
    } catch {
      // Ağ hatası veya zaman aşımı durumunda ~15 sn geri çekil
      cache.lastFetchedAtMs = nowMs;
    }
  }

  const jwk = cache.keys.get(kid);
  if (!jwk) {
    return null;
  }

  try {
    const importedKey = await crypto.subtle.importKey(
      'jwk',
      jwk,
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['verify']
    );
    cache.cryptoKeys.set(kid, importedKey);
    return importedKey;
  } catch {
    return null;
  }
}

/**
 * Firebase ID Token veya geliştirme token'ını doğrular ve detaylı kimlik bilgilerini döner.
 * Başarılı olursa { uid, isGuest, provider }, aksi halde `null` döner.
 */
export async function verifyAuth(
  token: string | null,
  env: AuthEnv,
  options?: VerifyTokenOptions
): Promise<AuthContext | null> {
  if (!token) return null;

  // 1. Geliştirme modu token'ı: dev:<uid>
  if (token.startsWith('dev:')) {
    if (env.ALLOW_DEV_AUTH === 'true') {
      const rawUid = token.slice(4).trim();
      if (!rawUid) return null;

      // Misafir simülasyonu: dev:guest:<uid> veya dev:guest-...
      const isGuest = rawUid.startsWith('guest:') || rawUid.startsWith('guest-');
      const uid = rawUid.startsWith('guest:') ? rawUid.slice(6).trim() : rawUid;
      if (!uid) return null;

      return {
        uid,
        isGuest,
        provider: isGuest ? 'anonymous' : 'dev',
      };
    }
    return null;
  }

  // 2. Firebase ID Token doğrulaması
  const projectId = env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId || projectId === 'REPLACE_WITH_FIREBASE_PROJECT_ID') {
    console.error('Firebase token verification rejected: FIREBASE_PROJECT_ID is not configured.');
    return null;
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    return null;
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  let header: JwtHeader;
  let payload: JwtPayload;

  try {
    header = JSON.parse(base64UrlToUtf8(headerB64)) as JwtHeader;
    payload = JSON.parse(base64UrlToUtf8(payloadB64)) as JwtPayload;
  } catch {
    return null;
  }

  // Başlık kontrolü: alg kesinlikle "RS256" olmalı (başka hiçbir algoritmaya, "none" veya "HS256" dahil, izin verilmez)
  if (header.alg !== 'RS256') {
    return null;
  }

  if (!header.kid || typeof header.kid !== 'string' || header.kid.trim().length === 0) {
    return null;
  }

  // Talepler (Claims) kontrolü
  if (payload.aud !== projectId) {
    return null;
  }

  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    return null;
  }

  if (typeof payload.sub !== 'string' || payload.sub.length === 0 || payload.sub.length > 128) {
    return null;
  }

  if (
    typeof payload.exp !== 'number' ||
    typeof payload.iat !== 'number' ||
    typeof payload.auth_time !== 'number'
  ) {
    return null;
  }

  const nowMs = options?.nowMs ?? Date.now();
  const nowSec = Math.floor(nowMs / 1000);

  // Süre kontrolleri (60 saniye saat sapması toleransı)
  if (nowSec > payload.exp + CLOCK_SKEW_TOLERANCE_SECONDS) {
    return null; // Süresi dolmuş
  }

  if (payload.iat - CLOCK_SKEW_TOLERANCE_SECONDS > nowSec) {
    return null; // iat gelecekte
  }

  if (payload.auth_time - CLOCK_SKEW_TOLERANCE_SECONDS > nowSec) {
    return null; // auth_time gelecekte
  }

  const keyCache = options?.keyCache ?? defaultKeyCache;
  const injectedFetch = options?.fetchFn;
  const fetchFn: FetchFunction = injectedFetch
    ? ((url: string, init?: RequestInit) => injectedFetch(url, init))
    : ((url: string, init?: RequestInit) => fetch(url, init));

  const cryptoKey = await getOrFetchKey(header.kid, keyCache, fetchFn, nowMs);
  if (!cryptoKey) {
    return null;
  }

  try {
    const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const signatureBytes = base64UrlToUint8Array(signatureB64);

    const isValid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      cryptoKey,
      signatureBytes,
      signedData
    );

    if (!isValid) return null;

    const signInProvider = payload.firebase?.sign_in_provider ?? payload.provider_id ?? 'unknown';
    const isGuest = signInProvider === 'anonymous';

    return {
      uid: payload.sub,
      isGuest,
      provider: signInProvider,
    };
  } catch {
    return null;
  }
}

/**
 * Firebase ID Token veya geliştirme token'ını doğrular.
 * Başarılı olursa kullanıcı kimliğini (`uid`), aksi halde `null` döner.
 */
export async function verifyToken(
  token: string | null,
  env: AuthEnv,
  options?: VerifyTokenOptions
): Promise<string | null> {
  const auth = await verifyAuth(token, env, options);
  return auth ? auth.uid : null;
}

/**
 * Gelen HTTP/WebSocket isteğinden tam kimlik ve misafirlik bilgilerini doğrular.
 */
export async function authenticateAuth(
  request: Request,
  env: AuthEnv,
  options?: VerifyTokenOptions
): Promise<AuthContext | null> {
  const url = new URL(request.url);
  const tokenParam = url.searchParams.get('token');

  if (tokenParam !== null) {
    // Üretim modunda ?token= sorgu parametresi doğrudan reddedilir
    if (env.ALLOW_DEV_AUTH !== 'true') {
      return null;
    }
    // Geliştirme modunda dahi sorgu parametresi yalnızca dev:<uid> için geçerlidir (Firebase jetonları için değil)
    if (!tokenParam.startsWith('dev:')) {
      return null;
    }
    return verifyAuth(tokenParam, env, options);
  }

  const authHeader = request.headers.get('Authorization');
  if (authHeader) {
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match) return null;
    const bearerToken = match[1].trim();
    if (!bearerToken) return null;
    return verifyAuth(bearerToken, env, options);
  }

  return null;
}

/**
 * Gelen HTTP/WebSocket isteğinden kimliği doğrular.
 * Geriye dönük uyumluluk için yalnızca `uid` döndürür.
 */
export async function authenticateRequest(
  request: Request,
  env: AuthEnv,
  options?: VerifyTokenOptions
): Promise<string | null> {
  const auth = await authenticateAuth(request, env, options);
  return auth ? auth.uid : null;
}
