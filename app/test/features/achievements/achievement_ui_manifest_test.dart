import 'dart:io';

import 'package:app/features/achievements/data/achievements_asset_loader.dart';
import 'package:app/features/achievements/domain/achievement_ui_manifest.dart';
import 'package:app/features/achievements/domain/user_achievement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AchievementUiManifest & Contract Tests', () {
    test('Sözleşme Testi: achievements.json içindeki her id için manifest karşılığı olmalıdır', () {
      final file = File('assets/achievements/achievements.json');
      expect(file.existsSync(), isTrue, reason: 'achievements.json dosyası mevcut olmalıdır');

      final jsonString = file.readAsStringSync();
      final assetDefinitions = AchievementsAssetLoader.parseJsonString(jsonString);

      expect(assetDefinitions, isNotEmpty);
      expect(assetDefinitions.length, equals(11));

      for (final def in assetDefinitions) {
        final manifestItem = AchievementUiManifest.get(def.id);
        expect(
          manifestItem,
          isNotNull,
          reason: 'Manifest içinde "${def.id}" kimliği için tanım bulunmalıdır.',
        );
        expect(manifestItem!.id, equals(def.id));
        expect(manifestItem.title.trim(), isNotEmpty);
        expect(manifestItem.description.trim(), isNotEmpty);
      }
    });

    test('Manifest metinleri kural ve sözleşmeye uygun Türkçe başlıklara sahiptir', () {
      final expectedTexts = {
        'first_match': ('İlk Adım', 'İlk maçını tamamla'),
        'matches_10': ('Alışma Süreci', '10 maç tamamla'),
        'matches_50': ('Düzenli Oyuncu', '50 maç tamamla'),
        'matches_100': ('Yüzlük', '100 maç tamamla'),
        'first_win': ('İlk Zafer', 'İlk galibiyetini al'),
        'wins_10': ('Yükselen Yıldız', '10 galibiyet al'),
        'wins_50': ('Usta Oyuncu', '50 galibiyet al'),
        'wins_100': ('Efsane', '100 galibiyet al'),
        'streak_3': ('Üçlü Seri', 'Üst üste 3 maç kazan'),
        'streak_5': ('Beşli Seri', 'Üst üste 5 maç kazan'),
        'streak_10': ('Durdurulamaz', 'Üst üste 10 maç kazan'),
      };

      for (final entry in expectedTexts.entries) {
        final item = AchievementUiManifest.get(entry.key);
        expect(item, isNotNull);
        expect(item!.title, equals(entry.value.$1));
        expect(item.description, equals(entry.value.$2));
      }
    });

    test('Bilinmeyen bir id sorgulandığında sessizce null döner (çökmez)', () {
      expect(AchievementUiManifest.get('unknown_future_achievement'), isNull);
      expect(AchievementUiManifest.get(''), isNull);
      expect(AchievementUiManifest.iconAssetFor('unknown_future_achievement'), isNull);
    });

    test('Sözleşme Testi: Manifest içindeki tüm 11 başarımın SVG görsel dosyası mevcut olmalıdır', () {
      expect(AchievementUiManifest.items.length, equals(11));

      for (final item in AchievementUiManifest.items.values) {
        expect(item.iconAsset, equals('assets/icons/ach_${item.id}.svg'));
        expect(AchievementUiManifest.iconAssetFor(item.id), equals('assets/icons/ach_${item.id}.svg'));

        final iconFile = File(item.iconAsset);
        expect(
          iconFile.existsSync(),
          isTrue,
          reason: 'Başarım "${item.id}" için ${item.iconAsset} dosyası mevcut olmalıdır.',
        );
      }
    });

    test('Kullanıcıya açık metinlerde kısıtlı kelimeler (bot, yapay zeka, alıştırma maçı) geçmez', () {
      for (final item in AchievementUiManifest.items.values) {
        final lowerTitle = item.title.toLowerCase();
        final lowerDesc = item.description.toLowerCase();
        expect(lowerTitle.contains('bot'), isFalse);
        expect(lowerTitle.contains('yapay zeka'), isFalse);
        expect(lowerTitle.contains('alıştırma'), isFalse);
        expect(lowerDesc.contains('bot'), isFalse);
        expect(lowerDesc.contains('yapay zeka'), isFalse);
        expect(lowerDesc.contains('alıştırma'), isFalse);
      }
    });

    test('Rozet konumu (badgeDx) ve dönme açısı (badgeRotationDeg) sözleşmeye uygundur', () {
      // 1. first_win: sol üstteki küçük yıldız kart sol kenar çizgisiyle hizalı (badgeDx = -6, badgeRotationDeg = -6)
      final firstWin = AchievementUiManifest.get('first_win')!;
      expect(firstWin.badgeDx, equals(-6.0));
      expect(firstWin.badgeRotationDeg, equals(-6.0));

      // 2. wins_10: rozet sola daha yatık (-12°) ve sol kenardan dışarı taşar (-14px)
      final wins10 = AchievementUiManifest.get('wins_10')!;
      expect(wins10.badgeDx, equals(-14.0));
      expect(wins10.badgeRotationDeg, equals(-12.0));

      // 3. first_match: dönmeden (0°), kart içinde sol kenardan içeride (badgeDx = 4) ve alt kenara dayalıdır
      final firstMatch = AchievementUiManifest.get('first_match')!;
      expect(firstMatch.badgeDx, equals(4.0));
      expect(firstMatch.badgeDy, equals(0.0));
      expect(firstMatch.badgeAlignBottom, isTrue);
      expect(firstMatch.badgeRotationDeg, equals(0.0));

      // 4. Diğer 10 başarım dikey ortalama (badgeAlignBottom=false, badgeDy=0) korur, 8'i varsayılan (-12px, -6°) kalır
      expect(firstWin.badgeAlignBottom, isFalse);
      expect(firstWin.badgeDy, equals(0.0));
      expect(wins10.badgeAlignBottom, isFalse);
      expect(wins10.badgeDy, equals(0.0));

      final defaultIds = [
        'matches_10',
        'matches_50',
        'matches_100',
        'wins_50',
        'wins_100',
        'streak_3',
        'streak_5',
        'streak_10',
      ];
      for (final id in defaultIds) {
        final item = AchievementUiManifest.get(id)!;
        expect(item.badgeDx, equals(-12.0), reason: '$id için badgeDx -12 olmalıdır');
        expect(item.badgeDy, equals(0.0), reason: '$id için badgeDy 0 olmalıdır');
        expect(item.badgeAlignBottom, isFalse, reason: '$id için badgeAlignBottom false olmalıdır');
        expect(item.badgeRotationDeg, equals(-6.0), reason: '$id için badgeRotationDeg -6 olmalıdır');
      }

      // 5. AchievementUiItem varsayılan kurucu parametreleri bugünkü davranışla birebir aynıdır
      const sampleItem = AchievementUiItem(
        id: 'sample',
        title: 'Örnek',
        description: 'Açıklama',
      );
      expect(sampleItem.badgeDx, equals(-12.0));
      expect(sampleItem.badgeDy, equals(0.0));
      expect(sampleItem.badgeAlignBottom, isFalse);
      expect(sampleItem.badgeRotationDeg, equals(-6.0));
    });

    test('Sabit prestij rank sırası ve sortByPrestige bilinmeyen ID elemesi', () {
      const expectedPrestigeOrder = [
        'wins_100',
        'streak_10',
        'matches_100',
        'wins_50',
        'streak_5',
        'matches_50',
        'wins_10',
        'streak_3',
        'matches_10',
        'first_win',
        'first_match',
      ];

      for (var i = 0; i < expectedPrestigeOrder.length; i++) {
        final item = AchievementUiManifest.get(expectedPrestigeOrder[i]);
        expect(item, isNotNull);
        expect(item!.rank, equals(i));
      }

      final sorted = AchievementUiManifest.sortByPrestige(const [
        UserAchievement(id: 'first_match', unlockedAt: 100),
        UserAchievement(id: 'unknown_future_id', unlockedAt: 200),
        UserAchievement(id: 'wins_100', unlockedAt: 300),
        UserAchievement(id: 'streak_3', unlockedAt: 400, count: 5),
      ]);

      expect(
        sorted.map((e) => e.id).toList(),
        equals(['wins_100', 'streak_3', 'first_match']),
      );
    });
  });
}
