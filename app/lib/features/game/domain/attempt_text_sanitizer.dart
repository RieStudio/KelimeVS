// Saf Dart - Flutter veya Riverpod bağımlılığı yoktur.

/// GDD Bölüm 4.6: Serbest Metin Güvenliği
///
/// Deneme metni en fazla 40 karakterdir;
/// baştaki ve sondaki boşluklar silinir, ardışık boşluklar tek boşluğa indirilir.
abstract final class AttemptTextSanitizer {
  static const int maxLength = 40;

  /// Metni temizler:
  /// - Baştaki ve sondaki boşlukları siler (trim).
  /// - Birden fazla ardışık boşluğu tek boşluğa indirir.
  /// - En fazla 40 karaktere kırpar.
  static String sanitize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length > maxLength) {
      return collapsed.substring(0, maxLength);
    }
    return collapsed;
  }
}

