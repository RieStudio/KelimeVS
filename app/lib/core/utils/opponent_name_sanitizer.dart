import '../strings/app_strings.dart';
import 'display_name_resolver.dart';

/// Rakip takma adını temizler ve güvenli hale getirir:
/// - Kontrol karakterlerini (\x00-\x1F, \x7F) temizler.
/// - Baştaki ve sondaki boşlukları siler, ardışık boşlukları tek boşluğa indirir.
/// - En fazla [maxLength] (24) karakterle sınırlar.
/// - Boş, null veya 'Oyuncu' ise ve [opponentUid] varsa deterministik M-#### döner; yoksa [AppStrings.opponent] ("Rakip") fallback'ini döner.
abstract final class OpponentNameSanitizer {
  static const int maxLength = 24;

  static String sanitize(String? raw, {String? opponentUid}) {
    final cleanUid = opponentUid?.trim();
    if (raw == null) {
      if (cleanUid != null && cleanUid.isNotEmpty) {
        return DisplayNameResolver.generateGuestNickname(cleanUid);
      }
      return AppStrings.opponent;
    }
    final noControlChars = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    final trimmed = noControlChars.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) {
      if (cleanUid != null && cleanUid.isNotEmpty) {
        return DisplayNameResolver.generateGuestNickname(cleanUid);
      }
      return AppStrings.opponent;
    }
    if (trimmed == AppStrings.defaultPlayerName &&
        cleanUid != null &&
        cleanUid.isNotEmpty) {
      return DisplayNameResolver.generateGuestNickname(cleanUid);
    }
    return trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength);
  }
}

