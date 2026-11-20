// Saf TypeScript - Cloudflare Workers ve Vitest uyumlu
import { CONTAINS_WORDS, EXACT_WORDS, ALLOW_WORDS } from './nicknameBlocklist';

/**
 * Satır başına kelime içeren dizeyi veya dize dizisini temizler ve parse eder.
 * # ile başlayan satırları ve boş satırları yok sayar.
 */
export function parseWordList(source: readonly string[] | string): string[] {
  const lines = typeof source === 'string'
    ? source.split(/\r?\n/)
    : source;

  const result: string[] = [];
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    result.push(line);
  }
  return result;
}

const TR_LOWER_MAP: Record<string, string> = {
  'İ': 'i',
  'I': 'i',
  'ı': 'i',
};

const TR_ACCENT_MAP: Record<string, string> = {
  'ş': 's',
  'ğ': 'g',
  'ü': 'u',
  'ö': 'o',
  'ç': 'c',
  'â': 'a',
  'î': 'i',
  'û': 'u',
};

const LEET_MAP: Record<string, string> = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '9': 'g',
  '@': 'a',
  '$': 's',
  '!': 'i',
  '|': 'i',
  '+': 't',
};

// Ayraçlar, boşluklar, noktalama ve sıfır genişlikli karakterler
const SEPARATORS_AND_INVISIBLE_REGEX =
  /[\s._\-\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF\u00AD~`'"*^&()=[\]{}<>\/\\?,:;]/gu;

/**
 * Takma ad filtreleme için tekil normalizasyon fonksiyonu.
 *
 * 1. Unicode NFKC normalizasyonu
 * 2. Türkçe farkındalıklı küçük harf: İ, I, ı, i hepsi 'i'ye
 * 3. Türkçe karakterleri sadeleştir: ş->s, ğ->g, ü->u, ö->o, ç->c, ı->i
 * 4. Yaygın leetspeak ve sembol eşlemeleri:
 *    0->o, 1->i, 3->e, 4->a, 5->s, 7->t, 9->g, @->a, $->s, !->i, |->i, +->t
 * 5. Ayraç ve görünmez karakterleri at:
 *    boşluk, ., _, -, sıfır genişlikli karakterler
 * 6. Üst üste tekrarlanan harfleri teke indir (aaa -> a)
 */
export function normalizeForFilter(input: string): string {
  if (!input || input.length === 0) return '';

  // 1. Unicode NFKC
  let text = input.normalize('NFKC');

  // 2. Türkçe farkındalıklı küçük harf: İ/I/ı/i -> 'i'
  let lower = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    lower += TR_LOWER_MAP[ch] ?? ch;
  }
  text = lower.toLowerCase();

  // 3. Türkçe karakterleri sadeleştir
  let accentFolded = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    accentFolded += TR_ACCENT_MAP[ch] ?? ch;
  }
  text = accentFolded.replace(/[\u0300-\u036f]/g, '');

  // 4. Yaygın leetspeak ve sembol eşlemeleri
  let leetFolded = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    leetFolded += LEET_MAP[ch] ?? ch;
  }
  text = leetFolded;

  // 5. Ayraç ve görünmez karakterleri (boşluk, . _ - ve sıfır genişlikli karakterler) at
  text = text.replace(SEPARATORS_AND_INVISIBLE_REGEX, '');

  // 6. Üst üste tekrarlanan karakterleri teke indir (aaa -> a)
  text = text.replace(/(.)\1+/gu, '$1');

  return text;
}

// Önceden normalize edilmiş ve uzunluğa göre sıralanmış setler
function buildNormalizedList(words: readonly string[]): string[] {
  const parsed = parseWordList(words);
  const set = new Set<string>();
  for (const w of parsed) {
    const norm = normalizeForFilter(w);
    if (norm.length > 0) {
      set.add(norm);
    }
  }
  return Array.from(set);
}

const PREPARED_CONTAINS = buildNormalizedList(CONTAINS_WORDS);
const PREPARED_EXACT = new Set(buildNormalizedList(EXACT_WORDS));
const PREPARED_ALLOW = buildNormalizedList(ALLOW_WORDS).sort(
  (a, b) => b.length - a.length
);

export interface FilterOptions {
  readonly contains?: readonly string[];
  readonly exact?: readonly string[];
  readonly allow?: readonly string[];
}

/**
 * Verilen takma adın küfür/uygunsuz kelime filtresine takılıp takılmadığını denetler.
 *
 * @param nickname Kontrol edilecek takma ad
 * @param customOptions Özel liste testleri için opsiyonel listeler
 * @returns true ise engellenmeli, false ise serbest
 */
export function isNicknameBlocked(
  nickname: string,
  customOptions?: FilterOptions
): boolean {
  if (!nickname || typeof nickname !== 'string') {
    return false;
  }

  const allowList = customOptions?.allow
    ? buildNormalizedList(customOptions.allow).sort((a, b) => b.length - a.length)
    : PREPARED_ALLOW;

  const exactSet = customOptions?.exact
    ? new Set(buildNormalizedList(customOptions.exact))
    : PREPARED_EXACT;

  const containsList = customOptions?.contains
    ? buildNormalizedList(customOptions.contains)
    : PREPARED_CONTAINS;

  // 1. Ana normalizasyon
  const normalized = normalizeForFilter(nickname);
  if (normalized.length === 0) {
    return false;
  }

  // 2. Sondaki rakamlar atılmış normalizasyon varyantları (exact kontrolü için)
  // a) Ham metinden sondaki rakamları atıp normalize et (örn. 'got_99' -> 'got')
  const rawNoTrailingDigits = nickname.replace(/[\s\-_0-9]+$/, '');
  const normalizedNoTrailingDigits = normalizeForFilter(rawNoTrailingDigits);
  // b) Normalize edilmiş metinden sondaki rakamları at (eşleşmeyen 2, 6, 8 gibi rakamlar için)
  const normalizedTrailingStripped = normalized.replace(/\d+$/, '');

  // 3. Allow (Yanlış Pozitif) Maskeleme
  // Allow listesindeki kelimeler eşleşmeden önce maskelenir (yerine '*' konur).
  // Karakterlerin birleşip istenmeyen sahte kelime üretmesini önlemek için '*' ile ayrılır.
  let masked = normalized;
  let maskedNoTrailing = normalizedNoTrailingDigits;
  let maskedTrailingStripped = normalizedTrailingStripped;

  for (const allowWord of allowList) {
    if (allowWord.length === 0) continue;
    if (masked.includes(allowWord)) {
      masked = masked.replaceAll(allowWord, '*');
    }
    if (maskedNoTrailing.includes(allowWord)) {
      maskedNoTrailing = maskedNoTrailing.replaceAll(allowWord, '*');
    }
    if (maskedTrailingStripped.includes(allowWord)) {
      maskedTrailingStripped = maskedTrailingStripped.replaceAll(allowWord, '*');
    }
  }

  // Eğer tüm kelime izinli kelimelerden oluşuyorsa ('*', '***' vb.) engellenmez
  const nonMaskedChars = masked.replace(/\*/g, '');
  if (nonMaskedChars.length === 0) {
    return false;
  }

  // 4. Exact (Tam Eşleşme) Kontrolü
  // Takma adın tamamı veya sondaki rakamlar atıldıktan sonraki hali exact listesindeyse engellenir.
  // (Not: Maskelemeden önceki orijinal normalize edilmiş kök kontrol edilir, ancak maskelenmişse izin verilmiştir)
  if (
    exactSet.has(normalized) ||
    (normalizedNoTrailingDigits.length > 0 && exactSet.has(normalizedNoTrailingDigits)) ||
    (normalizedTrailingStripped.length > 0 && exactSet.has(normalizedTrailingStripped))
  ) {
    // Eğer bu kök allow listesinde tam olarak yer alıyorsa engelleme
    const isExplicitlyAllowed = allowList.some(
      (aw) =>
        aw === normalized ||
        aw === normalizedNoTrailingDigits ||
        aw === normalizedTrailingStripped
    );
    if (!isExplicitlyAllowed) {
      return true;
    }
  }

  // 5. Contains (İçerme) Kontrolü
  // Maskelenmiş metinde contains listesindeki köklerden herhangi biri geçiyor mu?
  for (const badWord of containsList) {
    if (badWord.length === 0) continue;
    if (masked.includes(badWord)) {
      return true;
    }
  }

  return false;
}
