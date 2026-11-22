import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

void main() {
  group('FinalServerMessage Achievements Parsing', () {
    test('1. final mesajında unlockedAchievements varsa başarıyla List<String> olarak ayrıştırılır', () {
      final json = jsonEncode({
        't': 'final',
        'rounds': [
          {
            'questionId': 'q1',
            'attempts': [
              {'mine': true, 'text': 'ankara', 'result': 'correct'}
            ],
            'winnerIsMe': true,
            'reason': 'normal'
          }
        ],
        'scores': {'me': 2, 'opponent': 1},
        'winnerIsMe': true,
        'endedBy': 'normal',
        'coinsAwarded': 30,
        'coins': 200,
        'rematchAvailable': true,
        'unlockedAchievements': ['first_match', 'first_win', 'streak_3'],
      });

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final fin = msg as FinalServerMessage;

      expect(fin.unlockedAchievements, isNotNull);
      expect(fin.unlockedAchievements, equals(['first_match', 'first_win', 'streak_3']));
      expect(fin.coinsAwarded, equals(30));
    });

    test('2. final mesajında unlockedAchievements alanı yoksa null döner (çökmez)', () {
      final json = jsonEncode({
        't': 'final',
        'rounds': [],
        'scores': {'me': 2, 'opponent': 0},
        'winnerIsMe': true,
        'endedBy': 'normal',
      });

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final fin = msg as FinalServerMessage;

      expect(fin.unlockedAchievements, isNull);
    });

    test('3. final mesajında unlockedAchievements boş dizi [] ise boş liste döner', () {
      final json = jsonEncode({
        't': 'final',
        'rounds': [],
        'scores': {'me': 1, 'opponent': 2},
        'winnerIsMe': false,
        'endedBy': 'normal',
        'unlockedAchievements': [],
      });

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final fin = msg as FinalServerMessage;

      expect(fin.unlockedAchievements, isEmpty);
    });
  });
}
