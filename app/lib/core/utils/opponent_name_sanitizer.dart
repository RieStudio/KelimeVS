import '../strings/app_strings.dart';

/// Rakip takma adını temizler ve güvenli hale getirir:
/// - Kontrol karakterlerini (\x00-\x1F, \x7F) temizler.
/// - Baştaki ve sondaki boşlukları siler, ardışık boşlukları tek boşluğa indirir.
/// - En fazla [maxLength] (24) karakterle sınırlar.
/// - Boş veya null ise [AppStrings.opponent] ("Rakip") fallback'ini döner.
abstract final class OpponentNameSanitizer {
  static const int maxLength = 24;

  static String sanitize(String? raw) {
    if (raw == null) return AppStrings.opponent;
    final noControlChars = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    final trimmed = noControlChars.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return AppStrings.opponent;
    return trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength);
  }
}

