import 'dart:io';

import 'package:app/features/achievements/data/achievements_asset_loader.dart';
import 'package:app/features/achievements/domain/achievement_ui_manifest.dart';
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
  });
}
