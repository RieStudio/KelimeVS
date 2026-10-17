// Saf TypeScript - Harici ağ bağımlılığı yoktur.
import { normalize } from './normalizer';
import { PROFANITY_WORDS } from './profanityWords';

export interface NicknameValidationResult {
  readonly isValid: boolean;
  readonly normalized: string | null;
}

const ALLOWED_CHARS_REGEX = /^[a-zA-Z0-9_ çÇğĞıIİiöÖşŞüÜ]+$/;

export function validateNickname(raw: unknown): NicknameValidationResult {
  if (typeof raw !== 'string') {
    return { isValid: false, normalized: null };
  }

  // 1. Başta/sonda boşluk sil ve ardışık boşlukları tek boşluğa indir
  const trimmed = raw.trim().replace(/\s+/g, ' ');

  // 2. 3–16 karakter sınırı
  if (trimmed.length < 3 || trimmed.length > 16) {
    return { isValid: false, normalized: null };
  }

  // 3. İzin verilen karakterler (Türkçe harfler, rakamlar, boşluk, alt çizgi)
  if (!ALLOWED_CHARS_REGEX.test(trimmed)) {
    return { isValid: false, normalized: null };
  }

  // 4. Küfür ve uygunsuz kelime kontrolü (Türkçe aksan normalizasyonlu)
  const normalizedText = normalize(trimmed);
  for (const badWord of PROFANITY_WORDS) {
    if (normalizedText.includes(badWord)) {
      return { isValid: false, normalized: null };
    }
  }

  return { isValid: true, normalized: trimmed };
}

