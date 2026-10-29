import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/strings/app_strings.dart';
import '../../game/domain/match/match_config.dart';

/// Maç öncesi ipucu seçici mantığı.
///
/// - O(1) rastgele seçim: Seçilen indeks lastIndex ile aynıysa döngüye girmeden
///   kalan seçenekler arasından eşit olasılıkla yeni bir indeks seçilir.
/// - SharedPreferences ile son gösterilen indeks kalıcı hatırlanır.
/// - SharedPreferences yoksa veya hata verirse bellek içi fallback (_lastIndexInMemory) kullanılır.
/// - Random parametresi enjekte edilebilir (test edilebilirlik).
abstract final class MatchTipSelector {
  static const String prefsLastTipIndexKey = 'last_matchmaking_tip_index';
  static int? _lastIndexInMemory;

  /// Test amaçlı son indeksi ayarlar.
  @visibleForTesting
  static void setLastIndexForTesting(int? index) {
    _lastIndexInMemory = index;
  }

  /// Test amaçlı son indeksi döner.
  @visibleForTesting
  static int? getLastIndexForTesting() => _lastIndexInMemory;

  /// Test amaçlı durumu tamamen sıfırlar.
  @visibleForTesting
  static void resetForTesting() {
    _lastIndexInMemory = null;
  }

  /// O(1) matematiksel indeks seçimi.
  /// [total] liste eleman sayısı.
  /// [lastIndex] bir önceki maçta gösterilen indeks.
  /// [random] enjekte edilebilir rastgele sayı üreteci.
  static int pickNextIndex({
    required int total,
    int? lastIndex,
    math.Random? random,
  }) {
    if (total <= 1) return 0;
    final rng = random ?? math.Random();
    final next = rng.nextInt(total);
    if (lastIndex != null && next == lastIndex) {
      return (next + 1 + rng.nextInt(total - 1)) % total;
    }
    return next;
  }

  /// Verilen liste içinden ipucu metnini seçer ve indeksi günceller.
  ///
  /// Ekran açılışında bir kez çağrılır (initState).
  static String selectTip({
    List<String>? tips,
    int? answerSeconds,
    SharedPreferences? prefs,
    math.Random? random,
  }) {
    final pool = tips ??
        AppStrings.getMatchTips(
          answerSeconds: answerSeconds ?? const MatchConfig().answerSeconds,
        );

    if (pool.isEmpty) return '';
    if (pool.length == 1) return pool.first;

    final lastIndex =
        prefs?.getInt(prefsLastTipIndexKey) ?? _lastIndexInMemory;
    final nextIndex = pickNextIndex(
      total: pool.length,
      lastIndex: lastIndex,
      random: random,
    );

    _lastIndexInMemory = nextIndex;

    if (prefs != null) {
      prefs.setInt(prefsLastTipIndexKey, nextIndex);
    } else {
      SharedPreferences.getInstance().then((p) {
        p.setInt(prefsLastTipIndexKey, nextIndex);
      }).catchError((_) {});
    }

    return pool[nextIndex];
  }
}

