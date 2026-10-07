import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/data/question_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

class FakeClock implements GameClock {
  final Object _asyncObject;
  final int baseMs;

  FakeClock(this._asyncObject, {this.baseMs = 1000});

  @override
  int nowMs() {
    // FakeAsync provides elapsed Duration
    final elapsed = (_asyncObject as dynamic).elapsed as Duration;
    return baseMs + elapsed.inMilliseconds;
  }
}

class FakeQuestionRepository implements QuestionRepository {
  final List<Question> questions;

  const FakeQuestionRepository(this.questions);

  @override
  Future<List<Question>> loadAll() async => questions;
}

Question _createQuestion(String id, String text, List<String> answers) {
  return Question(
    id: id,
    categoryId: 'test_category',
    text: text,
    answers: answers.map((a) {
      final norm = TextNormalizer.normalize(a);
      return Answer(
        id: norm,
        display: a,
        aliases: [norm],
      );
    }).toList(),
  );
}

void main() {
  late List<Question> sampleQuestions;

  setUp(() {
    sampleQuestions = [
      _createQuestion('q1', 'Meyveler', ['elma', 'armut', 'muz', 'çilek', 'kavun']),
      _createQuestion('q2', 'Hayvanlar', ['kedi', 'köpek', 'kuş', 'at', 'aslan']),
      _createQuestion('q3', 'Şehirler', ['ankara', 'istanbul', 'izmir', 'bursa', 'antalya']),
      _createQuestion('q4', 'Renkler', ['mavi', 'kırmızı', 'sarı', 'yeşil', 'beyaz']),
    ];
  });

  group('MatchController Tests (fakeAsync)', () {
    test('Kullanıcı doğru cevap yazınca sıra bota geçer, bot gecikme sonrası cevap verir ve sıra tekrar kullanıcıya döner', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        var state = container.read(matchControllerProvider);
        expect(state.isLoading, isFalse);
        expect(state.matchState, isNotNull);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.turnPlayerId, 'me');

        // 1. Kullanıcı doğru bir cevap yazar
        controller.submit('elma');
        state = container.read(matchControllerProvider);

        expect(state.isMyTurn, isFalse);
        expect(state.matchState!.turnPlayerId, 'bot');
        expect(state.matchState!.usedAnswerIds, contains('elma'));

        // 2. 1000 ms ilerlet (bot henüz 1500 ms süresini doldurmadı)
        async.elapse(const Duration(milliseconds: 1000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'bot');

        // 3. 500 ms daha ilerlet (toplam 1500 ms, bot cevabını verir)
        async.elapse(const Duration(milliseconds: 500));
        state = container.read(matchControllerProvider);

        // Sıra tekrar kullanıcıya dönmüş olmalı
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.matchState!.usedAnswerIds.length, 2);

        container.dispose();
      });
    });

    test('Kullanıcı süre aşımına uğrayınca tur bot lehine biter', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                graceMs: 0,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        var state = container.read(matchControllerProvider);
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.scores['bot'], 0);
        expect(state.matchState!.scores['me'], 0);

        // Kullanıcı cevap vermeden 15 saniyeyi geçirir (200ms periyodik tick kontrol eder)
        async.elapse(const Duration(milliseconds: 15200));

        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 1);
        expect(state.matchState!.scores['me'], 0);
        expect(state.recentEvents.last, isA<RoundWon>());
        final lastWon = state.recentEvents.last as RoundWon;
        expect(lastWon.winnerId, 'bot');
        expect(lastWon.reason, RoundEndReason.timeout);

        container.dispose();
      });
    });

    test('Kullanıcı yanlış cevap verince tur hemen biter', () {
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
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        controller.submit('tamamen_yanlis_ve_alakasiz_bir_cevap');

        final state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 1);
        expect(state.matchState!.scores['me'], 0);

        final lastWon = state.recentEvents.last as RoundWon;
        expect(lastWon.winnerId, 'bot');
        expect(lastWon.reason, RoundEndReason.wrong);

        container.dispose();
      });
    });

    test('Tur bittikten sonra (roundTransitionDelayMs) otomatik olarak bir sonraki tur başlar', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        // Yanlış cevap ile turu hemen bitir
        controller.submit('yanlis_cevap_123');

        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);

        // 2000 ms sonra henüz geçiş yapılmamış olmalı
        async.elapse(const Duration(milliseconds: 2000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);

        // 1000 ms daha ilerlet (toplam 3000 ms): 2. tur otomatik başlar
        async.elapse(const Duration(milliseconds: 1000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.totalRoundsPlayed, 1);

        container.dispose();
      });
    });

    test('3 sonuçlanan tur sonunda maç biter (matchFinished) ve summary üretilir', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(42)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1000,
                thinkMaxMs: 1000,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        // 1. Tur: Sıra me'de. Me yanlış cevap verir -> Bot 1-0 kazanır
        controller.submit('yanlis_1');
        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 1);

        // 3 saniye geçiş
        async.elapse(const Duration(milliseconds: 3000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.turnPlayerId, 'bot');

        // 2. Tur: Sıra botta. Bot 1000 ms sonra doğru cevap verir
        async.elapse(const Duration(milliseconds: 1000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'me');

        // Me yanlış cevap verir -> Bot 2-0 kazanır
        controller.submit('yanlis_2');
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 2);

        // 3 saniye geçiş
        async.elapse(const Duration(milliseconds: 3000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.turnPlayerId, 'me');

        // 3. Tur: Sıra me'de. Me yanlış cevap verir -> Bot 3-0 kazanır
        controller.submit('yanlis_3');

        // Artık 3 sonuçlanan tur bitti (bot: 3, me: 0) -> MatchFinished!
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.matchFinished);
        expect(state.isMatchFinished, isTrue);
        expect(state.summary, isNotNull);
        expect(state.summary!.winnerId, 'bot');
        expect(state.summary!.scores['bot'], 3);
        expect(state.summary!.scores['me'], 0);
        expect(state.summary!.roundHistory.length, 3);

        container.dispose();
      });
    });

    test('Bot bilmediğinde süre aşımına uğrar ve tur kullanıcı lehine biter', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                baseKnowChance: 0.0,
                extraKnowChance: 0.0,
                wrongAnswerChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot');

        // Kullanıcı doğru cevap verir -> Sıra bota geçer
        controller.submit('elma');
        var state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'bot');

        // Bot cevap bilmediği için zamanlayıcı kurulmaz, 15200 ms sonra süre aşımına uğrar
        async.elapse(const Duration(milliseconds: 15200));

        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['me'], 1);
        expect(state.matchState!.scores['bot'], 0);

        final lastWon = state.recentEvents.last as RoundWon;
        expect(lastWon.winnerId, 'me');
        expect(lastWon.reason, RoundEndReason.timeout);

        container.dispose();
      });
    });

    test('startMatch() soru belirtilmeden çağrıldığında QuestionRepository.loadAll() üzerinden çalışır', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(opponentName: 'RepoBot');
        async.flushMicrotasks();

        final state = container.read(matchControllerProvider);
        expect(state.isLoading, isFalse);
        expect(state.matchState, isNotNull);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.opponentName, 'RepoBot');

        container.dispose();
      });
    });

    test('Tekrar startMatch() çağrıldığında eski zamanlayıcılar iptal edilir ve yeni maç başlar', () {
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
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'Bot1');

        async.elapse(const Duration(milliseconds: 5000));
        var state = container.read(matchControllerProvider);
        expect(state.remainingMs, lessThanOrEqualTo(10000));

        // Yeniden maç başlat
        controller.startMatch(questions: sampleQuestions, opponentName: 'Bot2');
        state = container.read(matchControllerProvider);
        expect(state.opponentName, 'Bot2');
        expect(state.remainingMs, 15000);
        expect(state.matchState!.scores['bot'], 0);
        expect(state.matchState!.scores['me'], 0);

        container.dispose();
      });
    });
  });
}
