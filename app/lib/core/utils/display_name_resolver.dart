import '../strings/app_strings.dart';

/// Kullanıcı görünen adlarını TEK bir kaynaktan tutarlı şekilde çözümler.
/// Misafir kullanıcılar için deterministik "M-####" takma ad üretir.
abstract final class DisplayNameResolver {
  /// Misafir kullanıcılar için deterministik "M-####" formatında takma ad üretir.
  /// Sunucu tarafındaki `generateGuestNickname(uid)` (displayName.ts / userProfile.ts) ile
  /// 100% birebir aynı 32-bit unsigned rolling hash algoritmasını kullanır.
  static String generateGuestNickname(String uid) {
    int hash = 0;
    for (int i = 0; i < uid.length; i++) {
      hash = ((hash * 31) + uid.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final num = 1000 + (hash % 9000);
    return 'M-$num';
  }

  /// M-#### misafir takma ad kalıbını kontrol eder.
  static bool isGuestPatternNickname(String raw) {
    final stripped = raw.replaceAll(RegExp(r'[\s\-_]'), '').toLowerCase();
    return RegExp(r'^m\d{4}$').hasMatch(stripped);
  }

  /// Görünen adı tek kaynaktan çözümler:
  /// - [isGuest] == true ise: ad her zaman M-#### olmalıdır. Mevcut ad M-#### ise korunur,
  ///   değilse veya yoksa uid'den türetilir.
  /// - [isGuest] == false ise: kayıtlı kullanıcının adı varsa korunur; yoksa 'Oyuncu' döner.
  /// - [isGuest] belirtilmemişse:
  ///   - [nickname] geçerli ve 'Oyuncu' değilse: [nickname] döner.
  ///   - [nickname] boşsa veya 'Oyuncu' ise:
  ///     - [uid] biliniyorsa: uid'den deterministik `generateGuestNickname(uid)` döner.
  ///     - [uid] bilinmiyorsa: [AppStrings.defaultPlayerName] ('Oyuncu') döner.
  static String resolve({
    String? nickname,
    String? uid,
    bool? isGuest,
  }) {
    final trimmed = nickname?.trim();
    final cleanUid = uid?.trim();

    if (isGuest == true) {
      if (trimmed != null && trimmed.isNotEmpty && isGuestPatternNickname(trimmed)) {
        return trimmed;
      }
      if (cleanUid != null && cleanUid.isNotEmpty) {
        return generateGuestNickname(cleanUid);
      }
      return (trimmed != null &&
              trimmed.isNotEmpty &&
              trimmed != AppStrings.defaultPlayerName)
          ? trimmed
          : AppStrings.defaultPlayerName;
    }

    if (isGuest == false) {
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
      return AppStrings.defaultPlayerName;
    }

    // isGuest belirtilmemişse:
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed == AppStrings.defaultPlayerName &&
          cleanUid != null &&
          cleanUid.isNotEmpty) {
        return generateGuestNickname(cleanUid);
      }
      return trimmed;
    }

    if (cleanUid != null && cleanUid.isNotEmpty) {
      return generateGuestNickname(cleanUid);
    }

    return AppStrings.defaultPlayerName;
  }
}
