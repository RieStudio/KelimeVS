import 'dart:convert';
import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/models.dart';

class FakeClock implements GameClock {
  final FakeAsync async;
  FakeClock(this.async);

  @override
  int nowMs() => async.elapsed.inMilliseconds;
}

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  final List<MatchHistoryEntry> entries = [];

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    entries.add(entry);
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return List.unmodifiable(entries);
  }

  @override
  Future<void> clear() async {
    entries.clear();
  }
}

void main() {
  const q1 = Question(
    id: 'q1',
    categoryId: 'c1',
    text: 'Soru 1',
    answers: [
      Answer(id: 'a1_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a1_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );
  const q2 = Question(
    id: 'q2',
    categoryId: 'c1',
    text: 'Soru 2',
    answers: [
      Answer(id: 'a2_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a2_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );
  const q3 = Question(
    id: 'q3',
    categoryId: 'c1',
    text: 'Soru 3',
    answers: [
      Answer(id: 'a3_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a3_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );

  test('Maç normal bittiğinde geçmişe BİR KEZ kaydedilir', () {
    fakeAsync((async) {
      final fakeClock = FakeClock(async);
      final fakeRepo = FakeMatchHistoryRepository();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(fakeClock),
          randomProvider.overrideWithValue(math.Random(1)),
          matchHistoryRepositoryProvider.overrideWithValue(fakeRepo),
          matchConfigProvider.overrideWithValue(
            const MatchConfig(
              answerSeconds: 15,
              totalDecisiveRounds: 3,
            ),
          ),
          botConfigProvider.overrideWithValue(
            const BotConfig(
              baseKnowChance: 1.0,
              thinkMinMs: 1000,
              thinkMaxMs: 1000,
            ),
          ),
        ],
      );

      final controller = container.read(matchControllerProvider.notifier);
      controller.startMatch(
        questions: [q1, q2, q3],
        opponentName: 'Ahmet',
      );

      // 1. Tur: Sıra me'de. Me süre aşımına uğrar (bot: 1, me: 0)
      async.elapse(const Duration(milliseconds: 15200));
      // 3 sn geçiş
      async.elapse(const Duration(milliseconds: 3000));

      // 2. Tur: Sıra botta. Bot 1000 ms sonra cevap verir
      async.elapse(const Duration(milliseconds: 1000));
      // Sıra me'ye geçer, me süre aşımına uğrar (bot: 2, me: 0, maç 2-0 ile biter!)
      async.elapse(const Duration(milliseconds: 15200));

      // matchFinished tetiklendi (Best of 3 kuralı: 2 galibiyete ulaşıldı), repo'ya tam 1 kayıt eklenmiş olmalı
      expect(fakeRepo.entries.length, 1);
      final entry = fakeRepo.entries.first;
      expect(entry.opponentName, 'Ahmet');
      expect(entry.myScore, 0);
      expect(entry.opponentScore, 2);
      expect(entry.result, MatchResult.lose);
      expect(entry.endType, MatchEndType.normal);
      expect(entry.forfeitedPlayerId, isNull);
      expect(entry.roundRecords.length, 2);
      expect(entry.botlaOynandi, isTrue);

      // 3 saniyelik final reveal geçtikten sonra da ek bir kayıt ATILMAMALI
      async.elapse(const Duration(milliseconds: 3000));
      expect(fakeRepo.entries.length, 1);

      container.dispose();
    });
  });

  test('Maç terk edildiğinde (leaveMatch) geçmişe BİR KEZ forfeit olarak kaydedilir', () {
    fakeAsync((async) {
      final fakeClock = FakeClock(async);
      final fakeRepo = FakeMatchHistoryRepository();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(fakeClock),
          randomProvider.overrideWithValue(math.Random(42)),
          matchHistoryRepositoryProvider.overrideWithValue(fakeRepo),
          matchConfigProvider.overrideWithValue(
            const MatchConfig(
              answerSeconds: 15,
              totalDecisiveRounds: 3,
            ),
          ),
        ],
      );

      final controller = container.read(matchControllerProvider.notifier);
      controller.startMatch(
        questions: [q1, q2, q3],
        opponentName: 'Zeynep',
      );

      async.elapse(const Duration(milliseconds: 1000));

      // Kullanıcı maçı terk eder
      controller.leaveMatch();

      expect(fakeRepo.entries.length, 1);
      final entry = fakeRepo.entries.first;
      expect(entry.opponentName, 'Zeynep');
      expect(entry.result, MatchResult.lose);
      expect(entry.endType, MatchEndType.forfeit);
      expect(entry.forfeitedPlayerId, 'me');
      expect(entry.botlaOynandi, isTrue);

      // Ekstra beklemede ikinci kayıt atılmaz
      async.elapse(const Duration(milliseconds: 5000));
      expect(fakeRepo.entries.length, 1);

      container.dispose();
    });
  });

  test(
    'Uygulama yeniden başlatıldıktan sonra (StopwatchClock sıfırlansa bile) biten yerel bot maçı gerçek depoya yazılır ve yeni depo örneğinde en başta okunur',
    () async {
      // Önceki daha uzun oturumdan kalmış 10 kayıt (500.000 ms - 1.400.000 ms arası zaman damgaları,
      // hem botlaOynandi alanı olmayan eski hem de olan yeni kayıtlar karışık)
      final existingJsonList = List.generate(10, (i) {
        final map = <String, dynamic>{
          'id': 'prev_match_$i',
          'opponentName': 'Eski Rakip $i',
          'finishedAtMs': 500000 + i * 100000,
          'myScore': 2,
          'opponentScore': 1,
          'result': 'win',
          'endType': 'normal',
          'forfeitedPlayerId': null,
          'roundRecords': <Map<String, dynamic>>[],
          'roundQuestionTexts': <String>[],
        };
        if (i.isEven) {
          map['botlaOynandi'] = true;
        }
        return map;
      });

      SharedPreferences.setMockInitialValues({
        'kelimego_match_history': jsonEncode(existingJsonList),
      });

      final container = ProviderContainer(
        overrides: [
          // Varsayılan gameClockProvider (StopwatchClock) kullanılır!
          randomProvider.overrideWithValue(math.Random(7)),
          matchConfigProvider.overrideWithValue(
            const MatchConfig(
              answerSeconds: 15,
              totalDecisiveRounds: 3,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(matchControllerProvider.notifier);
      await controller.startMatch(
        questions: [q1, q2, q3],
        opponentName: 'Yeni Bot Rakip',
      );

      // Maçı bitir (forfeit ile anında bitiş)
      controller.leaveMatch();

      // Asenkron SharedPreferences yazımının tamamlanmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Uygulama tamamen kapatılıp yeniden açılmış gibi YENİ bir LocalMatchHistoryRepository örneğiyle oku
      final freshRepo = LocalMatchHistoryRepository();
      final loaded = await freshRepo.loadRecent();

      expect(loaded.length, 10);
      expect(loaded.first.opponentName, 'Yeni Bot Rakip');
      expect(loaded.first.botlaOynandi, isTrue);
      expect(loaded.first.endType, MatchEndType.forfeit);

      // Sağlayıcı üzerinden de aynı güncel listenin okunduğunu doğrula
      final providerList = await container.read(matchHistoryProvider.future);
      expect(providerList.first.opponentName, 'Yeni Bot Rakip');
    },
  );

  test(
    'Normal biten yerel bot maçı gerçek depoya tek kayıt olarak yazılır ve yeni depo örneğinde (yeniden başlatma simülasyonu) okunur',
    () {
      SharedPreferences.setMockInitialValues({});

      fakeAsync((async) {
        final fakeClock = FakeClock(async);

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                baseKnowChance: 1.0,
                thinkMinMs: 1000,
                thinkMaxMs: 1000,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [q1, q2, q3],
          opponentName: 'Normal Bot Rakip',
        );

        // 1. Tur: Sıra me'de. Me süre aşımına uğrar (bot: 1, me: 0)
        async.elapse(const Duration(milliseconds: 15200));
        // 3 sn geçiş
        async.elapse(const Duration(milliseconds: 3000));

        // 2. Tur: Sıra botta. Bot 1000 ms sonra cevap verir
        async.elapse(const Duration(milliseconds: 1000));
        // Sıra me'ye geçer, me süre aşımına uğrar (bot: 2, me: 0, maç 2-0 ile biter!)
        async.elapse(const Duration(milliseconds: 15200));
        async.flushMicrotasks();

        // Uygulama yeniden başlatılmış gibi YENİ bir LocalMatchHistoryRepository örneğiyle oku
        List<MatchHistoryEntry>? loaded;
        LocalMatchHistoryRepository().loadRecent().then((res) {
          loaded = res;
        });
        async.flushMicrotasks();

        expect(loaded, isNotNull);
        expect(loaded!.length, 1);
        expect(loaded!.first.opponentName, 'Normal Bot Rakip');
        expect(loaded!.first.endType, MatchEndType.normal);
        expect(loaded!.first.result, MatchResult.lose);
        expect(loaded!.first.botlaOynandi, isTrue);

        container.dispose();
      });
    },
  );
}


