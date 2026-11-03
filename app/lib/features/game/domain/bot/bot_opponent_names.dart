import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

/// Bot rakipler için gerçekçi takma ad havuzu ve son karşılaşılan rakipleri
/// saklayıp dışlama mantığını sağlayan tek merkezli yardımcı sınıf.
abstract final class BotOpponentNames {
  /// SharedPreferences saklama anahtarı
  static const String storageKey = 'kelimevs_recent_bot_names';

  /// Tekrarlanmaması gereken son rakip sayısı
  static const int maxRecentCount = 3;

  /// NicknameValidator kurallarına (%100 geçerli, küfürsüz, rezerve/misafir kalıbı olmayan)
  /// uygun, ilk isimler ve takma adlardan oluşan 60 elemanlı havuz.
  static const List<String> pool = [
    // 1. Gerçek Türkçe İsimler (30 Adet)
    'Ahmet',
    'Zeynep',
    'Mert',
    'Elif',
    'Burak',
    'Can',
    'Selin',
    'Deniz',
    'Mehmet',
    'Ayşe',
    'Emre',
    'Büşra',
    'Barış',
    'Ceren',
    'Kerem',
    'Ece',
    'Onur',
    'Gizem',
    'Kaan',
    'İrem',
    'Umut',
    'Derya',
    'Oğuz',
    'Damla',
    'Tolga',
    'Pınar',
    'Volkan',
    'Seda',
    'Murat',
    'Gamze',

    // 2. Takma Ad / Kullanıcı Adı Stili (30 Adet)
    'Kaan34',
    'ayse_k',
    'mrt_yilmaz',
    'Deniz07',
    'can_efe',
    'berk99',
    'elif_su',
    'burak_tr',
    'zeynep_d',
    'bora_ist',
    'selin_96',
    'alperen_06',
    'cemre_k',
    'yigit_35',
    'melis_a',
    'koray_88',
    'tugce_g',
    'arda_bjk',
    'hazal_s',
    'efe_can',
    'sinem_m',
    'eren_10',
    'ozge_k',
    'batuhan_54',
    'asli_d',
    'serkan_01',
    'nazli_e',
    'tarik_41',
    'busra_t',
    'cihan_61',
  ];

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

  /// Son rakipleri dışlayarak rastgele bir bot adı seçer.
  static String pickOpponentName({
    required math.Random random,
    List<String> recentNames = const [],
  }) {
    final recentSet = recentNames.toSet();
    final available = pool.where((name) => !recentSet.contains(name)).toList();
    final candidates = available.isNotEmpty ? available : pool;
    return candidates[random.nextInt(candidates.length)];
  }
}

