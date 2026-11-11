import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

void main() {
  group('LeaderboardEntry UID Tests', () {
    test('Sunucudan gelen uid doğru parse edilir', () {
      final json = {
        'rank': 1,
        'nickname': 'Champion',
        'wins': 42,
        'isMe': false,
        'frame': 'gold',
        'uid': 'user_champ_123',
      };

      final entry = LeaderboardEntry.fromJson(json);

      expect(entry.rank, 1);
      expect(entry.nickname, 'Champion');
      expect(entry.wins, 42);
      expect(entry.frame, 'gold');
      expect(entry.uid, 'user_champ_123');
    });

    test('Eski sunucudan gelen yanıtta uid eksikse null olur (çökmez)', () {
      final json = {
        'rank': 2,
        'nickname': 'RunnerUp',
        'wins': 38,
        'isMe': false,
        'frame': 'classic',
      };

      final entry = LeaderboardEntry.fromJson(json);

      expect(entry.rank, 2);
      expect(entry.uid, isNull);
    });

    test('Eşitlik kontrolünde uid dikkate alınır', () {
      const e1 = LeaderboardEntry(
        rank: 1,
        nickname: 'Alice',
        wins: 10,
        isMe: false,
        uid: 'uid_1',
      );
      const e2 = LeaderboardEntry(
        rank: 1,
        nickname: 'Alice',
        wins: 10,
        isMe: false,
        uid: 'uid_1',
      );
      const e3 = LeaderboardEntry(
        rank: 1,
        nickname: 'Alice',
        wins: 10,
        isMe: false,
        uid: 'uid_2',
      );

      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));
      expect(e1, isNot(equals(e3)));
    });
  });

  group('MatchHistoryEntry & Mapper opponentUid Tests', () {
    test('opponentUid içeren kayıt doğru serialize ve deserialize edilir', () {
      const entry = MatchHistoryEntry(
        id: 'match_123',
        matchId: 'online_m123',
        opponentName: 'Alice',
        opponentUid: 'user_alice_456',
        finishedAtMs: 1729452000000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        opponentFrame: 'emerald',
      );

      final json = LocalMatchHistoryRepository.entryFromJson;
      final rawMap = {
        'id': entry.id,
        'matchId': entry.matchId,
        'opponentName': entry.opponentName,
        'opponentUid': entry.opponentUid,
        'finishedAtMs': entry.finishedAtMs,
        'myScore': entry.myScore,
        'opponentScore': entry.opponentScore,
        'result': entry.result.name,
        'endType': entry.endType.name,
        'endReason': entry.endReason.name,
        'roundRecords': [],
        'roundQuestionTexts': [],
        'botlaOynandi': false,
        'isFinal': true,
        'isFriendly': false,
        'opponentFrame': entry.opponentFrame,
      };

      final deserialized = json(rawMap);

      expect(deserialized.id, 'match_123');
      expect(deserialized.opponentName, 'Alice');
      expect(deserialized.opponentUid, 'user_alice_456');
      expect(deserialized.opponentFrame, 'emerald');
    });

    test(
        'Eski depolama şeması (opponentUid anahtarı olmayan legacy kayıt) null olarak okunur',
        () {
      final legacyJson = {
        'id': 'legacy_match',
        'matchId': 'old_m_001',
        'opponentName': 'EskiOyuncu',
        // 'opponentUid' alanı yok
        'finishedAtMs': 1700000000000,
        'myScore': 2,
        'opponentScore': 0,
        'result': 'win',
        'endType': 'normal',
        'roundRecords': [],
      };

      final deserialized =
          LocalMatchHistoryRepository.entryFromJson(legacyJson);

      expect(deserialized.id, 'legacy_match');
      expect(deserialized.opponentName, 'EskiOyuncu');
      expect(deserialized.opponentUid, isNull); // Güvenli geriye dönük uyum!
    });
  });

  group('ServerMessage opponentUid Parsing Tests', () {
    test('matched mesajında opponentUid varsa parse edilir', () {
      final json = {
        't': 'matched',
        'matchId': 'm_789',
        'opponentName': 'Zeynep',
        'opponentUid': 'user_zeynep_999',
        'opponentFrame': 'mint',
      };

      final msg = parseServerMessage(json);
      expect(msg, isA<MatchedServerMessage>());
      final matched = msg as MatchedServerMessage;
      expect(matched.matchId, 'm_789');
      expect(matched.opponentName, 'Zeynep');
      expect(matched.opponentUid, 'user_zeynep_999');
      expect(matched.opponentFrame, 'mint');
    });

    test('bot maçında matched mesajında opponentUid gönderilmez (null kalır)',
        () {
      final json = {
        't': 'matched',
        'matchId': 'bot_123',
        'opponentName': 'KelimeBot',
      };

      final msg = parseServerMessage(json);
      expect(msg, isA<MatchedServerMessage>());
      final matched = msg as MatchedServerMessage;
      expect(matched.opponentUid, isNull);
    });

    test('final mesajında opponentUid varsa parse edilir', () {
      final json = {
        't': 'final',
        'rounds': [],
        'scores': {'me': 2, 'opponent': 1},
        'winnerIsMe': true,
        'endedBy': 'normal',
        'opponentName': 'Can',
        'opponentUid': 'user_can_555',
        'opponentFrame': 'sakura',
      };

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.opponentName, 'Can');
      expect(finalMsg.opponentUid, 'user_can_555');
      expect(finalMsg.opponentFrame, 'sakura');
    });

    test('final mesajında bot maçında opponentUid null kalır', () {
      final json = {
        't': 'final',
        'rounds': [],
        'scores': {'me': 2, 'opponent': 0},
        'winnerIsMe': true,
        'endedBy': 'normal',
        'opponentName': 'Bot',
      };

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.opponentUid, isNull);
    });
  });

  group('OnlineMatchHistoryMapper toHistoryEntry opponentUid Tests', () {
    test('final mesajındaki opponentUid MatchHistoryEntry içine yazılır', () {
      const finalMsg = FinalServerMessage(
        rounds: [],
        myScore: 2,
        opponentScore: 1,
        winnerIsMe: true,
        endedBy: 'normal',
        opponentName: 'Deniz',
        opponentUid: 'user_deniz_111',
        opponentFrame: 'ice',
      );

      final entry = OnlineMatchHistoryMapper.toHistoryEntry(
        finalMessage: finalMsg,
        matchId: 'match_online_1',
        opponentName: 'Deniz',
        finishedAtMs: 1729452000000,
        questionTextsById: {},
      );

      expect(entry.opponentUid, 'user_deniz_111');
      expect(entry.opponentName, 'Deniz');
      expect(entry.botlaOynandi, false);
    });

    test('bot veya parametresiz final mesajında opponentUid null kalır', () {
      const finalMsg = FinalServerMessage(
        rounds: [],
        myScore: 2,
        opponentScore: 0,
        winnerIsMe: true,
        endedBy: 'normal',
        opponentName: 'Bot',
      );

      final entry = OnlineMatchHistoryMapper.toHistoryEntry(
        finalMessage: finalMsg,
        matchId: 'match_online_2',
        opponentName: 'Bot',
        finishedAtMs: 1729452000000,
        questionTextsById: {},
      );

      expect(entry.opponentUid, isNull);
    });
  });
}
