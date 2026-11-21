// Saf TypeScript / JavaScript - Harici bağımlılık yoktur. Cloudflare Workers ve Vitest uyumludur.

import { normalizeForFilter, parseWordList } from './nicknameFilter';
import {
  ALLOW_WORDS,
  EXACT_WORDS,
  CONTAINS_WORDS,
} from './nicknameBlocklist';

// Module düzeyinde bir defa normalize edilen ve hafızada tutulan listeler (yüksek performans)
const PREPARED_ALLOW: readonly string[] = parseWordList(ALLOW_WORDS)
  .map((w) => normalizeForFilter(w))
  .filter((w) => w.length > 0)
  .sort((a, b) => b.length - a.length);

const PREPARED_EXACT: ReadonlySet<string> = new Set(
  parseWordList(EXACT_WORDS)
    .map((w) => normalizeForFilter(w))
    .filter((w) => w.length > 0)
);

const PREPARED_CONTAINS: readonly string[] = parseWordList(CONTAINS_WORDS)
  .map((w) => normalizeForFilter(w))
  .filter((w) => w.length >= 3)
  .sort((a, b) => b.length - a.length);

/**
 * Verilen tekil kelime veya kök adayının küfür/hakaret/uygunsuzluk listelerinde
 * yer alıp almadığını denetler.
 *
 * Kurallar:
 * 1. Allow listesi: Masum kelimeler (örn. 'kemal', 'siklamen', 'tamam', 'finnigan')
 *    önce metinden elenir.
 * 2. Exact listesi: Tam kelime veya sondaki rakamlar atılmış hali exact listesinde
 *    varsa engellenir.
 * 3. Contains listesi: Normalleştirilmiş kelimenin içinde güçlü küfür kökleri
 *    varsa engellenir.
 */
export function isWordInappropriate(candidate: string): boolean {
  if (!candidate || candidate.length === 0) return false;

  // Ondalıklı / sürüm numaraları (örn. 3.1, 8.1, 2.0) küfür değildir ve korunur
  if (/^\d+(?:\.\d+)+$/.test(candidate.trim())) {
    return false;
  }

  // 1. Ana normalizasyon
  const norm = normalizeForFilter(candidate);
  if (!norm) return false;

  // 2. Sondaki rakamlar atılmış normalizasyon (leetspeak rakamları 'g', 'o', 'i' olmadan önce)
  const rawNoTrailingDigits = candidate.replace(/[\s\-_0-9]+$/, '');
  const normNoTrailingDigits =
    rawNoTrailingDigits.length > 0 && rawNoTrailingDigits !== candidate
      ? normalizeForFilter(rawNoTrailingDigits)
      : norm;

  // 3. Allow Listesi Kontrolü (maskele / geç)
  let masked = norm;
  let maskedNoTrailing = normNoTrailingDigits;

  for (const normAllow of PREPARED_ALLOW) {
    if (masked.includes(normAllow)) {
      masked = masked.split(normAllow).join(' ');
    }
    if (maskedNoTrailing.includes(normAllow)) {
      maskedNoTrailing = maskedNoTrailing.split(normAllow).join(' ');
    }
  }

  const cleanNorm = masked.replace(/\s+/g, '');
  const cleanNoTrailing = maskedNoTrailing.replace(/\s+/g, '');

  if (!cleanNorm && !cleanNoTrailing) {
    return false;
  }

  // 4. Exact Listesi Kontrolü (O(1) Set lookup)
  if (cleanNorm && PREPARED_EXACT.has(cleanNorm)) {
    return true;
  }
  if (cleanNoTrailing && PREPARED_EXACT.has(cleanNoTrailing)) {
    return true;
  }

  // 5. Contains Listesi Kontrolü
  for (const normContains of PREPARED_CONTAINS) {
    if (cleanNorm.includes(normContains) || cleanNoTrailing.includes(normContains)) {
      return true;
    }
  }

  return false;
}

/**
 * Bir kelimeyi "ilk harf + yıldızlar" biçiminde maskeler.
 * - İlk Unicode karakterinin (grapheme) büyüklüğü ve Türkçe karakter özelliği
 *   (Ş, İ, ı, ç, ö, ü, ğ vb.) korunur.
 * - Geriye kalan tüm karakterler '*' ile değiştirilir (toplam uzunluk korunur).
 * - Tek karakterliyse '*' döner.
 */
export function maskSingleWord(word: string): string {
  const graphemes = Array.from(word);
  if (graphemes.length === 0) return '';
  if (graphemes.length === 1) return '*';
  return graphemes[0] + '*'.repeat(graphemes.length - 1);
}

// Spaced single-letter regex: örn. "s i k", "o . r . o . s . p . u" (yalnızca harfler; rakam kombinasyonları değil)
const SPACED_SINGLE_LETTER_REGEX =
  /(?:(?<=^|[\s\p{P}\p{S}])\p{L}(?:[\s._\-\u200B-\u200D\uFEFF]+\p{L})+)(?=[\s\p{P}\p{S}]|$)/gu;

/**
 * Metindeki uygunsuz kelimeleri "ilk harf + yıldızlar" olarak maskeler.
 * - Metin sözcük sınırlarına göre incelenir (cümle içindeki masum kelimeler ve
 *   ayraçlar korunur).
 * - Art arda gelen tek harfli sözcükler ("s i k", "o . r . o . s . p . u")
 *   birleştirilerek kontrol edilir ve uygunsuzsa ilgili aralık maskelenir.
 * - Kelimeye bitişik rakam/semboller maskeye dahil edilir.
 * - Boş/uzun metinlerde güvenlidir ve hata fırlatmaz.
 */
export function maskInappropriateText(text: string): string {
  if (!text || typeof text !== 'string') {
    return '';
  }

  // Çok uzun metinlerde (örn. > 5000 karakter) bellek/regex güvenliği için hızlı kestirme
  // 1. Adım: Art arda gelen TEK HARFLİ aralıklı yazımları (örn. "s i k", "o . r . o . s . p . u")
  // yakala ve uygunsuzsa o aralığı tek parça maskele.
  let processed = text;
  if (text.length <= 5000) {
    processed = text.replace(SPACED_SINGLE_LETTER_REGEX, (match) => {
      if (isWordInappropriate(match)) {
        return maskSingleWord(match);
      }
      return match;
    });
  }

  // 2. Adım: Boşluklara göre tokenize et
  const tokens = processed.split(/(\s+)/);

  return tokens
    .map((token) => {
      if (/^\s+$/.test(token)) {
        return token;
      }

      // Sözcüğün tamamını kontrol et (örn. 'orospu', 'sik123', 'p!c')
      if (isWordInappropriate(token)) {
        return maskSingleWord(token);
      }

      // Cümle sonu/başı noktalama işaretlerini (örn. 'orospu,' veya '"orospu"') ayırarak kontrol et
      const punctMatch = token.match(
        /^([\p{P}\p{S}]*)([\p{L}\p{N}\p{P}\p{S}]+?)([\p{P}\p{S}]*)$/u
      );
      if (punctMatch) {
        const [, lead, core, trail] = punctMatch;
        if (core && isWordInappropriate(core)) {
          return lead + maskSingleWord(core) + trail;
        }
      }

      return token;
    })
    .join('');
}
