import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  MatchHistoryEntry createTestEntry({
    required String id,
    required String opponentName,
    required int finishedAtMs,
    int myScore = 2,
    int opponentScore = 1,
    MatchResult result = MatchResult.win,
    MatchEndType endType = MatchEndType.normal,
    String? forfeitedPlayerId,
  }) {
    return MatchHistoryEntry(
      id: id,
      opponentName: opponentName,
      finishedAtMs: finishedAtMs,
      myScore: myScore,
      opponentScore: opponentScore,
      result: result,
      endType: endType,
      forfeitedPlayerId: forfeitedPlayerId,
      roundRecords: [
        RoundRecord(
          questionId: 'q_1',
          starterPlayerId: 'me',
          attempts: [
            const TurnAttempt(
              playerId: 'me',
              rawInput: 'ankara',
              resultType: AttemptResultType.correct,
              answerId: 'ankara',
              nowMs: 1000,
            ),
            const TurnAttempt(
              playerId: 'bot',
              rawInput: 'izmir',
              resultType: AttemptResultType.wrong,
              nowMs: 2000,
            ),
          ],
          winnerId: 'me',
          reason: RoundEndReason.timeout,
        ),
      ],
    );
  }

  test('Kayıt ekleme ve okuma serileştirme gidiş-dönüşünü doğru korur', () async {
    final repo = LocalMatchHistoryRepository();
    final entry = createTestEntry(
      id: 'match_1',
      opponentName: 'Zeynep',
      finishedAtMs: 1700000000000,
    );

    await repo.add(entry);
    final loaded = await repo.loadRecent();

    expect(loaded.length, 1);
    final loadedEntry = loaded.first;
    expect(loadedEntry.id, 'match_1');
    expect(loadedEntry.opponentName, 'Zeynep');
    expect(loadedEntry.finishedAtMs, 1700000000000);
    expect(loadedEntry.myScore, 2);
    expect(loadedEntry.opponentScore, 1);
    expect(loadedEntry.result, MatchResult.win);
    expect(loadedEntry.endType, MatchEndType.normal);
    expect(loadedEntry.forfeitedPlayerId, isNull);

    // RoundRecord ve TurnAttempt detayları
    expect(loadedEntry.roundRecords.length, 1);
    final record = loadedEntry.roundRecords.first;
    expect(record.questionId, 'q_1');
    expect(record.starterPlayerId, 'me');
    expect(record.winnerId, 'me');
    expect(record.reason, RoundEndReason.timeout);
    expect(record.attempts.length, 2);

    expect(record.attempts[0].playerId, 'me');
    expect(record.attempts[0].rawInput, 'ankara');
    expect(record.attempts[0].resultType, AttemptResultType.correct);
    expect(record.attempts[0].answerId, 'ankara');
    expect(record.attempts[0].nowMs, 1000);

    expect(record.attempts[1].playerId, 'bot');
    expect(record.attempts[1].rawInput, 'izmir');
    expect(record.attempts[1].resultType, AttemptResultType.wrong);
    expect(record.attempts[1].answerId, isNull);
    expect(record.attempts[1].nowMs, 2000);
  });

  test('Terk (forfeit) durumunda forfeitedPlayerId korunur', () async {
    final repo = LocalMatchHistoryRepository();
    final entry = createTestEntry(
      id: 'match_forfeit',
      opponentName: 'Mert',
      finishedAtMs: 1700000005000,
      myScore: 0,
      opponentScore: 0,
      result: MatchResult.lose,
      endType: MatchEndType.forfeit,
      forfeitedPlayerId: 'me',
    );

    await repo.add(entry);
    final loaded = await repo.loadRecent();

    expect(loaded.length, 1);
    expect(loaded.first.endType, MatchEndType.forfeit);
    expect(loaded.first.forfeitedPlayerId, 'me');
    expect(loaded.first.result, MatchResult.lose);
  });

  test('En fazla 10 kayıt tutulur ve en yeni başta sıralanır', () async {
    final repo = LocalMatchHistoryRepository();

    // 15 farklı kayıt ekle (farklı zaman damgalarıyla)
    for (int i = 1; i <= 15; i++) {
      await repo.add(createTestEntry(
        id: 'match_$i',
        opponentName: 'Oyuncu $i',
        finishedAtMs: 1000 + i * 100, // artan zaman
      ));
    }

    final loaded = await repo.loadRecent();

    expect(loaded.length, 10);
    // En yeni en başta olmalı (match_15, sonra match_14, ...)
    expect(loaded.first.id, 'match_15');
    expect(loaded[1].id, 'match_14');
    expect(loaded.last.id, 'match_6');
  });

  test('Boş depodan okuma boş liste döner', () async {
    final repo = LocalMatchHistoryRepository();
    final loaded = await repo.loadRecent();
    expect(loaded, isEmpty);
  });

  test('isClose ve hintShown alanları serileştirmede korunur', () async {
    final repo = LocalMatchHistoryRepository();
    final entry = MatchHistoryEntry(
      id: 'match_close',
      opponentName: 'Ali',
      finishedAtMs: 1700000000000,
      myScore: 2,
      opponentScore: 1,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      roundRecords: [
        RoundRecord(
          questionId: 'q_1',
          starterPlayerId: 'me',
          attempts: const [
            TurnAttempt(
              playerId: 'me',
              rawInput: 'aude',
              resultType: AttemptResultType.nearMiss,
              nowMs: 1000,
              isClose: true,
              hintShown: true,
            ),
            TurnAttempt(
              playerId: 'bot',
              rawInput: 'parsi',
              resultType: AttemptResultType.wrong,
              nowMs: 2000,
              isClose: true,
              hintShown: false,
            ),
          ],
          winnerId: 'me',
          reason: RoundEndReason.timeout,
        ),
      ],
    );

    await repo.add(entry);
    final loaded = await repo.loadRecent();
    expect(loaded.length, 1);
    final attempts = loaded.first.roundRecords.first.attempts;
    expect(attempts[0].isClose, isTrue);
    expect(attempts[0].hintShown, isTrue);
    expect(attempts[1].isClose, isTrue);
    expect(attempts[1].hintShown, isFalse);
  });

  test('Eski kayıtlarda isClose ve hintShown yoksa varsayılan false olarak yüklenir (geriye uyumluluk)', () async {
    // Eski JSON yapısını doğrudan SharedPreferences'a yaz
    const oldJson = '[{'
        '"id":"old_match",'
        '"opponentName":"Eski Rakip",'
        '"finishedAtMs":1690000000000,'
        '"myScore":2,'
        '"opponentScore":1,'
        '"result":"win",'
        '"endType":"normal",'
        '"forfeitedPlayerId":null,'
        '"roundRecords":[{'
        '"questionId":"q_old",'
        '"starterPlayerId":"me",'
        '"winnerId":"me",'
        '"reason":"timeout",'
        '"attempts":[{'
        '"playerId":"me",'
        '"rawInput":"ankara",'
        '"resultType":"correct",'
        '"answerId":"ankara",'
        '"nowMs":1000'
        '}]'
        '}],'
        '"roundQuestionTexts":[]'
        '}]';

    SharedPreferences.setMockInitialValues({
      'kelimego_match_history': oldJson,
    });

    final repo = LocalMatchHistoryRepository();
    final loaded = await repo.loadRecent();

    expect(loaded.length, 1);
    expect(loaded.first.id, 'old_match');
    final attempt = loaded.first.roundRecords.first.attempts.first;
    expect(attempt.isClose, isFalse);
    expect(attempt.hintShown, isFalse);
  });
}

