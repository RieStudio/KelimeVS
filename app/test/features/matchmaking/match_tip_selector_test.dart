import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/matchmaking/domain/match_tip_selector.dart';

void main() {
  group('MatchTipSelector Unit Tests', () {
    setUp(() {
      MatchTipSelector.resetForTesting();
    });

    test('pickNextIndex: total <= 1 olduğunda 0 döner', () {
      expect(MatchTipSelector.pickNextIndex(total: 0), 0);
      expect(MatchTipSelector.pickNextIndex(total: 1), 0);
      expect(MatchTipSelector.pickNextIndex(total: 1, lastIndex: 0), 0);
    });

    test('pickNextIndex: hiçbir zaman lastIndex ile aynı indeksi seçmez (1000 deneme fuzz testi)', () {
      final rng = math.Random(12345);
      const total = 19;
      int? lastIndex;

      for (int i = 0; i < 1000; i++) {
        final next = MatchTipSelector.pickNextIndex(
          total: total,
          lastIndex: lastIndex,
          random: rng,
        );

        expect(next, greaterThanOrEqualTo(0));
        expect(next, lessThan(total));
        if (lastIndex != null) {
          expect(next, isNot(equals(lastIndex)),
              reason: 'İterasyon $i: lastIndex $lastIndex ile aynı indeks $next seçildi!');
        }
        lastIndex = next;
      }
    });

    test('pickNextIndex: deterministik random ile beklenen matematiksel indeksi üretir', () {
      // 5 elemanlı listede lastIndex=2 iken rng.nextInt(5) 2 dönerse:
      // (2 + 1 + rng.nextInt(4)) % 5 formülü çalışır.
      final mockRng = math.Random(42);
      final index1 = MatchTipSelector.pickNextIndex(
        total: 5,
        lastIndex: null,
        random: mockRng,
      );
      expect(index1, inInclusiveRange(0, 4));

      final index2 = MatchTipSelector.pickNextIndex(
        total: 5,
        lastIndex: index1,
        random: mockRng,
      );
      expect(index2, isNot(equals(index1)));
    });

    test('selectTip: SharedPreferences ile son indeksi hatırlar ve kaydeder', () async {
      SharedPreferences.setMockInitialValues({
        MatchTipSelector.prefsLastTipIndexKey: 3,
      });
      final prefs = await SharedPreferences.getInstance();

      final customTips = ['İpucu A', 'İpucu B', 'İpucu C', 'İpucu D', 'İpucu E'];
      // lastIndex = 3 ('İpucu D') olduğu için bir sonraki seçim asla 'İpucu D' olmamalı
      final selected = MatchTipSelector.selectTip(
        tips: customTips,
        prefs: prefs,
        random: math.Random(99),
      );

      expect(selected, isNot(equals('İpucu D')));
      expect(customTips.contains(selected), isTrue);

      final savedIndex = prefs.getInt(MatchTipSelector.prefsLastTipIndexKey);
      expect(savedIndex, isNotNull);
      expect(customTips[savedIndex!], equals(selected));
    });

    test('selectTip: SharedPreferences yoksa bellek içi fallback ile art arda tekrarı önler', () {
      final customTips = ['Tip 1', 'Tip 2', 'Tip 3'];
      final tip1 = MatchTipSelector.selectTip(tips: customTips);
      final tip2 = MatchTipSelector.selectTip(tips: customTips);

      expect(tip1, isNot(equals(tip2)));
    });

    test('selectTip: tek elemanlı listede o elemanı döner', () {
      final single = MatchTipSelector.selectTip(tips: ['Tek']);
      expect(single, 'Tek');
    });

    test('selectTip: boş listede boş string döner', () {
      final empty = MatchTipSelector.selectTip(tips: []);
      expect(empty, '');
    });

    test('İpucu Havuzu Doğrulama (AppStrings.getMatchTips)', () {
      final tips = AppStrings.getMatchTips(answerSeconds: 15);
      expect(tips.length, equals(19));

      // Süre parametresinin dinamik yerleşimi
      final customDurationTips = AppStrings.getMatchTips(answerSeconds: 20);
      expect(customDurationTips[1], contains('20 saniyen var'));

      for (int i = 0; i < tips.length; i++) {
        final tip = tips[i];
        expect(tip.trim(), isNotEmpty, reason: 'İpucu $i boş olamaz');
        expect(tip.length, lessThanOrEqualTo(90),
            reason: 'İpucu $i ("$tip") kart boyutuna sığması için 90 karakterden kısa olmalıdır (mevcut: ${tip.length})');
        expect(tip.length, greaterThanOrEqualTo(25),
            reason: 'İpucu $i çok kısa olamaz');
        // Eksik/hatalı tırnak karakteri kontrolü: akıllı tırnak yerine düz tırnak
        expect(tip.contains('“') || tip.contains('”'), isFalse,
            reason: 'İpucu $i düz ascii tırnak ("...") kullanmalıdır');
      }
    });
  });
}

