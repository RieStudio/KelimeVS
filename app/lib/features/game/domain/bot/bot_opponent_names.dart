import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

/// Bot rakipler için misafir formatında (M-####) takma ad üretimi ve son karşılaşılan
/// rakipleri saklayıp dışlama mantığını sağlayan tek merkezli yardımcı sınıf.
abstract final class BotOpponentNames {
  /// SharedPreferences saklama anahtarı
  static const String storageKey = 'kelimevs_recent_bot_names';

  /// Tekrarlanmaması gereken son rakip sayısı
  static const int maxRecentCount = 3;

  /// Kayıtlı son karşılaşılan bot isimlerini yükler.
  static List<String> loadRecentNames(SharedPreferences prefs) {
    return prefs.getStringList(storageKey) ?? const [];
  }

  /// Yeni bir bot maçına fiilen başlandığında ismi son karşılaşılanlara kaydeder (azami 3).
  static Future<void> recordRecentName(
    String name,
    SharedPreferences prefs,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final current = List<String>.from(loadRecentNames(prefs));
    current.remove(trimmed);
    current.add(trimmed);

    while (current.length > maxRecentCount) {
      current.removeAt(0);
    }

    await prefs.setStringList(storageKey, current);
  }

  /// Misafir formatında ("M-" + 1000-9999 arası 4 basamaklı sayı, örn. M-4821)
  /// son rakipleri ve oyuncunun kendi adını (özellikle oyuncu da misafirse)
  /// dışlayarak rastgele bir bot adı üretir.
  static String pickOpponentName({
    required math.Random random,
    List<String> recentNames = const [],
    String? excludeName,
  }) {
    final excluded = <String>{
      for (final r in recentNames) r.trim().toUpperCase(),
      if (excludeName != null && excludeName.trim().isNotEmpty)
        excludeName.trim().toUpperCase(),
    };

    // 1000..9999 aralığında rastgele sayı üret (9000 olasılık)
    for (int i = 0; i < 100; i++) {
      final num = 1000 + random.nextInt(9000);
      final candidate = 'M-$num';
      if (!excluded.contains(candidate.toUpperCase())) {
        return candidate;
      }
    }

    // Olası yoğun çakışma durumunda deterministik fallback
    for (int n = 1000; n <= 9999; n++) {
      final candidate = 'M-$n';
      if (!excluded.contains(candidate.toUpperCase())) {
        return candidate;
      }
    }

    return 'M-1000';
  }
}
