// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

abstract final class TextNormalizer {
  static const Map<String, String> _trCharMap = {
    'İ': 'i',
    'I': 'ı',
  };

  static const Map<String, String> _accentMap = {
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

  static final RegExp _combiningMarksRegex = RegExp(r'[\u0300-\u036f]');
  static final RegExp _nonAlphaNumSpacesRegex = RegExp(r'[^a-z0-9\s+#]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  /// Hem kullanıcı girdisi hem de kayıtlı cevaplar için standart normalizasyon.
  ///
  /// a) Önce Türkçe harfleri elle eşle: 'İ' → 'i', 'I' → 'ı'. Sonra toLowerCase() uygula.
  /// b) Aksan katlama: ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u, â→a, î→i, û→u. Birleşik işaretleri sil.
  /// c) Harf, rakam ve boşluk dışındaki her karakteri boşluğa çevir.
  /// d) Ardışık boşlukları tek boşluğa indir, baştaki/sondaki boşlukları sil.
  static String normalize(String input) {
    if (input.isEmpty) return '';

    // a) Elle Türkçe eşleme ve ardından toLowerCase()
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      buffer.write(_trCharMap[char] ?? char);
    }
    String text = buffer.toString().toLowerCase();

    // b) Aksan katlama ve birleşik işaretleri temizleme
    final accentBuffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      accentBuffer.write(_accentMap[char] ?? char);
    }
    text = accentBuffer.toString().replaceAll(_combiningMarksRegex, '');

    // c) Harf, rakam ve boşluk harici karakterleri boşluğa dönüştür
    text = text.replaceAll(_nonAlphaNumSpacesRegex, ' ');

    // d) Ardışık boşlukları tek boşluğa indir ve kenar boşluklarını sil
    text = text.replaceAll(_whitespaceRegex, ' ').trim();

    return text;
  }
}

