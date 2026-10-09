// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

const TR_CHAR_MAP: Record<string, string> = {
  'İ': 'i',
  'I': 'ı',
};

const ACCENT_MAP: Record<string, string> = {
  'ç': 'c',
  'ğ': 'g',
  'ı': 'i',
  'ö': 'o',
  'ş': 's',
  'ü': 'u',
  'â': 'a',
  'î': 'i',
  'û': 'u',
};

const COMBINING_MARKS_REGEX = /[\u0300-\u036f]/g;
const NON_ALPHA_NUM_SPACES_REGEX = /[^a-z0-9\s+#]/gu;
const WHITESPACE_REGEX = /\s+/g;

/**
 * Hem kullanıcı girdisi hem de kayıtlı cevaplar için standart normalizasyon.
 *
 * a) Önce Türkçe harfleri elle eşle: 'İ' → 'i', 'I' → 'ı'. Sonra toLowerCase() uygula.
 * b) Aksan katlama: ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u, â→a, î→i, û→u. Birleşik işaretleri sil.
 * c) Harf, rakam, boşluk, '+' ve '#' dışındaki her karakteri boşluğa çevir.
 * d) Ardışık boşlukları tek boşluğa indir, baştaki/sondaki boşlukları sil.
 */
export function normalize(input: string): string {
  if (input.length === 0) return '';

  // a) Elle Türkçe eşleme ve ardından toLowerCase()
  let text = '';
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    text += TR_CHAR_MAP[char] ?? char;
  }
  text = text.toLowerCase();

  // b) Aksan katlama ve birleşik işaretleri temizleme
  let accentText = '';
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    accentText += ACCENT_MAP[char] ?? char;
  }
  text = accentText.replace(COMBINING_MARKS_REGEX, '');

  // c) Harf, rakam, boşluk, '+' ve '#' harici karakterleri boşluğa dönüştür
  text = text.replace(NON_ALPHA_NUM_SPACES_REGEX, ' ');

  // d) Ardışık boşlukları tek boşluğa indir ve kenar boşluklarını sil
  return text.replace(WHITESPACE_REGEX, ' ').trim();
}

