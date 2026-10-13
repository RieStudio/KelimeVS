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
    expect(loaded.first.botlaOynandi, isFalse);
    final attempt = loaded.first.roundRecords.first.attempts.first;
    expect(attempt.isClose, isFalse);
    expect(attempt.hintShown, isFalse);
  });

  test('botlaOynandi alanı serileştirmede korunur', () async {
    final repo = LocalMatchHistoryRepository();
    final botEntry = MatchHistoryEntry(
      id: 'bot_match_1',
      opponentName: 'Deniz',
      finishedAtMs: 1700000001000,
      myScore: 2,
      opponentScore: 0,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      roundRecords: const [],
      botlaOynandi: true,
    );
    final onlineEntry = MatchHistoryEntry(
      id: 'online_match_1',
      opponentName: 'Mert',
      finishedAtMs: 1700000002000,
      myScore: 1,
      opponentScore: 2,
      result: MatchResult.lose,
      endType: MatchEndType.normal,
      roundRecords: const [],
      botlaOynandi: false,
    );

    await repo.add(botEntry);
    await repo.add(onlineEntry);

    final loaded = await repo.loadRecent();
    expect(loaded.length, 2);
    expect(loaded[0].id, 'online_match_1');
    expect(loaded[0].botlaOynandi, isFalse);
    expect(loaded[1].id, 'bot_match_1');
    expect(loaded[1].botlaOynandi, isTrue);
  });

  test('Depo karışık sırayla yazılmış kayıtları en yeni başta döndürür', () async {
    // SharedPreferences içine karışık finishedAtMs sırasıyla JSON yaz
    const mixedJson = '[{'
        '"id":"match_old",'
        '"opponentName":"Eski",'
        '"finishedAtMs":1000,'
        '"myScore":2,'
        '"opponentScore":0,'
        '"result":"win",'
        '"endType":"normal",'
        '"roundRecords":[],'
        '"roundQuestionTexts":[]'
        '},{'
        '"id":"match_newest",'
        '"opponentName":"En Yeni",'
        '"finishedAtMs":5000,'
        '"myScore":2,'
        '"opponentScore":1,'
        '"result":"win",'
        '"endType":"normal",'
        '"roundRecords":[],'
        '"roundQuestionTexts":[]'
        '},{'
        '"id":"match_mid",'
        '"opponentName":"Orta",'
        '"finishedAtMs":3000,'
        '"myScore":1,'
        '"opponentScore":2,'
        '"result":"lose",'
        '"endType":"normal",'
        '"roundRecords":[],'
        '"roundQuestionTexts":[]'
        '}]';

    SharedPreferences.setMockInitialValues({
      'kelimego_match_history': mixedJson,
    });

    final repo = LocalMatchHistoryRepository();
    final loaded = await repo.loadRecent();

    expect(loaded.length, 3);
    expect(loaded[0].id, 'match_newest');
    expect(loaded[1].id, 'match_mid');
    expect(loaded[2].id, 'match_old');
  });

  test('11. kayıtta EN ESKİ kayıt silinir (en yeni değil, toplam 10 kayıt kalır)', () async {
    final repo = LocalMatchHistoryRepository();

    // 10 kayıt ekle: finishedAtMs 2000, 3000, ..., 11000
    for (int i = 1; i <= 10; i++) {
      await repo.add(createTestEntry(
        id: 'match_$i',
        opponentName: 'Oyuncu $i',
        finishedAtMs: 1000 + i * 1000,
      ));
    }

    var loaded = await repo.loadRecent();
    expect(loaded.length, 10);
    expect(loaded.first.id, 'match_10'); // 11000 ms
    expect(loaded.last.id, 'match_1'); // 2000 ms (en eski)

    // 11. kaydı ekle (finishedAtMs: 15000 - en yeni)
    await repo.add(createTestEntry(
      id: 'match_11',
      opponentName: 'Oyuncu 11',
      finishedAtMs: 15000,
    ));

    loaded = await repo.loadRecent();
    expect(loaded.length, 10);
    // En yeni en başta olmalı
    expect(loaded.first.id, 'match_11');
    // En eski olan match_1 (2000 ms) silinmiş olmalı, sondaki match_2 (3000 ms) olmalı
    expect(loaded.any((m) => m.id == 'match_1'), isFalse);
    expect(loaded.last.id, 'match_2');

    // Şimdi 12. kaydı daha eski bir tarihle ekleyelim (finishedAtMs: 1000)
    // Bu durumda 1000 ms mevcut tüm kayıtlardan (3000-15000) daha eski olduğu için kendisi silinmeli
    await repo.add(createTestEntry(
      id: 'match_very_old',
      opponentName: 'Çok Eski',
      finishedAtMs: 1000,
    ));

    loaded = await repo.loadRecent();
    expect(loaded.length, 10);
    // match_very_old en eski olduğu için listede yer almamalı, 3000-15000 arası 10 kayıt korunmalı
    expect(loaded.any((m) => m.id == 'match_very_old'), isFalse);
    expect(loaded.first.id, 'match_11');
    expect(loaded.last.id, 'match_2');
  });

  test('Aynı bitiş zamanına sahip kayıtlarda sonradan eklenen üstte yer alır', () async {
    final repo = LocalMatchHistoryRepository();

    // finishedAtMs değeri aynı (5000) olan 3 kayıt sırayla eklenir
    await repo.add(createTestEntry(
      id: 'match_first',
      opponentName: 'İlk Eklenen',
      finishedAtMs: 5000,
    ));

    await repo.add(createTestEntry(
      id: 'match_second',
      opponentName: 'İkinci Eklenen',
      finishedAtMs: 5000,
    ));

    await repo.add(createTestEntry(
      id: 'match_third',
      opponentName: 'Üçüncü Eklenen',
      finishedAtMs: 5000,
    ));

    final loaded = await repo.loadRecent();
    expect(loaded.length, 3);
    // Eşitlikte sonradan eklenen en üstte olmalı: match_third, match_second, match_first
    expect(loaded[0].id, 'match_third');
    expect(loaded[1].id, 'match_second');
    expect(loaded[2].id, 'match_first');
  });

  test(
    'botlaOynandi alanı olan (yeni), olmayan (eski) ve bozuk bir kayıt birlikte bulunduğunda geçerli kayıtlar yeni depo örneğinde birlikte okunur',
    () async {
      const mixedOldNewAndCorruptJson = '['
          '{'
          '"id":"legacy_match_no_bot_field",'
          '"opponentName":"Eski Sürüm Rakip",'
          '"finishedAtMs":1700000001000,'
          '"myScore":2,'
          '"opponentScore":1,'
          '"result":"win",'
          '"endType":"normal",'
          '"forfeitedPlayerId":null,'
          '"roundRecords":[]'
          '},'
          '{'
          '"id":"corrupt_entry",'
          '"opponentName":12345'
          '},'
          '{'
          '"id":"new_bot_match",'
          '"opponentName":"Yeni Bot",'
          '"finishedAtMs":1700000002000,'
          '"myScore":2,'
          '"opponentScore":0,'
          '"result":"win",'
          '"endType":"normal",'
          '"forfeitedPlayerId":null,'
          '"roundRecords":[],'
          '"roundQuestionTexts":["Meyveler"],'
          '"botlaOynandi":true'
          '},'
          '{'
          '"id":"new_online_match",'
          '"opponentName":"Yeni Online",'
          '"finishedAtMs":1700000003000,'
          '"myScore":1,'
          '"opponentScore":2,'
          '"result":"lose",'
          '"endType":"forfeit",'
          '"forfeitedPlayerId":"me",'
          '"roundRecords":[],'
          '"roundQuestionTexts":["Sebzeler"],'
          '"botlaOynandi":false'
          '}'
          ']';

      SharedPreferences.setMockInitialValues({
        'kelimego_match_history': mixedOldNewAndCorruptJson,
      });

      // Yeni depo örneği (uygulama yeniden başlatılmış gibi)
      final freshRepo = LocalMatchHistoryRepository();
      final loaded = await freshRepo.loadRecent();

      expect(loaded.length, 3);
      expect(loaded[0].id, 'new_online_match');
      expect(loaded[0].botlaOynandi, isFalse);
      expect(loaded[0].endType, MatchEndType.forfeit);

      expect(loaded[1].id, 'new_bot_match');
      expect(loaded[1].botlaOynandi, isTrue);

      expect(loaded[2].id, 'legacy_match_no_bot_field');
      expect(loaded[2].botlaOynandi, isFalse);
    },
  );
}


