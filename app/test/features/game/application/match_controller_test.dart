import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/data/question_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_filter.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

class CustomMaskingTextFilter implements TextFilter {
  final Set<String> blockedWords;
  const CustomMaskingTextFilter(this.blockedWords);

  @override
  String apply(String text) {
    var result = text;
    for (final word in blockedWords) {
      result = result.replaceAll(word, '***');
    }
    return result;
  }
}

class FakeClock implements GameClock {
  final Object _asyncObject;
  final int baseMs;

  FakeClock(this._asyncObject, {this.baseMs = 1000});

  @override
  int nowMs() {
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
                wrongBeforeChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

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

    test('Bot wrongBeforeChance ile önce yanlış dener, sıra bota kalır, sonra doğru cevapla sıra kullanıcıya geçer', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(7)),
            questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 3000,
                thinkMaxMs: 3000,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 1.0, // Her zaman önce yanlış dene
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // Kullanıcı doğru cevap verir -> Sıra bota geçer
        controller.submit('elma');
        var state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'bot');

        // 1. Bot ilk (yanlış) eylemini yapar (delay1 en fazla 2300 ms'dir)
        async.elapse(const Duration(milliseconds: 2400));
        state = container.read(matchControllerProvider);
        // İlk eylem yapıldı: WrongAnswer
        expect(state.recentEvents.last, isA<WrongAnswer>());
        // Sıra HALA botta olmalı (yeni kural gereği yanlış cevap sırayı değiştirmez)
        expect(state.matchState!.turnPlayerId, 'bot');

        // 2. Bot sıradaki doğru eylemini yapar (toplam süre 3000 ms tamamlanır)
        async.elapse(const Duration(milliseconds: 700));
        state = container.read(matchControllerProvider);
        expect(state.recentEvents.last, isA<AnswerAccepted>());
        // Artık sıra kullanıcıya geçmiş olmalıdır
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.isMyTurn, isTrue);

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
                answerSeconds: 20,
                graceMs: 0,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        var state = container.read(matchControllerProvider);
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.scores['bot'], 0);
        expect(state.matchState!.scores['me'], 0);

        // Kullanıcı cevap vermeden 15 saniyeyi geçirir (200ms periyodik tick kontrol eder)
        async.elapse(const Duration(milliseconds: 20200));

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

    test('Kullanıcı yanlış cevap verince tur bitmez, sıra ve süre korunur, ardından doğru cevap verip sırayı geçirebilir', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // Yanlış cevap gönderilir
        controller.submit('tamamen_yanlis_ve_alakasiz_bir_cevap');

        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.recentEvents.last, isA<WrongAnswer>());

        // 700 ms bekleyip ardından doğru cevap gönderilir (600ms sınırını geçmek için)
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('elma');

        state = container.read(matchControllerProvider);
        expect(state.recentEvents.last, isA<AnswerAccepted>());
        expect(state.isMyTurn, isFalse);
        expect(state.matchState!.turnPlayerId, 'bot');

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
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // Süre aşımı ile turu bitir
        async.elapse(const Duration(milliseconds: 20200));

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

    test('2-0 durumunda 2. tur sonunda maç biter (matchFinished), ara tur sonu atlanır ve 500 ms sonra maç sonu ekranı açılır', () {
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
                wrongBeforeChance: 0.0,
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                roundsToWin: 2,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // 1. Tur: Sıra me'de. Süre aşımı ile Bot 1-0 kazanır
        async.elapse(const Duration(milliseconds: 20200));
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

        // Me süre aşımına uğrar -> Bot 2-0 kazanır.
        // Best of 3 kuralı: 2 galibiyete ulaşıldığı için motor matchFinished yapar, 3. tur oynanmaz!
        async.elapse(const Duration(milliseconds: 20200));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.scores['bot'], 2);
        expect(state.matchState!.scores['me'], 0);
        // Maçı bitiren turda ara tur sonu ekranı (isRoundEnded) gösterilmez!
        // 500 ms boyunca tahta aktif kalır, isRoundEnded false'tur:
        expect(state.isRoundEnded, isFalse);
        expect(state.isMatchFinished, isFalse);

        // 500 ms sonra maç sonucu ekranı açılır:
        async.elapse(const Duration(milliseconds: 500));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.matchFinished);
        expect(state.isRoundEnded, isFalse);
        expect(state.isMatchFinished, isTrue);
        expect(state.summary, isNotNull);
        expect(state.summary!.winnerId, 'bot');
        expect(state.summary!.scores['bot'], 2);
        expect(state.summary!.scores['me'], 0);
        expect(state.summary!.roundHistory.length, 2);

        container.dispose();
      });
    });

    test('1-1 durumunda 3. tur oynanır ve 2-1 ile maç biter, son turda ara tur sonu atlanır', () {
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
                baseKnowChance: 0.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 0.0,
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                roundsToWin: 2,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // 1. Tur: Sıra me'de. Me süre aşımına uğrar -> Bot 1-0 kazanır
        async.elapse(const Duration(milliseconds: 20000));
        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 1);
        expect(state.isFinalReveal, isFalse);

        // 3 saniye geçiş -> Tur 2 başlar
        async.elapse(const Duration(milliseconds: 3000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.turnPlayerId, 'bot');

        // 2. Tur: Sıra botta. Bot bilmediği için cevap vermez, süre aşımına uğrar -> Me 1-1 yapar
        async.elapse(const Duration(milliseconds: 20000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['bot'], 1);
        expect(state.matchState!.scores['me'], 1);
        expect(state.isFinalReveal, isFalse);

        // 3 saniye geçiş -> 1-1 olduğu için 3. Tur başlar!
        async.elapse(const Duration(milliseconds: 3000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.turnPlayerId, 'me');

        // 3. Tur: Sıra me'de. Me süre aşımına uğrar -> Bot 2-1 kazanır ve maç biter!
        async.elapse(const Duration(milliseconds: 20000));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.scores['bot'], 2);
        expect(state.matchState!.scores['me'], 1);
        expect(state.isRoundEnded, isFalse);
        expect(state.isMatchFinished, isFalse);

        // 500 ms sonra maç sonucu ekranı açılır:
        async.elapse(const Duration(milliseconds: 500));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.matchFinished);
        expect(state.isRoundEnded, isFalse);
        expect(state.isMatchFinished, isTrue);
        expect(state.summary, isNotNull);
        expect(state.summary!.winnerId, 'bot');
        expect(state.summary!.scores['bot'], 2);
        expect(state.summary!.scores['me'], 1);
        expect(state.summary!.roundHistory.length, 3);

        container.dispose();
      });
    });

    test('leaveMatch() çağrıldığında maçı hemen terk eder ve rakip kazanır (forfeit)', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        controller.leaveMatch();

        final state = container.read(matchControllerProvider);
        expect(state.isMatchFinished, isTrue);
        expect(state.matchState!.phase, MatchPhase.matchFinished);
        expect(state.summary, isNotNull);
        expect(state.summary!.winnerId, 'bot');
        expect(state.matchState!.endedBy, 'forfeit');

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
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(opponentName: 'RepoBot', initialTurnPlayerId: 'me');
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
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'Bot1', initialTurnPlayerId: 'me');

        async.elapse(const Duration(milliseconds: 5000));
        var state = container.read(matchControllerProvider);
        expect(state.remainingMs, lessThanOrEqualTo(15000));

        // Yeniden maç başlat
        controller.startMatch(questions: sampleQuestions, opponentName: 'Bot2', initialTurnPlayerId: 'me');
        state = container.read(matchControllerProvider);
        expect(state.opponentName, 'Bot2');
        expect(state.remainingMs, 20000);
        expect(state.matchState!.scores['bot'], 0);
        expect(state.matchState!.scores['me'], 0);

        container.dispose();
      });
    });

    test('Tur içi tüm geçerli denemeler (doğru, yanlış) kronolojik olarak roundAttempts içinde tutulur', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
                minSubmitIntervalMs: 600,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // 1. Yanlış cevap
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('kesinlikle_yanlis_cevap');
        var state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 1);
        expect(state.roundAttempts.last.text, 'kesinlikle_yanlis_cevap');
        expect(state.roundAttempts.last.isCorrect, isFalse);
        expect(state.lastFeedback, MatchFeedbackType.wrong);

        // 2. Doğru cevap (mevcut sorunun ilk geçerli cevabı)
        final validAnswer = state.matchState!.currentQuestion!.answers.first.display;
        async.elapse(const Duration(milliseconds: 700));
        controller.submit(validAnswer);
        state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 2);
        expect(state.roundAttempts.last.text, validAnswer);
        expect(state.roundAttempts.last.isCorrect, isTrue);

        container.dispose();
      });
    });

    test('Tekrarlanan cevap (alreadySaid) aktif turda roundAttempts ve displayAttempts içine girmez, lastFeedback alreadySaid olur, ham motor kaydı korunur', () {
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
                wrongBeforeChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
                minSubmitIntervalMs: 600,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        var state = container.read(matchControllerProvider);
        expect(state.isMyTurn, isTrue);

        // 1. Kullanıcı kendi doğru cevabını verir ('elma')
        controller.submit('elma');
        state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 1);
        expect(state.roundAttempts.last.text, 'elma');
        expect(state.roundAttempts.last.isCorrect, isTrue);
        expect(state.isMyTurn, isFalse);

        // 2. Bot 1500 ms sonra kendi doğru cevabını verir
        async.elapse(const Duration(milliseconds: 1500));
        state = container.read(matchControllerProvider);
        expect(state.isMyTurn, isTrue);
        expect(state.roundAttempts.length, 2);
        final botAnswerText = state.roundAttempts.last.text;

        final currentVisibleCount = state.roundAttempts.length; // 2
        final currentEngineCount = state.matchState!.currentRoundAttempts.length; // 2

        // 3. Kullanıcı kendi daha önce verdiği cevabı ('elma') tekrar yazar
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('elma');
        state = container.read(matchControllerProvider);

        // Doğrulama: Geri bildirim tetiklendi
        expect(state.lastFeedback, MatchFeedbackType.alreadySaid);
        // Doğrulama: roundAttempts ve displayAttempts uzunluğu ARTMAZ (chat akışına girmez)
        expect(state.roundAttempts.length, currentVisibleCount);
        expect(state.displayAttempts.length, currentVisibleCount);
        expect(state.roundAttempts.any((a) => a.isRepeated), isFalse);
        // Doğrulama: Sıra ve süre korunur
        expect(state.isMyTurn, isTrue);
        // Doğrulama: Ham motor kaydında ise deneme saklanır
        expect(state.matchState!.currentRoundAttempts.length, currentEngineCount + 1);
        expect(state.matchState!.currentRoundAttempts.last.resultType, AttemptResultType.repeated);

        // 4. Kullanıcı rakibin verdiği cevabı (botAnswerText) tekrar yazar
        async.elapse(const Duration(milliseconds: 700));
        controller.submit(botAnswerText);
        state = container.read(matchControllerProvider);

        expect(state.lastFeedback, MatchFeedbackType.alreadySaid);
        expect(state.roundAttempts.length, currentVisibleCount);
        expect(state.displayAttempts.length, currentVisibleCount);
        expect(state.matchState!.currentRoundAttempts.length, currentEngineCount + 2);

        // 5. Yanlış cevap yazıldığında ise kırmızı balon olarak eklenmeye devam eder
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('tamamen_yanlis_cevap');
        state = container.read(matchControllerProvider);

        expect(state.lastFeedback, MatchFeedbackType.wrong);
        expect(state.roundAttempts.length, currentVisibleCount + 1);
        expect(state.displayAttempts.length, currentVisibleCount + 1);
        expect(state.roundAttempts.last.isCorrect, isFalse);

        container.dispose();
      });
    });

    test('Rakibin denemeleri TextFilter filtresinden geçirilir', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        // Filtrede sesli harfleri maskeleyen filtre
        final customFilter = CustomMaskingTextFilter({'a', 'e', 'i', 'o', 'u'});
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            textFilterProvider.overrideWithValue(customFilter),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 0.0,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        var state = container.read(matchControllerProvider);
        final validAnswer = state.matchState!.currentQuestion!.answers.first.display;

        // Me -> doğru cevap verir, sıra bota geçer
        controller.submit(validAnswer);
        state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'bot');

        // Bot süresi geçene kadar bekle (bot düşünüp cevap versin)
        async.elapse(const Duration(milliseconds: 2000));
        state = container.read(matchControllerProvider);

        // Bot cevap vermiş olmalı ve TextFilter uygulanmış olmalı
        final botAttempts = state.roundAttempts.where((a) => a.playerId != 'me').toList();
        expect(botAttempts.isNotEmpty, isTrue);
        for (final attempt in botAttempts) {
          expect(attempt.text.contains('***'), isTrue);
        }

        container.dispose();
      });
    });

    test('submit() metni AttemptTextSanitizer ile temizler ve 40 karaktere kırpar', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // Başı-sonu boşluklu ve ardışık boşluklu yanlış metin
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('   yanlış    deneme   ');
        var state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 1);
        expect(state.roundAttempts.first.text, 'yanlış deneme');

        container.dispose();
      });
    });

    test('Yok sayılan denemeler (ignored: tooFast) roundAttempts listesine eklenmez', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
                minSubmitIntervalMs: 600,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(questions: sampleQuestions, opponentName: 'TestBot', initialTurnPlayerId: 'me');

        // İlk deneme (yanlış)
        async.elapse(const Duration(milliseconds: 700));
        controller.submit('yanlış1');
        var state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 1);

        // 100 ms sonra tekrar deneme (tooFast, 600 ms altında)
        async.elapse(const Duration(milliseconds: 100));
        controller.submit('yanlış2');
        state = container.read(matchControllerProvider);
        // Sayı artmamalı!
        expect(state.roundAttempts.length, 1);
        expect(state.roundAttempts.first.text, 'yanlış1');

        container.dispose();
      });
    });

    test('Botun yakın denemesi aktif turda roundAttempts listesinde gizlenir, tur bitince açılır', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
                nearMissPerRound: 1,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        final customQ = Question(
          id: 'q_custom',
          categoryId: 'araba',
          text: 'Araba Markaları',
          answers: const [
            Answer(id: 'audi', display: 'Audi', aliases: ['audi']),
            Answer(id: 'ferrari', display: 'Ferrari', aliases: ['ferrari']),
          ],
        );
        controller.startMatch(questions: [customQ], opponentName: 'TestBot', initialTurnPlayerId: 'me');

        var state = container.read(matchControllerProvider);

        // Kendi doğru cevabımı verip sırayı bota geçir
        controller.submit('Audi');
        state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'bot');

        // Botun 'ferari' yakın denemesi (Ferrari'ye 1 mesafe, isClose = true) yapıldığını simüle et
        final engineRes = MatchEngine.submit(
          state: state.matchState!,
          playerId: 'bot',
          rawInput: 'ferari',
          nowMs: fakeClock.nowMs(),
        );
        controller.applyEngineResultForTesting(engineRes);
        state = container.read(matchControllerProvider);

        // Aktif turdayken botun yakın denemesi kullanıcının (me) roundAttempts listesinde GİZLİ OLMALIDIR!
        expect(state.roundAttempts.any((a) => a.text == 'ferari'), isFalse);

        // Turu süre aşımıyla bitir
        final timeoutRes = MatchEngine.checkTimeout(
          state: state.matchState!,
          nowMs: state.matchState!.deadlineMs + 100,
        );
        controller.applyEngineResultForTesting(timeoutRes);
        state = container.read(matchControllerProvider);

        // Tur bittiğinde (roundEnded) botun yakın denemesi artık listede GÖRÜNÜR OLMALIDIR!
        expect(state.roundAttempts.any((a) => a.text == 'ferari'), isTrue);

        container.dispose();
      });
    });

    test('Alias ile verilen doğru cevap roundAttempts içinde ana cevap (answer.display) olarak gösterilir, yanlış cevap yazıldığı gibi kalır, alias sonrası tekrar girişler gizlenir', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
                nearMissPerRound: 1,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        final customQ = Question(
          id: 'q_teams',
          categoryId: 'futbol',
          text: 'Futbol Takımları',
          answers: const [
            Answer(id: 'besiktas', display: 'Beşiktaş', aliases: ['besiktas', 'bjk']),
            Answer(id: 'galatasaray', display: 'Galatasaray', aliases: ['galatasaray', 'gs']),
            Answer(id: 'fenerbahce', display: 'Fenerbahçe', aliases: ['fenerbahce', 'fb']),
          ],
        );
        controller.startMatch(questions: [customQ], opponentName: 'TestBot', initialTurnPlayerId: 'me');

        var state = container.read(matchControllerProvider);

        // 1. Yanlış cevap girildiğinde balon kullanıcının yazdığı metni korumalıdır
        controller.submit('yanlis_takim');
        state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 1);
        expect(state.roundAttempts.first.text, 'yanlis_takim');
        expect(state.roundAttempts.first.isCorrect, isFalse);

        // Cooldown süresi kadar ilerlet
        async.elapse(const Duration(milliseconds: 600));

        // 2. Alias ile doğru cevap ("bjk") girildiğinde displayText ("Beşiktaş") gösterilmelidir
        controller.submit('bjk');
        state = container.read(matchControllerProvider);
        expect(state.roundAttempts.length, 2);
        final correctAttempt = state.roundAttempts.last;
        expect(correctAttempt.isCorrect, isTrue);
        expect(correctAttempt.text, 'Beşiktaş');

        // Sıra bota geçti
        expect(state.matchState!.turnPlayerId, 'bot');

        // Bot 1500 ms sonra kalan cevaplardan birini ("Galatasaray" veya "Fenerbahçe") verir
        async.elapse(const Duration(milliseconds: 1500));
        state = container.read(matchControllerProvider);
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.roundAttempts.length, 3);
        final botAttempt = state.roundAttempts.last;
        expect(botAttempt.isCorrect, isTrue);

        // 3. Kullanıcı kendi daha önce verdiği cevabın ana yazımını ("Beşiktaş") tekrar yazar
        controller.submit('Beşiktaş');
        state = container.read(matchControllerProvider);

        // Doğrulama: Geri bildirim alreadySaid tetiklendi
        expect(state.lastFeedback, MatchFeedbackType.alreadySaid);
        // Doğrulama: Tekrarlanan cevap aktif turda roundAttempts listesine eklenmez (uzunluk 3 kalır)
        expect(state.roundAttempts.length, 3);
        expect(state.displayAttempts.length, 3);
        expect(state.roundAttempts.any((a) => a.isRepeated), isFalse);

        // Cooldown sonrası başka bir alias ("besiktas") ile tekrar denenirse de gizli kalmalı
        async.elapse(const Duration(milliseconds: 600));
        controller.submit('besiktas');
        state = container.read(matchControllerProvider);
        expect(state.lastFeedback, MatchFeedbackType.alreadySaid);
        expect(state.roundAttempts.length, 3);

        container.dispose();
      });
    });

    test('Bilmeyen bot tur boyunca en fazla 1 yanlış deneme yapar, asla peş peşe 2 hatalı mesaj atmaz ve süre aşımına kadar bekler', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(42)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 0.0,
                extraKnowChance: 0.0,
                wrongAnswerChance: 1.0, // Her zaman yanlış deneme yapsın
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                roundsToWin: 2,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'M-1234',
          initialTurnPlayerId: 'bot',
        );

        // 1500ms sonra bot tam olarak 1 yanlış cevap gönderir
        async.elapse(const Duration(milliseconds: 1600));
        var state = container.read(matchControllerProvider);
        final rawBotAttempts = state.matchState!.currentRoundAttempts.where((a) => a.playerId == 'bot').toList();

        // Tam olarak 1 yanlış/yakın deneme olmalı, asla 2 değil ve doğru olmamalı
        expect(rawBotAttempts.length, 1);
        expect(rawBotAttempts.first.resultType, isNot(equals(AttemptResultType.correct)));

        // Tur sonuna kadar (19.000 ms daha) bekletilir: Bot başka hiçbir şey göndermez
        async.elapse(const Duration(milliseconds: 19000));
        state = container.read(matchControllerProvider);

        final finalRawBotAttempts = state.matchState!.currentRoundAttempts.where((a) => a.playerId == 'bot').toList();
        expect(finalRawBotAttempts.length, 1, reason: 'Bot maç biterken ikinci bir hatalı deneme atmamalı!');
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.matchState!.scores['me'], 1);

        container.dispose();
      });
    });

    test('Tur veya maç bittiğinde bekleyen bot zamanlayıcıları iptal edilir ve süre bitiminden sonra bot mesajı gelmez', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 4000,
                thinkMaxMs: 4000,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                roundsToWin: 2,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'M-5555',
          initialTurnPlayerId: 'bot',
        );

        // Henüz 4000ms dolmadan (2000ms'de) maç terk edilir
        async.elapse(const Duration(milliseconds: 2000));
        controller.leaveMatch();

        var state = container.read(matchControllerProvider);
        expect(state.isMatchFinished, isTrue);

        // 5000ms daha bekletilir (botun 4000ms zamanlayıcısı bu sırada tetiklenmeye çalışsa bile iptal edilmiş olmalı)
        async.elapse(const Duration(milliseconds: 5000));
        state = container.read(matchControllerProvider);

        // Hiçbir bot cevabı kaydedilmemiş olmalı
        expect(state.matchState!.currentRoundAttempts, isEmpty);
        expect(state.acceptedAnswers, isEmpty);

        container.dispose();
      });
    });

    test('Tur süresinin son ~1.5 saniyesinde bot hiçbir zaman 1den fazla mesaj göndermez', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(99)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 13000,
                thinkMaxMs: 14500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 1.0, // wrongBefore tetiklense bile
              ),
            ),
            matchControllerProvider.overrideWith(
              () => MatchController(roundTransitionDelayMs: 3000),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                roundsToWin: 2,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'M-7777',
          initialTurnPlayerId: 'bot',
        );

        // 13.500 ms'ye kadar ilerlet (son 1.5 sn başlangıcı)
        async.elapse(const Duration(milliseconds: 13500));
        var state = container.read(matchControllerProvider);
        final attemptsBeforeLast1500 = state.matchState!.currentRoundAttempts.length;

        // Kalan 1.500 ms + süre aşımı toleransını ilerlet
        async.elapse(const Duration(milliseconds: 1700));
        state = container.read(matchControllerProvider);
        final attemptsAfterLast1500 = state.matchState!.currentRoundAttempts.length;

        final messagesInLast1500 = attemptsAfterLast1500 - attemptsBeforeLast1500;
        expect(messagesInLast1500, lessThanOrEqualTo(1),
            reason: 'Son 1.5 saniyede bot en fazla 1 mesaj gönderebilir!');

        container.dispose();
      });
    });

    test('preselectedQuestionId ile startMatch çağrılınca 1. tur sorusu tam o sorudur ve havuz karıştırma bunu ezemez', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        // Farklı seed'lerle 10 kez dene; her defasında q3 seçilmelidir
        for (int seed = 0; seed < 10; seed++) {
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(seed)),
              questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            ],
          );

          final controller = container.read(matchControllerProvider.notifier);
          controller.startMatch(
            questions: sampleQuestions,
            opponentName: 'Bot Rakip',
            preselectedQuestionId: 'q3',
          );

          final matchState = container.read(matchControllerProvider).matchState;
          expect(matchState, isNotNull);
          expect(matchState!.currentQuestion, isNotNull);
          expect(matchState.currentQuestion!.id, equals('q3'));
          expect(matchState.currentQuestion!.text, equals('Şehirler'));

          container.dispose();
        }
      });
    });

    test('Yerel bot maçında: roundEnded fazındaki nextQuestionText ve nextQuestionId sonraki turda oynanan soruyla BİREBİR AYNIDIR', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(42)),
            questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1000,
                thinkMaxMs: 1000,
                baseKnowChance: 0.0,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'TestBot',
          initialTurnPlayerId: 'bot',
        );

        // 1. Tur botun süre aşımıyla biter (21 sn)
        async.elapse(const Duration(milliseconds: 21000));

        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundEnded);
        expect(state.nextQuestionText, isNotNull);
        expect(state.nextQuestionId, isNotNull);

        final expectedNextId = state.nextQuestionId;
        final expectedNextText = state.nextQuestionText;

        // 3.5 sn geçiş süresi tamamlanır ve 2. tur başlar
        async.elapse(const Duration(milliseconds: 3550));

        state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.matchState!.currentQuestion!.id, equals(expectedNextId));
        expect(state.matchState!.currentQuestion!.text, equals(expectedNextText));

        // 2. tur başladığında nextQuestion temizlenmiştir
        expect(state.nextQuestionText, isNull);
        expect(state.nextQuestionId, isNull);

        container.dispose();
      });
    });
  });
}
