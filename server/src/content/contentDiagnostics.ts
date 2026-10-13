// İçerik Sağlayıcı Tanılama ve Güvenli Yapılandırılmış Günlükleme Modülü
// Gizli değişkenler, anahtarlar, jetonlar ve soru/cevap metinleri ASLA loglanmaz.

export type ContentErrorStage =
  | 'secret_missing'
  | 'secret_decode'
  | 'jwt_sign'
  | 'token_exchange'
  | 'rtdb_fetch'
  | 'parse';

export interface ContentErrorLogPayload {
  readonly event: 'content_error';
  readonly stage: ContentErrorStage;
  readonly status?: number;
  readonly errorName?: string;
  readonly code?: string;
  readonly detail: string;
  readonly causeCode?: string;
  readonly message?: string;
  readonly hasSecret?: boolean;
  readonly hasClientEmail?: boolean;
  readonly hasPrivateKey?: boolean;
  readonly isPemFormatValid?: boolean;
}

/** PEM başlık ve bitiş satırlarının biçimini kontrol eder (anahtar içeriğini incelemez). */
export function checkPemFormat(pem?: string): boolean {
  if (typeof pem !== 'string' || pem.trim().length === 0) return false;
  const hasBegin = /-----BEGIN[ A-Z0-9_-]+-----/.test(pem);
  const hasEnd = /-----END[ A-Z0-9_-]+-----/.test(pem);
  return hasBegin && hasEnd;
}

/** Base64 dizesinden UTF-8 metne dönüştürür. */
function safeBase64ToUtf8(b64: string): string {
  const binary = atob(b64.trim());
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

/**
 * Servis hesabı Base64 dizesini güvenle inceler.
 * Yalnızca boolean tanı bilgisi döner; anahtar, e-posta veya değer/uzunluk DÖNMEZ.
 */
export function inspectSecretB64(serviceAccountB64?: string): {
  readonly hasSecret: boolean;
  readonly hasClientEmail: boolean;
  readonly hasPrivateKey: boolean;
  readonly isPemFormatValid: boolean;
} {
  const hasSecret =
    typeof serviceAccountB64 === 'string' && serviceAccountB64.trim().length > 0;
  if (!hasSecret) {
    return {
      hasSecret: false,
      hasClientEmail: false,
      hasPrivateKey: false,
      isPemFormatValid: false,
    };
  }

  try {
    const jsonStr = safeBase64ToUtf8(serviceAccountB64);
    const parsed = JSON.parse(jsonStr) as Record<string, unknown>;

    const hasClientEmail =
      typeof parsed.client_email === 'string' &&
      parsed.client_email.trim().length > 0;
    const hasPrivateKey =
      typeof parsed.private_key === 'string' &&
      parsed.private_key.trim().length > 0;
    const isPemFormatValid = hasPrivateKey
      ? checkPemFormat(parsed.private_key as string)
      : false;

    return {
      hasSecret: true,
      hasClientEmail,
      hasPrivateKey,
      isPemFormatValid,
    };
  } catch {
    return {
      hasSecret: true,
      hasClientEmail: false,
      hasPrivateKey: false,
      isPemFormatValid: false,
    };
  }
}

/**
 * Hata detay metnini temizler ve en fazla 200 karakterle sınırlar.
 * URL sorgu parametreleri, e-postalar, JWT'ler ve uzun anahtar parçaları ayıklanır.
 */
export function sanitizeDetail(raw?: string): string {
  if (typeof raw !== 'string') return '';
  let clean = raw
    // URL sorgu parametrelerini kaldır (?access_token=... vb.)
    .replace(/\?[^ \t\r\n]+/g, '')
    // E-posta adreslerini maskele
    .replace(/[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+/g, '[REDACTED_EMAIL]')
    // JWT jetonlarını maskele
    .replace(/ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, '[REDACTED_JWT]')
    // Uzun base64 / hex bloklarını maskele
    .replace(/[A-Za-z0-9+/=]{30,}/g, '[REDACTED_KEY]')
    // Fazla boşlukları tek boşluğa indir
    .replace(/\s+/g, ' ')
    .trim();

  if (clean.length > 200) {
    clean = clean.slice(0, 200);
  }
  return clean;
}

/**
 * Hata mesajını temizler ve en fazla 120 karakterle sınırlar.
 * 40 ya da daha fazla ardışık [A-Za-z0-9_-] karakterini "[redacted]" ile değiştirir,
 * "Bearer ..." ve "access_token=..." kalıplarını siler, URL sorgularını arındırır.
 */
export function sanitizeErrorMessage(raw?: string): string {
  if (typeof raw !== 'string') return '';
  let clean = raw
    // "Bearer ..." kalıplarını sil
    .replace(/Bearer\s+[^\s]+/gi, '')
    // "access_token=..." kalıplarını sil
    .replace(/access_token=[^\s&]+/gi, '')
    // 40 ya da daha fazla ardışık [A-Za-z0-9_-] karakterini "[redacted]" ile değiştir
    .replace(/[A-Za-z0-9_-]{40,}/g, '[redacted]')
    // URL sorgu parametrelerini kaldır (?key=... vb.)
    .replace(/\?[^ \t\r\n]+/g, '')
    // Fazla boşlukları tek boşluğa indir
    .replace(/\s+/g, ' ')
    .trim();

  if (clean.length > 120) {
    clean = clean.slice(0, 120);
  }
  return clean;
}

/**
 * Hatadan cause.code veya code alanını güvenle çeker.
 * Yalnızca string ise döner (örn. ENOTFOUND, ECONNRESET, UND_ERR_CONNECT_TIMEOUT, ETIMEDOUT).
 */
export function extractCauseCode(err: unknown): string | undefined {
  if (typeof err !== 'object' || err === null) return undefined;

  // err.cause alanı (Undici / workerd / fetch cause)
  if ('cause' in err) {
    const cause = (err as Record<string, unknown>).cause;
    if (typeof cause === 'object' && cause !== null && 'code' in cause) {
      const code = (cause as Record<string, unknown>).code;
      if (typeof code === 'string' && code.trim().length > 0) {
        return code.trim();
      }
    }
    if (typeof cause === 'string' && cause.trim().length > 0) {
      return cause.trim();
    }
  }

  // err.code alanı
  if ('code' in err) {
    const code = (err as Record<string, unknown>).code;
    if (typeof code === 'string' && code.trim().length > 0) {
      return code.trim();
    }
  }

  return undefined;
}

/**
 * Hatadan hata mesajını ve varsa cause.message'ı çekip temizler.
 */
export function extractErrorMessage(err: unknown): string | undefined {
  if (err instanceof Error) {
    if (
      typeof err.cause === 'object' &&
      err.cause !== null &&
      'message' in err.cause &&
      typeof (err.cause as Record<string, unknown>).message === 'string'
    ) {
      const causeMsg = (err.cause as Record<string, unknown>).message as string;
      const combined = `${err.message} (${causeMsg})`;
      return sanitizeErrorMessage(combined);
    }
    return sanitizeErrorMessage(err.message);
  }
  if (typeof err === 'string') {
    return sanitizeErrorMessage(err);
  }
  return undefined;
}

// Spam önleme durumu (de-duplication)
let lastErrorSignature: string | null = null;
let lastErrorTimeMs = 0;
const DEDUPLICATION_WINDOW_MS = 10000; // 10 saniye içinde mükerrer log basma

/** Testler için spam önleme durumunu sıfırlar. */
export function resetContentErrorLogger(): void {
  lastErrorSignature = null;
  lastErrorTimeMs = 0;
}

/**
 * İçerik okuma hattındaki hatayı tek satırlık yapılandırılmış JSON olarak console.warn ile yazar.
 * Art arda gelen aynı hatayı spam yapmaz.
 */
export function logContentError(
  payload: ContentErrorLogPayload,
  warnFn: (msg: string) => void = (msg) => console.warn(msg),
  nowFn: () => number = () => Date.now()
): boolean {
  const sanitizedDetail = sanitizeDetail(payload.detail);

  const cleanPayload: ContentErrorLogPayload = {
    event: 'content_error',
    stage: payload.stage,
    ...(typeof payload.status === 'number' ? { status: payload.status } : {}),
    ...(payload.errorName ? { errorName: payload.errorName } : {}),
    ...(payload.code ? { code: sanitizeDetail(payload.code) } : {}),
    detail: sanitizedDetail,
    ...(payload.causeCode ? { causeCode: payload.causeCode.trim() } : {}),
    ...(payload.message ? { message: sanitizeErrorMessage(payload.message) } : {}),
    ...(typeof payload.hasSecret === 'boolean' ? { hasSecret: payload.hasSecret } : {}),
    ...(typeof payload.hasClientEmail === 'boolean'
      ? { hasClientEmail: payload.hasClientEmail }
      : {}),
    ...(typeof payload.hasPrivateKey === 'boolean'
      ? { hasPrivateKey: payload.hasPrivateKey }
      : {}),
    ...(typeof payload.isPemFormatValid === 'boolean'
      ? { isPemFormatValid: payload.isPemFormatValid }
      : {}),
  };

  const now = nowFn();
  const signature = `${cleanPayload.stage}:${cleanPayload.status ?? ''}:${cleanPayload.code ?? ''}:${cleanPayload.causeCode ?? ''}:${cleanPayload.detail}:${cleanPayload.message ?? ''}`;

  if (signature === lastErrorSignature && now - lastErrorTimeMs < DEDUPLICATION_WINDOW_MS) {
    return false;
  }

  lastErrorSignature = signature;
  lastErrorTimeMs = now;

  warnFn(JSON.stringify(cleanPayload));
  return true;
}

