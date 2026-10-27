import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/data/question_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Question> sampleQuestions;

  setUp(() {
    sampleQuestions = [
      _createQuestion('q1', 'Meyveler', ['elma', 'armut', 'muz']),
      _createQuestion('q2', 'Hayvanlar', ['kedi', 'köpek', 'kuş']),
      _createQuestion('q3', 'Şehirler', ['ankara', 'istanbul', 'izmir']),
    ];
  });

  ProviderContainer createContainer({
    required FakeClock clock,
    int thinkMs = 1500,
    int answerSeconds = 15,
  }) {
    return ProviderContainer(
      overrides: [
        gameClockProvider.overrideWithValue(clock),
        randomProvider.overrideWithValue(math.Random(42)),
        questionRepositoryProvider.overrideWithValue(FakeQuestionRepository(sampleQuestions)),
        botConfigProvider.overrideWithValue(
          BotConfig(
            thinkMinMs: thinkMs,
            thinkMaxMs: thinkMs,
            baseKnowChance: 1.0,
            extraKnowChance: 0.0,
            wrongBeforeChance: 0.0,
          ),
        ),
        matchConfigProvider.overrideWithValue(
          MatchConfig(
            answerSeconds: answerSeconds,
            roundsToWin: 2,
          ),
        ),
      ],
    );
  }

  group('BULGU-4: MatchController Arka Plan (Lifecycle) & Duraklatma Testleri', () {
    test('1. Observer yaşam döngüsü: tek kayıt, leave/finish/dispose ile kaldırılma ve eski controller yalıtımı', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container1 = createContainer(clock: clock);
        final controller1 = container1.read(matchControllerProvider.notifier);

        // Başlangıçta kayıtlı değil
        expect(controller1.isObserverRegisteredForTesting, isFalse);

        // startMatch ile tam olarak bir kez kaydedilir
        controller1.startMatch();
        async.flushMicrotasks();
        expect(controller1.isObserverRegisteredForTesting, isTrue);

        // Tekrar startMatch çağrılsa bile çift kayıt olmaz
        controller1.startMatch();
        async.flushMicrotasks();
        expect(controller1.isObserverRegisteredForTesting, isTrue);

        // leaveMatch ile observer kaldırılır
        controller1.leaveMatch();
        expect(controller1.isObserverRegisteredForTesting, isFalse);

        // İkinci maç başlatılır
        controller1.startMatch();
        async.flushMicrotasks();
        expect(controller1.isObserverRegisteredForTesting, isTrue);

        // Controller dispose edildiğinde observer kaldırılır
        container1.dispose();
        expect(controller1.isObserverRegisteredForTesting, isFalse);

        // İkinci container (ardışık yeni maç) oluşturulur
        final container2 = createContainer(clock: clock);
        final controller2 = container2.read(matchControllerProvider.notifier);
        controller2.startMatch();
        async.flushMicrotasks();
        expect(controller2.isObserverRegisteredForTesting, isTrue);

        // Eski dispose edilmiş controller1'e lifecycle olayı gelirse hiçbir şeyi değiştirmez
        controller1.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        expect(controller1.isPausedForTesting, isFalse);

        container2.dispose();
      });
    });

    test('2. Kullanıcı sırasında paused iken süre akmaz, resumed sonrası kalan süreyle devam eder', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container = createContainer(clock: clock, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // Maç başladı, sıra kullanıcıda ('me'), toplam 15.000 ms
        expect(controller.state.matchState?.turnPlayerId, 'me');
        expect(controller.state.matchState?.phase, MatchPhase.roundActive);

        // 3 saniye geçer (tick timer çalışır)
        async.elapse(const Duration(seconds: 3));
        expect(controller.state.remainingMs, 12000);

        // Uygulama arka plana gider (paused)
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        expect(controller.isPausedForTesting, isTrue);

        // Arka planda 20 saniye geçer (duvar saati 20 sn ilerler)
        async.elapse(const Duration(seconds: 20));

        // Arka plandayken timeout olmamalıdır, faz hala roundActive kalmalıdır
        expect(controller.state.matchState?.phase, MatchPhase.roundActive);

        // Uygulama öne gelir (resumed)
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.isPausedForTesting, isFalse);

        // Kalan süre hala ~12.000 ms'dir (20 saniyelik arka plan süresi tüketmemiştir!)
        expect(controller.state.remainingMs, 12000);

        // Şimdi 6 saniye normal akar -> kalan 6 sn
        async.elapse(const Duration(seconds: 6));
        expect(controller.state.remainingMs, 6000);

        // 6.5 saniye daha geçer -> 12 saniyelik hak dolunca normal timeout gerçekleşir
        async.elapse(const Duration(milliseconds: 6500));
        expect(controller.state.matchState?.phase, MatchPhase.roundEnded);
      });
    });

    test('3. Bot düşünme gecikmesi sırasında paused olunca bot hamlesi yapılmaz, resumed sonrası kalan süreyle hamle gelir', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        // Bot düşünme süresi 2000 ms
        final container = createContainer(clock: clock, thinkMs: 2000, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // Kullanıcı doğru cevap verir -> sıra bota geçer
        controller.submit('elma');
        expect(controller.state.matchState?.turnPlayerId, 'bot');

        // Bot düşünmeye başladı; 800 ms geçer
        async.elapse(const Duration(milliseconds: 800));
        // Henüz bot cevap vermedi
        expect(controller.state.acceptedAnswers.length, 1);

        // Uygulama inactive (örn. bildirim çekmecesi) olur
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.inactive);
        expect(controller.isPausedForTesting, isTrue);

        // Arka planda 10 saniye geçer
        async.elapse(const Duration(seconds: 10));

        // Bot arka plandayken ASLA hamle yapmamıştır
        expect(controller.state.acceptedAnswers.length, 1);
        expect(controller.state.matchState?.turnPlayerId, 'bot');

        // Uygulama öne gelir (resumed)
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.isPausedForTesting, isFalse);

        // Kalan 1200 ms düşünme süresinden 600 ms geçer -> hala cevap yok
        async.elapse(const Duration(milliseconds: 600));
        expect(controller.state.acceptedAnswers.length, 1);

        // Kalan 650 ms daha geçer -> 1200 ms tamamlanır ve bot cevabı gelir!
        async.elapse(const Duration(milliseconds: 650));
        expect(controller.state.acceptedAnswers.length, 2);
        expect(controller.state.matchState?.turnPlayerId, 'me');
      });
    });

    test('4. Tur sonu geçişinde (roundEnded 3000ms) paused olunca yeni tur arka planda başlamaz, dönüşte kalan süreyle başlar', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container = createContainer(clock: clock, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // Kullanıcı timeout olsun -> tur biter (roundEnded, 3000 ms geçiş süresi)
        async.elapse(const Duration(milliseconds: 15500));
        expect(controller.state.matchState?.phase, MatchPhase.roundEnded);
        expect(controller.state.roundTransitionRemainingMs, greaterThan(0));

        // 1000 ms geçişten sonra paused olur
        async.elapse(const Duration(milliseconds: 1000));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        expect(controller.isPausedForTesting, isTrue);

        // Arka planda 15 saniye bekletilir
        async.elapse(const Duration(seconds: 15));

        // Arka planda yeni tur başlamaz, hala roundEnded kalır
        expect(controller.state.matchState?.phase, MatchPhase.roundEnded);

        // Öne gelinir (resumed)
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.isPausedForTesting, isFalse);

        // Kalan ~2000 ms geçiş süresinden 1000 ms geçer -> hala roundEnded
        async.elapse(const Duration(milliseconds: 1000));
        expect(controller.state.matchState?.phase, MatchPhase.roundEnded);

        // Kalan 1100 ms daha geçer -> 2. tur başlar!
        async.elapse(const Duration(milliseconds: 1100));
        expect(controller.state.matchState?.phase, MatchPhase.roundActive);
      });
    });

    test('5. Çoklu paused / resumed döngüsünde kümülatif süre doğru korunur', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container = createContainer(clock: clock, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // 1. Döngü: 2 sn oyna (kalan 13 sn), 5 sn duraklat
        async.elapse(const Duration(seconds: 2));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.inactive);
        async.elapse(const Duration(seconds: 5));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.state.remainingMs, 13000);

        // 2. Döngü: 3 sn daha oyna (kalan 10 sn), 10 sn duraklat
        async.elapse(const Duration(seconds: 3));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        async.elapse(const Duration(seconds: 10));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.state.remainingMs, 10000);

        // 3. Döngü: 4 sn daha oyna (kalan 6 sn), 7 sn duraklat
        async.elapse(const Duration(seconds: 4));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.hidden);
        async.elapse(const Duration(seconds: 7));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.state.remainingMs, 6000);

        // Kalan 6 sn normal akar
        async.elapse(const Duration(milliseconds: 6500));
        expect(controller.state.matchState?.phase, MatchPhase.roundEnded);
      });
    });

    test('6. Maç bittikten sonra gelen lifecycle olayları zararsızdır (no-op)', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container = createContainer(clock: clock, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // Maçı forfeit ile bitir
        controller.leaveMatch();
        expect(controller.state.matchState?.phase, MatchPhase.matchFinished);
        expect(controller.isObserverRegisteredForTesting, isFalse);

        final stateAfterFinish = controller.state;

        // Maç bittikten sonra paused / resumed gelirse hiçbir şey değişmez
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        expect(controller.isPausedForTesting, isFalse);

        async.elapse(const Duration(seconds: 5));

        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        expect(controller.state, equals(stateAfterFinish));
      });
    });

    test('7. Duraklatılmışken savunmacı kontroller: kullanıcı submit yapamaz, motor timeout üretemez', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final container = createContainer(clock: clock, answerSeconds: 15);
        addTearDown(container.dispose);
        final controller = container.read(matchControllerProvider.notifier);

        controller.startMatch();
        async.flushMicrotasks();

        // 2 saniye sonra duraklatılır
        async.elapse(const Duration(seconds: 2));
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.paused);
        expect(controller.isPausedForTesting, isTrue);

        // Duraklatılmışken submit çağrılır
        controller.submit('elma');

        // Cevap işlenmemiştir, kabul edilenler listesi boştur
        expect(controller.state.acceptedAnswers, isEmpty);
        expect(controller.state.roundAttempts, isEmpty);

        // 30 saniye boyunca motor timeout üretmez
        async.elapse(const Duration(seconds: 30));
        expect(controller.state.matchState?.phase, MatchPhase.roundActive);

        // Devam ettirilince submit çalışabilir
        controller.handleAppLifecycleStateForTesting(AppLifecycleState.resumed);
        controller.submit('elma');
        expect(controller.state.acceptedAnswers.length, 1);
      });
    });
  });
}
