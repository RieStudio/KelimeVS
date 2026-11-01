// Saf TypeScript - Harici ağ bağımlılığı yoktur.
import { normalize } from './normalizer';
import { PROFANITY_WORDS } from './profanityWords';

export interface NicknameValidationResult {
  readonly isValid: boolean;
  readonly normalized: string | null;
  readonly error?: 'invalid_length' | 'invalid_chars' | 'profanity' | 'reserved';
  readonly errorMessage?: string;
}

const ALLOWED_CHARS_REGEX = /^[a-zA-Z0-9_ çÇğĞıIİiöÖşŞüÜ]+$/;

export const RESERVED_NICKNAMES: readonly string[] = [
  'admin',
  'administrator',
  'moderator',
  'sistem',
  'system',
  'destek',
  'support',
  'kelimevs',
  'kelimego',
  'riestudio',
  'yetkili',
  'official',
  'resmi',
];

export function isReservedNickname(raw: string): boolean {
  const normalized = normalize(raw);
  const stripped = normalized.replace(/[^a-z0-9]/g, '');

  for (const reserved of RESERVED_NICKNAMES) {
    if (stripped.includes(reserved)) {
      return true;
    }
  }
  return false;
}

export function validateNickname(raw: unknown): NicknameValidationResult {
  if (typeof raw !== 'string') {
    return { isValid: false, normalized: null };
  }

  // 1. Başta/sonda boşluk sil ve ardışık boşlukları tek boşluğa indir
  const trimmed = raw.trim().replace(/\s+/g, ' ');

  // 2. 3–16 karakter sınırı
  if (trimmed.length < 3 || trimmed.length > 16) {
    return {
      isValid: false,
      normalized: null,
      error: 'invalid_length',
      errorMessage: 'Takma ad 3 ile 16 karakter arasında olmalıdır.',
    };
  }

  // 3. İzin verilen karakterler (Türkçe harfler, rakamlar, boşluk, alt çizgi)
  if (!ALLOWED_CHARS_REGEX.test(trimmed)) {
    return {
      isValid: false,
      normalized: null,
      error: 'invalid_chars',
      errorMessage: 'Yalnızca harf, rakam, boşluk ve alt çizgi (_) kullanabilirsin.',
    };
  }

  // 4. Yasaklı / Sistem rezervli unvan kontrolü (Normalizasyonlu ve boşluk/özel karakter dayanıklı)
  if (isReservedNickname(trimmed)) {
    return {
      isValid: false,
      normalized: null,
      error: 'reserved',
      errorMessage: 'Bu takma ad sistem tarafından ayrılmıştır, lütfen başka bir ad seçin.',
    };
  }

  // 5. Küfür ve uygunsuz kelime kontrolü (Türkçe aksan normalizasyonlu)
  const normalizedText = normalize(trimmed);
  for (const badWord of PROFANITY_WORDS) {
    if (normalizedText.includes(badWord)) {
      return {
        isValid: false,
        normalized: null,
        error: 'profanity',
        errorMessage: 'Bu takma ad uygunsuz ifadeler içeriyor.',
      };
    }
  }

  return { isValid: true, normalized: trimmed };
}

