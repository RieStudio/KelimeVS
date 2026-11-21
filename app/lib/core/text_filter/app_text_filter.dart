// Saf Dart - Harici paket bağımlılığı yoktur (Flutter standard characters kütüphanesi kullanılır).
// Sunucu textMasker ve nicknameFilter ile birebir parite sağlar.

import 'dart:convert';
import 'dart:io';
import 'package:characters/characters.dart';
import '../../features/game/domain/text_filter.dart';

const Map<String, String> _trLowerMap = {
  'İ': 'i',
  'I': 'i',
  'ı': 'i',
};

const Map<String, String> _trAccentMap = {
  'ş': 's',
  'ğ': 'g',
  'ü': 'u',
  'ö': 'o',
  'ç': 'c',
  'â': 'a',
  'î': 'i',
  'û': 'u',
  // Yaygın Latin aksanları (NFKC katlama desteği)
  'à': 'a',
  'á': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ñ': 'n',
};

const Map<String, String> _leetMap = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '9': 'g',
  '@': 'a',
  '\$': 's',
  '!': 'i',
  '|': 'i',
  '+': 't',
};

// Ayraçlar, boşluklar, noktalama ve sıfır genişlikli karakterler
final RegExp _separatorsAndInvisibleRegex = RegExp(
  r"""[\s._\-\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF\u00AD~`'"*^&()=[\]{}<>\/\\?,:;]""",
  unicode: true,
);

final RegExp _combiningMarksRegex = RegExp(r'[\u0300-\u036f]');
final RegExp _repeatedCharsRegex = RegExp(r'(.)\1+');
final RegExp _hasLetterRegex = RegExp(r'\p{L}', unicode: true);
final RegExp _trailingDigitsRegex = RegExp(r'[\s\-_0-9]+$');
final RegExp _whitespaceRegex = RegExp(r'\s+');
final RegExp _allWhitespaceRegex = RegExp(r'^\s+$');
final RegExp _tokenSplitRegex = RegExp(r'\S+|\s+');
final RegExp _onlyDigitsRegex = RegExp(r'^\d+$');

final RegExp _punctuationEnclosingRegex = RegExp(
  r'^([\p{P}\p{S}]*)([\p{L}\p{N}\p{P}\p{S}]+?)([\p{P}\p{S}]*)$',
  unicode: true,
);

// Spaced single-letter regex: örn. "s i k", "o . r . o . s . p . u" (yalnızca harfler)
final RegExp _spacedSingleLetterRegex = RegExp(
  r'(?:(?<=^|[\s\p{P}\p{S}])\p{L}(?:[\s._\-\u200B-\u200D\uFEFF]+\p{L})+)(?=[\s\p{P}\p{S}]|$)',
  unicode: true,
);

/// Unicode NFKC benzeri uyumluluk katlama fonksiyonu (harici paket gerektirmez).
/// - Tam genişlikli Latin harfleri, rakamlar ve semboller (0xFF01 - 0xFF5E) -> standart ASCII
/// - Tam genişlikli boşluk (0x3000) -> normal boşluk
/// - Yaygın ligatürler (ﬀ, ﬁ, ﬂ, ﬃ, ﬄ, ﬅ, ﬆ)
/// - Daire içine alınmış harf ve rakamlar (①-⑨, ⓪, Ⓐ-Ⓩ, ⓐ-ⓩ)
/// - Üst/alt simgeler (¹, ², ³, ⁰, ⁴-⁹, ₀-₉)
String foldNfkcCompatibility(String input) {
  if (input.isEmpty) return input;
  final buffer = StringBuffer();
  for (final codeUnit in input.runes) {
    // 1. Tam genişlikli ASCII (0xFF01 - 0xFF5E: ！.. ～)
    if (codeUnit >= 0xFF01 && codeUnit <= 0xFF5E) {
      buffer.writeCharCode(codeUnit - 0xFEE0);
      continue;
    }
    // 2. Tam genişlikli boşluk
    if (codeUnit == 0x3000) {
      buffer.write(' ');
      continue;
    }
    // 3. Ligatürler
    if (codeUnit >= 0xFB00 && codeUnit <= 0xFB06) {
      switch (codeUnit) {
        case 0xFB00:
          buffer.write('ff');
          break;
        case 0xFB01:
          buffer.write('fi');
          break;
        case 0xFB02:
          buffer.write('fl');
          break;
        case 0xFB03:
          buffer.write('ffi');
          break;
        case 0xFB04:
          buffer.write('ffl');
          break;
        case 0xFB05:
          buffer.write('ft');
          break;
        case 0xFB06:
          buffer.write('st');
          break;
      }
      continue;
    }
    // 4. Daire içine alınmış rakamlar
    if (codeUnit == 0x24EA) {
      buffer.write('0');
      continue;
    }
    if (codeUnit >= 0x2460 && codeUnit <= 0x2468) {
      buffer.write(String.fromCharCode(0x31 + (codeUnit - 0x2460)));
      continue;
    }
    // 5. Daire içine alınmış harfler
    if (codeUnit >= 0x24B6 && codeUnit <= 0x24CF) {
      buffer.write(String.fromCharCode(0x41 + (codeUnit - 0x24B6)));
      continue;
    }
    if (codeUnit >= 0x24D0 && codeUnit <= 0x24E9) {
      buffer.write(String.fromCharCode(0x61 + (codeUnit - 0x24D0)));
      continue;
    }
    // 6. Üst simgeler
    if (codeUnit == 0x00B9) {
      buffer.write('1');
      continue;
    }
    if (codeUnit == 0x00B2) {
      buffer.write('2');
      continue;
    }
    if (codeUnit == 0x00B3) {
      buffer.write('3');
      continue;
    }
    if (codeUnit == 0x2070) {
      buffer.write('0');
      continue;
    }
    if (codeUnit >= 0x2074 && codeUnit <= 0x2079) {
      buffer.write(String.fromCharCode(0x34 + (codeUnit - 0x2074)));
      continue;
    }
    // 7. Alt simgeler
    if (codeUnit >= 0x2080 && codeUnit <= 0x2089) {
      buffer.write(String.fromCharCode(0x30 + (codeUnit - 0x2080)));
      continue;
    }
    // 8. Diğer özel ligatür/karakterler
    if (codeUnit == 0x00DF) {
      buffer.write('ss');
      continue;
    }
    if (codeUnit == 0x00E6) {
      buffer.write('ae');
      continue;
    }
    if (codeUnit == 0x0153) {
      buffer.write('oe');
      continue;
    }

    buffer.writeCharCode(codeUnit);
  }
  return buffer.toString();
}

/// Sunucu normalizeForFilter ile birebir parite sağlayan normalizasyon fonksiyonu.
String normalizeForFilter(String input) {
  if (input.isEmpty) return '';

  // 1. Unicode NFKC katlama
  var text = foldNfkcCompatibility(input);

  // 2. Türkçe farkındalıklı küçük harf: İ/I/ı/i -> 'i'
  final lowerBuffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    lowerBuffer.write(_trLowerMap[ch] ?? ch);
  }
  text = lowerBuffer.toString().toLowerCase();

  // 3. Türkçe karakter ve aksan sadeleştirme
  final accentBuffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    accentBuffer.write(_trAccentMap[ch] ?? ch);
  }
  text = accentBuffer.toString().replaceAll(_combiningMarksRegex, '');

  // 4. Yaygın leetspeak ve sembol eşlemeleri
  final leetBuffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    leetBuffer.write(_leetMap[ch] ?? ch);
  }
  text = leetBuffer.toString();

  // 5. Ayraç ve görünmez karakterleri at
  text = text.replaceAll(_separatorsAndInvisibleRegex, '');

  // 6. Üst üste tekrarlanan karakterleri teke indir (aaa -> a)
  text = text.replaceAllMapped(_repeatedCharsRegex, (m) => m[1]!);

  return text;
}

/// Kelimeyi "ilk harf + yıldızlar" biçiminde maskeler.
String maskSingleWord(String word) {
  final chars = word.characters.toList();
  if (chars.isEmpty) return '';
  if (chars.length == 1) return '*';
  return chars.first + ('*' * (chars.length - 1));
}

/// İstemci tarafı maç içi metin maskeleyici (TextFilter implementasyonu).
class AppTextFilter implements TextFilter {
  final List<String> contains;
  final Set<String> exact;
  final List<String> allow;

  final List<String> _preparedContains;
  final Set<String> _preparedExact;
  final List<String> _preparedAllow;

  AppTextFilter({
    required this.contains,
    required this.exact,
    required this.allow,
  })  : _preparedContains = contains
            .map((w) => normalizeForFilter(w))
            .where((w) => w.length >= 3)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length)),
        _preparedExact = exact
            .where((w) => !_onlyDigitsRegex.hasMatch(w.trim()))
            .map((w) => normalizeForFilter(w))
            .where((w) => w.isNotEmpty)
            .toSet(),
        _preparedAllow = allow
            .map((w) => normalizeForFilter(w))
            .where((w) => w.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));

  factory AppTextFilter.fromJson(Map<String, dynamic> json) {
    final containsList = (json['contains'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final exactList = (json['exact'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toSet() ??
        const <String>{};
    final allowList = (json['allow'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    return AppTextFilter(
      contains: containsList,
      exact: exactList,
      allow: allowList,
    );
  }

  factory AppTextFilter.fromJsonString(String jsonString) {
    final dynamic decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz blocklist JSON biçimi');
    }
    return AppTextFilter.fromJson(decoded);
  }

  static AppTextFilter? _instance;

  /// Singleton örneğe erişim. Önceden init() çağrılmadıysa dosya sisteminden
  /// yüklemeyi dener (test ve çalışma zamanı ortamları için).
  static AppTextFilter get instance {
    if (_instance != null) return _instance!;
    for (final path in [
      'assets/text_filter/blocklist.json',
      'app/assets/text_filter/blocklist.json',
    ]) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          _instance = AppTextFilter.fromJsonString(file.readAsStringSync());
          return _instance!;
        }
      } catch (_) {}
    }
    // Geriye dönük güvenlik: dosya bulunamazsa boş liste ile başlat
    _instance = AppTextFilter(
      contains: const [],
      exact: const {},
      allow: const [],
    );
    return _instance!;
  }

  /// Uygulama başlangıcında (main) asset JSON içeriğiyle başlatır.
  static void init(String jsonString) {
    _instance = AppTextFilter.fromJsonString(jsonString);
  }

  /// Test temizliği için singleton'ı sıfırlar.
  static void reset() {
    _instance = null;
  }

  /// Verilen tekil kelimenin uygunsuz içerik olup olmadığını denetler.
  bool isWordInappropriate(String candidate) {
    if (candidate.isEmpty) return false;

    // Yalnızca rakamlardan ve noktalama/ayraç işaretlerinden oluşan sözcükler muaftır
    if (!_hasLetterRegex.hasMatch(candidate)) {
      return false;
    }

    // 1. Ana normalizasyon
    final norm = normalizeForFilter(candidate);
    if (norm.isEmpty) return false;

    // 2. Sondaki rakamlar atılmış normalizasyon
    final rawNoTrailingDigits = candidate.replaceAll(_trailingDigitsRegex, '');
    final normNoTrailingDigits =
        rawNoTrailingDigits.isNotEmpty && rawNoTrailingDigits != candidate
            ? normalizeForFilter(rawNoTrailingDigits)
            : norm;

    // 3. Allow Listesi Kontrolü (maskele / geç)
    String masked = norm;
    String maskedNoTrailing = normNoTrailingDigits;

    for (final normAllow in _preparedAllow) {
      if (masked.contains(normAllow)) {
        masked = masked.split(normAllow).join(' ');
      }
      if (maskedNoTrailing.contains(normAllow)) {
        maskedNoTrailing = maskedNoTrailing.split(normAllow).join(' ');
      }
    }

    final cleanNorm = masked.replaceAll(_whitespaceRegex, '');
    final cleanNoTrailing = maskedNoTrailing.replaceAll(_whitespaceRegex, '');

    if (cleanNorm.isEmpty && cleanNoTrailing.isEmpty) {
      return false;
    }

    // 4. Exact Listesi Kontrolü
    if (cleanNorm.isNotEmpty && _preparedExact.contains(cleanNorm)) {
      return true;
    }
    if (cleanNoTrailing.isNotEmpty && _preparedExact.contains(cleanNoTrailing)) {
      return true;
    }

    // 5. Contains Listesi Kontrolü
    for (final normContains in _preparedContains) {
      if ((cleanNorm.isNotEmpty && cleanNorm.contains(normContains)) ||
          (cleanNoTrailing.isNotEmpty &&
              cleanNoTrailing.contains(normContains))) {
        return true;
      }
    }

    return false;
  }

  /// Metindeki uygunsuz kelimeleri "ilk harf + yıldızlar" olarak maskeler.
  String maskInappropriateText(String text) {
    if (text.isEmpty) return '';

    // 1. Adım: Art arda gelen TEK HARFLİ aralıklı yazımları (örn. "s i k") yakala
    String processed = text;
    if (text.length <= 5000) {
      processed = processed.replaceAllMapped(_spacedSingleLetterRegex, (match) {
        final matchedText = match.group(0)!;
        if (isWordInappropriate(matchedText)) {
          return maskSingleWord(matchedText);
        }
        return matchedText;
      });
    }

    // 2. Adım: Boşluk ve sözcük tokenlarına ayır
    final matches = _tokenSplitRegex.allMatches(processed);
    final buffer = StringBuffer();

    for (final m in matches) {
      final token = m.group(0)!;
      if (_allWhitespaceRegex.hasMatch(token)) {
        buffer.write(token);
        continue;
      }

      // Sözcüğün tamamını kontrol et
      if (isWordInappropriate(token)) {
        buffer.write(maskSingleWord(token));
        continue;
      }

      // Cümle sonu/başı noktalama işaretlerini ayırarak kontrol et
      final punctMatch = _punctuationEnclosingRegex.firstMatch(token);
      if (punctMatch != null) {
        final lead = punctMatch.group(1) ?? '';
        final core = punctMatch.group(2) ?? '';
        final trail = punctMatch.group(3) ?? '';
        if (core.isNotEmpty && isWordInappropriate(core)) {
          buffer.write(lead);
          buffer.write(maskSingleWord(core));
          buffer.write(trail);
          continue;
        }
      }

      buffer.write(token);
    }

    return buffer.toString();
  }

  @override
  String apply(String text) => maskInappropriateText(text);
}
