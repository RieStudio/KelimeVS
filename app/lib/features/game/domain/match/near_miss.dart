// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'dart:math' as math;

abstract final class NearMissCalculator {
  /// Hedef kelime uzunluğuna göre izin verilen maksimum Damerau-Levenshtein düzenleme mesafesi:
  /// - 3 harf ve altı: kapalı (0 tolerans)
  /// - 4 - 8 harf: 1 düzenleme
  /// - 9+ harf: 2 düzenleme
  static int maxAllowedDistance(int targetLength) {
    if (targetLength <= 3) return 0;
    if (targetLength <= 8) return 1;
    return 2;
  }

  /// İki normalleştirilmiş metin arasındaki Damerau-Levenshtein (Optimal String Alignment) mesafesi:
  /// Ekleme, silme, değiştirme ve komşu iki karakterin yer değiştirmesi (transposition) 1 maliyetindedir.
  static int distance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final m = s1.length;
    final n = s2.length;

    // (m + 1) x (n + 1) matrisi
    final d = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (int i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

        d[i][j] = math.min(
          d[i - 1][j] + 1, // deletion
          math.min(
            d[i][j - 1] + 1, // insertion
            d[i - 1][j - 1] + cost, // substitution
          ),
        );

        // Komşu iki karakterin yer değiştirmesi (transposition)
        if (i > 1 &&
            j > 1 &&
            s1[i - 1] == s2[j - 2] &&
            s1[i - 2] == s2[j - 1]) {
          d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }

    return d[m][n];
  }

  /// Girdinin, henüz söylenmemiş cevapların alias'larından birine
  /// izin verilen eşik sınırlarında yakın olup olmadığını kontrol eder.
  ///
  /// Güvenlik gereği hangi cevaba yakın olduğu bilgisi ASLA döndürülmez.
  static bool isNearMiss({
    required String normalizedInput,
    required Iterable<List<String>> unusedAnswerAliases,
  }) {
    if (normalizedInput.isEmpty) return false;

    for (final aliases in unusedAnswerAliases) {
      for (final alias in aliases) {
        if (alias.isEmpty) continue;

        final threshold = maxAllowedDistance(alias.length);
        if (threshold <= 0) continue;

        final dist = distance(normalizedInput, alias);
        if (dist > 0 && dist <= threshold) {
          return true;
        }
      }
    }

    return false;
  }
}

