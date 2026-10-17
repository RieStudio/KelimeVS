// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import '../../game/domain/text_normalizer.dart';
import 'profanity_words.dart';

class NicknameValidationResult {
  final bool isValid;
  final String? normalized;
  final String? errorMessage;

  const NicknameValidationResult({
    required this.isValid,
    this.normalized,
    this.errorMessage,
  });

  const NicknameValidationResult.valid(this.normalized)
      : isValid = true,
        errorMessage = null;

  const NicknameValidationResult.invalid(this.errorMessage)
      : isValid = false,
        normalized = null;
}

abstract final class NicknameValidator {
  static final RegExp _allowedCharsRegex =
      RegExp(r'^[a-zA-Z0-9_ çÇğĞıIİiöÖşŞüÜ]+$');
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');

  static NicknameValidationResult validate(String? raw) {
    if (raw == null) {
      return const NicknameValidationResult.invalid(
        'Lütfen bir takma ad girin.',
      );
    }

    // 1. Başta ve sonda boşluk silinir, ardışık boşluklar tek boşluğa iner
    final trimmed = raw.trim().replaceAll(_multiSpaceRegex, ' ');

    if (trimmed.isEmpty) {
      return const NicknameValidationResult.invalid(
        'Lütfen bir takma ad girin.',
      );
    }

    // 2. 3–16 karakter uzunluk kontrolü
    if (trimmed.length < 3) {
      return const NicknameValidationResult.invalid(
        'Takma ad en az 3 karakter olmalıdır.',
      );
    }
    if (trimmed.length > 16) {
      return const NicknameValidationResult.invalid(
        'Takma ad en fazla 16 karakter olabilir.',
      );
    }

    // 3. Yalnızca harf (Türkçe harfler dahil), rakam, boşluk ve alt çizgi
    if (!_allowedCharsRegex.hasMatch(trimmed)) {
      return const NicknameValidationResult.invalid(
        'Yalnızca harf, rakam, boşluk ve alt çizgi (_) kullanabilirsin.',
      );
    }

    // 4. Küfür/uygunsuz kelime filtresi (Türkçe normalizasyon uygulanarak)
    final normalized = TextNormalizer.normalize(trimmed);
    for (final badWord in profanityWords) {
      if (normalized.contains(badWord)) {
        return const NicknameValidationResult.invalid(
          'Bu takma ad uygunsuz ifadeler içeriyor.',
        );
      }
    }

    return NicknameValidationResult.valid(trimmed);
  }
}
