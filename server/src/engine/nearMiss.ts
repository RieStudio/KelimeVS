// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

/**
 * Hedef kelime uzunluğuna göre izin verilen maksimum Damerau-Levenshtein düzenleme mesafesi:
 * - 3 harf ve altı: kapalı (0 tolerans)
 * - 4 - 8 harf: 1 düzenleme
 * - 9+ harf: 2 düzenleme
 */
export function maxAllowedDistance(targetLength: number): number {
  if (targetLength <= 3) return 0;
  if (targetLength <= 8) return 1;
  return 2;
}

/**
 * İki normalleştirilmiş metin arasındaki Damerau-Levenshtein (Optimal String Alignment) mesafesi:
 * Ekleme, silme, değiştirme ve komşu iki karakterin yer değiştirmesi (transposition) 1 maliyetindedir.
 */
export function distance(s1: string, s2: string): number {
  if (s1 === s2) return 0;
  if (s1.length === 0) return s2.length;
  if (s2.length === 0) return s1.length;

  const m = s1.length;
  const n = s2.length;

  // (m + 1) x (n + 1) matrisi
  const d: number[][] = Array.from({ length: m + 1 }, () => new Array<number>(n + 1).fill(0));

  for (let i = 0; i <= m; i++) {
    d[i][0] = i;
  }
  for (let j = 0; j <= n; j++) {
    d[0][j] = j;
  }

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = s1[i - 1] === s2[j - 1] ? 0 : 1;

      d[i][j] = Math.min(
        d[i - 1][j] + 1, // deletion
        d[i][j - 1] + 1, // insertion
        d[i - 1][j - 1] + cost // substitution
      );

      // Komşu iki karakterin yer değiştirmesi (transposition)
      if (
        i > 1 &&
        j > 1 &&
        s1[i - 1] === s2[j - 2] &&
        s1[i - 2] === s2[j - 1]
      ) {
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }

  return d[m][n];
}

/**
 * Girdinin, henüz söylenmemiş cevapların alias'larından birine
 * izin verilen eşik sınırlarında yakın olup olmadığını kontrol eder.
 *
 * Güvenlik gereği hangi cevaba yakın olduğu bilgisi ASLA döndürülmez.
 */
export function isNearMiss(
  normalizedInput: string,
  unusedAnswerAliases: Iterable<readonly string[] | string[]>
): boolean {
  if (normalizedInput.length === 0) return false;

  for (const aliases of unusedAnswerAliases) {
    for (const alias of aliases) {
      if (alias.length === 0) continue;

      const threshold = maxAllowedDistance(alias.length);
      if (threshold <= 0) continue;

      const dist = distance(normalizedInput, alias);
      if (dist > 0 && dist <= threshold) {
        return true;
      }
    }
  }

  return false;
}

