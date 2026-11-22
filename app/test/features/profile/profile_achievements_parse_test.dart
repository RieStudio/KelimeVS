import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/profile/data/profile_api_client.dart';

void main() {
  group('UserProfileModel Achievements & Streaks Parsing', () {
    test('1. achievements dizisi ve streak alanları eksiksiz parse edilir', () {
      final json = {
        'uid': 'user_123',
        'nickname': 'Şampiyon',
        'coins': 500,
        'current_streak': 4,
        'max_streak': 7,
        'achievements': [
          {'id': 'first_match', 'unlockedAt': 1730000001000},
          {'id': 'first_win', 'unlocked_at': 1730000002000},
          {'id': 'streak_3', 'unlockedAt': 1730000003000},
        ],
      };

      final profile = UserProfileModel.fromJson(json);

      expect(profile.uid, equals('user_123'));
      expect(profile.nickname, equals('Şampiyon'));
      expect(profile.coins, equals(500));
      expect(profile.currentStreak, equals(4));
      expect(profile.maxStreak, equals(7));
      expect(profile.achievements.length, equals(3));

      expect(profile.achievements[0].id, equals('first_match'));
      expect(profile.achievements[0].unlockedAt, equals(1730000001000));

      // snake_case desteği (unlocked_at)
      expect(profile.achievements[1].id, equals('first_win'));
      expect(profile.achievements[1].unlockedAt, equals(1730000002000));

      expect(profile.achievements[2].id, equals('streak_3'));
      expect(profile.achievements[2].unlockedAt, equals(1730000003000));
    });

    test('2. achievements ve streak alanları yoksa güvenli varsayılan değerler atanır', () {
      final json = {
        'uid': 'user_456',
        'nickname': 'YeniOyuncu',
        'coins': 100,
      };

      final profile = UserProfileModel.fromJson(json);

      expect(profile.uid, equals('user_456'));
      expect(profile.currentStreak, equals(0));
      expect(profile.maxStreak, equals(0));
      expect(profile.achievements, isEmpty);
    });

    test('3. UserAchievement model equality ve hashCode kontrolü', () {
      const a1 = UserAchievement(id: 'streak_5', unlockedAt: 123456);
      const a2 = UserAchievement(id: 'streak_5', unlockedAt: 123456);
      const a3 = UserAchievement(id: 'streak_5', unlockedAt: 654321);

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
      expect(a1 == a3, isFalse);
    });
  });
}
