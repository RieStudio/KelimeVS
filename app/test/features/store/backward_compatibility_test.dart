import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';

void main() {
  group('Backward Compatibility - Unknown JSON fields ignored', () {
    test('UserProfileModel handles extra unknown server fields gracefully', () {
      final json = {
        'uid': 'user_123',
        'nickname': 'Ali',
        'coins': 250,
        'equippedFrame': 'gold',
        'stats': {'played': 10, 'won': 7, 'lost': 3},
        'extra_field_from_future': 'should_be_ignored',
        'future_badge': {'level': 5},
      };

      final profile = UserProfileModel.fromJson(json);
      expect(profile.uid, 'user_123');
      expect(profile.nickname, 'Ali');
      expect(profile.coins, 250);
      expect(profile.equippedFrame, 'gold');
    });

    test('LeaderboardEntry handles extra unknown fields and missing frame', () {
      final jsonWithFrame = {
        'uid': 'p1',
        'nickname': 'Veli',
        'wins': 15,
        'rank': 1,
        'frame': 'diamond',
        'future_season_rating': 1500,
      };

      final entry1 = LeaderboardEntry.fromJson(jsonWithFrame);
      expect(entry1.frame, 'diamond');

      final jsonWithoutFrame = {
        'uid': 'p2',
        'nickname': 'Ayşe',
        'wins': 10,
        'rank': 2,
        'new_feature_flag': true,
      };

      final entry2 = LeaderboardEntry.fromJson(jsonWithoutFrame);
      expect(entry2.frame, 'classic');
    });

    test('MatchedServerMessage handles extra unknown fields', () {
      final json = {
        't': 'matched',
        'matchId': 'm_99',
        'opponentName': 'Rakip1',
        'opponentFrame': 'neon',
        'isFriendly': true,
        'future_match_variant': 'blitz',
      };

      final msg = parseServerMessage(json) as MatchedServerMessage;
      expect(msg.matchId, 'm_99');
      expect(msg.opponentName, 'Rakip1');
      expect(msg.opponentFrame, 'neon');
      expect(msg.isFriendly, isTrue);
    });

    test('FinalServerMessage handles extra unknown fields and missing frame', () {
      final json = {
        't': 'final',
        'winnerIsMe': true,
        'endedBy': 'normal',
        'myScore': 2,
        'opponentScore': 1,
        'rounds': <Map<String, dynamic>>[],
        'opponentFrame': 'rainbow',
        'server_timestamp': 123456789,
      };

      final msg = parseServerMessage(json) as FinalServerMessage;
      expect(msg.winnerIsMe, isTrue);
      expect(msg.opponentFrame, 'rainbow');
    });

    test('LocalMatchHistoryRepository handles extra unknown fields and missing frame', () {
      final json = {
        'id': 'rec_1',
        'opponentName': 'Bot',
        'finishedAtMs': 1000,
        'myScore': 2,
        'opponentScore': 0,
        'result': 'win',
        'endType': 'normal',
        'endReason': 'normal',
        'roundRecords': <Map<String, dynamic>>[],
        'roundQuestionTexts': <String>[],
        'botlaOynandi': true,
        'future_metadata': {'version': 2},
      };

      final record = LocalMatchHistoryRepository.entryFromJson(json);
      expect(record.opponentFrame, 'classic');
    });

    test('StoreItem.fromJson maps server cost and isOwned fields to price and owned', () {
      final json = {
        'id': 'gold',
        'name': 'Altın',
        'cost': 300,
        'description': 'Lüks altın kenarlık',
        'order': 5,
        'isOwned': false,
        'isEquipped': false,
        'future_discount': 20,
      };

      final item = StoreItem.fromJson(json);
      expect(item.id, 'gold');
      expect(item.name, 'Altın');
      expect(item.price, 300);
      expect(item.owned, isFalse);
      expect(item.isEquipped, isFalse);
    });
  });
}

