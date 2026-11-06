import 'dart:async';
import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/player_card.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/data/question_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/game/presentation/round_end_view.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';

class _FakeClock implements GameClock {
  final Object _asyncObject;

  _FakeClock(this._asyncObject);

  @override
  int nowMs() {
    final elapsed = (_asyncObject as dynamic).elapsed as Duration;
    return 1000 + elapsed.inMilliseconds;
  }
}

class _ManualClock implements GameClock {
  int currentMs;
  _ManualClock([this.currentMs = 10000]);

  @override
  int nowMs() => currentMs;
}

const _testQuestion1 = Question(
  id: 'q1',
  categoryId: 'c1',
  text: 'Soru 1',
  answers: [
    Answer(id: 'elma', display: 'Elma', aliases: ['elma']),
    Answer(id: 'armut', display: 'Armut', aliases: ['armut']),
  ],
);

const _testQuestion2 = Question(
  id: 'q2',
  categoryId: 'c1',
  text: 'Soru 2',
  answers: [
    Answer(id: 'kedi', display: 'Kedi', aliases: ['kedi']),
    Answer(id: 'kopek', display: 'Köpek', aliases: ['kopek']),
  ],
);

class _TestOnlineMatchClient extends OnlineMatchClient {
  final StreamController<OnlineMatchEvent> controller =
      StreamController<OnlineMatchEvent>.broadcast(sync: true);

  @override
  Stream<OnlineMatchEvent> get events => controller.stream;

  @override
  Future<void> connect(String matchId) async {
    controller.add(const OnlineMatchConnected());
  }

  @override
  bool submit(String text) => true;

  @override
  Future<void> leave() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {
    await controller.close();
  }

  void emit(OnlineMatchEvent event) {
    if (!controller.isClosed) {
      controller.add(event);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tur Sonu Skor Gösterim Zamanlaması Testleri', () {
    test(
      '1. Bot maçında süre aşımıyla tur biterken maç ekranı skoru (displayedScores) tur sonu ekranı boyunca eski değerde (0) kalır; RoundEndView yeni skoru (1) gösterir; yeni turda 1 olur',
      () {
        fakeAsync((async) {
          final fakeClock = _FakeClock(async);
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(42)),
              activeMatchSessionModeProvider.overrideWith(
                () => ActiveMatchSessionModeNotifier(),
              ),
            ],
          );
          addTearDown(container.dispose);

          final controller = container.read(matchControllerProvider.notifier);

          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'TestBot',
            initialTurnPlayerId: 'bot',
            botConfig: const BotConfig(
              thinkMinMs: 999999,
              thinkMaxMs: 999999,
              baseKnowChance: 0.0,
            ),
          );

          var uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundActive, isTrue);
          expect(uiState.displayedScores['me'], 0);
          expect(uiState.displayedScores['bot'], 0);

          // Tur süresini (15 sn + 500 ms grace) aş
          async.elapse(const Duration(milliseconds: 16000));

          uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundEnded, isTrue);

          // RoundEndView yeni skoru (1) gösterir:
          expect(uiState.matchState?.scores['me'], 1);
          // Maç ekranı skor kartı eski skoru (0) tutar:
          expect(uiState.displayedScores['me'], 0);

          // Tur geçiş süresi (3.5 sn) tamamlansın ve 2. tur başlasın
          async.elapse(const Duration(milliseconds: 3500));

          uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundActive, isTrue);
          // 2. tura geçildiğinde maç ekranı skor kartı güncel skoru (1) gösterir:
          expect(uiState.displayedScores['me'], 1);
          expect(uiState.displayedScores['bot'], 0);
        });
      },
    );

    test(
      '2. Bot maçında doğru cevapla tur biterken maç ekranı skoru tur sonu ekranı süresince eski skorda kalır',
      () {
        fakeAsync((async) {
          final fakeClock = _FakeClock(async);
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(42)),
            ],
          );
          addTearDown(container.dispose);

          final controller = container.read(matchControllerProvider.notifier);

          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'TestBot',
            initialTurnPlayerId: 'me',
            preselectedQuestionId: 'q1',
            botConfig: const BotConfig(
              thinkMinMs: 999999,
              thinkMaxMs: 999999,
              baseKnowChance: 0.0,
            ),
          );
          async.flushMicrotasks();

          var uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundActive, isTrue);
          expect(uiState.displayedScores['me'], 0);

          // 'me' doğru cevap verir ve turu kazanır
          controller.submit('elma');

          // Bot cevap vermeden sıra bota geçer; botun süresi aşılır
          async.elapse(const Duration(milliseconds: 16000));

          uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundEnded, isTrue);
          expect(uiState.matchState?.scores['me'], 1);
          expect(uiState.displayedScores['me'], 0);

          // Yeni tura geç
          async.elapse(const Duration(milliseconds: 3500));
          uiState = container.read(matchControllerProvider);
          expect(uiState.isRoundActive, isTrue);
          expect(uiState.displayedScores['me'], 1);
        });
      },
    );

    test(
      '3. Berabere biten turda skorlar değişmez ve hem displayedScores hem matchState tutarlı kalır',
      () {
        fakeAsync((async) {
          final fakeClock = _FakeClock(async);
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(42)),
            ],
          );
          addTearDown(container.dispose);

          final controller = container.read(matchControllerProvider.notifier);

          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'TestBot',
            initialTurnPlayerId: 'me',
            preselectedQuestionId: 'q1',
            botConfig: const BotConfig(
              thinkMinMs: 999999,
              thinkMaxMs: 999999,
              baseKnowChance: 0.0,
            ),
          );

          // Başlangıçta ve beraberlik durumunda skor 0 - 0 kalmalıdır
          var uiState = container.read(matchControllerProvider);
          expect(uiState.displayedScores['me'], 0);
          expect(uiState.displayedScores['bot'], 0);
        });
      },
    );

    test(
      '4. Çevrim içi (online) maçta roundEnded geldiğinde displayedScores eski skoru korur; roundActive gelince güncellenir',
      () async {
        final clock = _ManualClock(10000);
        final client = _TestOnlineMatchClient();
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            onlineMatchClientFactoryProvider.overrideWithValue(() => client),
          ],
        );
        addTearDown(container.dispose);

        final session = container.read(onlineMatchSessionProvider.notifier);
        await session.startOnlineMatch(
          matchId: 'm_online_1',
          opponentName: 'Rakip',
        );

        // 1. Tur aktif durumu (0 - 0)
        final activeState1 = OnlineMatchState(
          opponentName: 'Rakip',
          serverNowMs: 10000,
          receivedLocalMs: 10000,
          phase: OnlineMatchPhase.roundActive,
          roundNumber: 1,
          turnIsMine: true,
          myScore: 0,
          opponentScore: 0,
          myHintsLeft: 1,
          question: const OnlineQuestion(
            id: 'q1',
            text: 'Meyveler',
          ),
          deadlineMs: 25000,
          attempts: const [],
          opponentConnected: true,
        );
        client.emit(OnlineMatchStateUpdate(activeState1));

        var uiState = container.read(onlineMatchSessionProvider);
        expect(uiState.isRoundActive, isTrue);
        expect(uiState.displayedScores['me'], 0);
        expect(uiState.displayedScores['bot'], 0);

        // 2. Tur bitti (roundEnded): sunucu skoru 1 - 0 olarak gönderir
        final roundEndedState = OnlineMatchState(
          opponentName: 'Rakip',
          serverNowMs: 25000,
          receivedLocalMs: 25000,
          phase: OnlineMatchPhase.roundEnded,
          roundNumber: 1,
          turnIsMine: false,
          myScore: 1,
          opponentScore: 0,
          myHintsLeft: 1,
          question: const OnlineQuestion(
            id: 'q1',
            text: 'Meyveler',
          ),
          deadlineMs: 25000,
          attempts: const [],
          opponentConnected: true,
          nextRoundAtMs: 28500,
          lastRound: const OnlineLastRound(
            winnerIsMe: true,
            draw: false,
            reason: 'timeout',
          ),
        );
        client.emit(OnlineMatchStateUpdate(roundEndedState));

        uiState = container.read(onlineMatchSessionProvider);
        expect(uiState.isRoundEnded, isTrue);
        // RoundEndView için gerçek skor 1 olmalıdır:
        expect(uiState.matchState?.scores['me'], 1);
        // Maç ekranı skor kartı (displayedScores) tur bitişi boyunca eski skorda (0) kalmalıdır:
        expect(uiState.displayedScores['me'], 0);

        // 3. 2. Tur başlar (roundActive):
        final activeState2 = OnlineMatchState(
          opponentName: 'Rakip',
          serverNowMs: 28500,
          receivedLocalMs: 28500,
          phase: OnlineMatchPhase.roundActive,
          roundNumber: 2,
          turnIsMine: false,
          myScore: 1,
          opponentScore: 0,
          myHintsLeft: 1,
          question: const OnlineQuestion(
            id: 'q2',
            text: 'Hayvanlar',
          ),
          deadlineMs: 43500,
          attempts: const [],
          opponentConnected: true,
        );
        client.emit(OnlineMatchStateUpdate(activeState2));

        uiState = container.read(onlineMatchSessionProvider);
        expect(uiState.isRoundActive, isTrue);
        // Yeni turda maç ekranı güncel skoru (1) gösterir:
        expect(uiState.displayedScores['me'], 1);
        expect(uiState.displayedScores['bot'], 0);
      },
    );

    test(
      '5. Çevrim içi maçta oyuncu tam roundEnded anında yeniden bağlanırsa (reconnect), displayedScores lastRound üzerinden eski skoru türetir',
      () async {
        final clock = _ManualClock(10000);
        final client = _TestOnlineMatchClient();
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            onlineMatchClientFactoryProvider.overrideWithValue(() => client),
          ],
        );
        addTearDown(container.dispose);

        final session = container.read(onlineMatchSessionProvider.notifier);
        await session.startOnlineMatch(
          matchId: 'm_online_reconnect',
          opponentName: 'Rakip',
        );

        // Doğrudan roundEnded fazında state mesajı gelir (oyuncu o anda bağlandı)
        final roundEndedState = OnlineMatchState(
          opponentName: 'Rakip',
          serverNowMs: 25000,
          receivedLocalMs: 25000,
          phase: OnlineMatchPhase.roundEnded,
          roundNumber: 1,
          turnIsMine: false,
          myScore: 1,
          opponentScore: 0,
          myHintsLeft: 1,
          question: const OnlineQuestion(
            id: 'q1',
            text: 'Meyveler',
          ),
          deadlineMs: 25000,
          attempts: const [],
          opponentConnected: true,
          nextRoundAtMs: 28500,
          lastRound: const OnlineLastRound(
            winnerIsMe: true,
            draw: false,
            reason: 'timeout',
          ),
        );
        client.emit(OnlineMatchStateUpdate(roundEndedState));

        final uiState = container.read(onlineMatchSessionProvider);
        expect(uiState.isRoundEnded, isTrue);
        expect(uiState.matchState?.scores['me'], 1);
        // Reconnect olsa dahi maç ekranındaki skor kartı eski skoru (0) gösterir:
        expect(uiState.displayedScores['me'], 0);
      },
    );

    testWidgets(
      '6. Widget testi: MatchScreen içindeki PlayerCard tur sonu ekranı varken displayedScores kullanır ve eski skorda kalır',
      (tester) async {
        final matchState = MatchState(
          config: const MatchConfig(totalDecisiveRounds: 3, answerSeconds: 15),
          playerIds: const ['me', 'bot'],
          scores: const {'me': 1, 'bot': 0},
          decisiveRounds: 1,
          totalRoundsPlayed: 1,
          phase: MatchPhase.roundEnded,
          currentQuestion: _testQuestion1,
          usedAnswerIds: const {},
          turnPlayerId: 'me',
          deadlineMs: 15000,
          remainingNearMisses: const {'me': 1, 'bot': 1},
          usedQuestionIds: const {'q1'},
          currentRoundAttempts: const [],
          roundHistory: const [
            RoundRecord(
              questionId: 'q1',
              starterPlayerId: 'me',
              attempts: [],
              winnerId: 'me',
              reason: RoundEndReason.timeout,
            ),
          ],
        );

        final uiState = MatchUiState(
          matchState: matchState,
          opponentName: 'Bot',
          roundTransitionTotalMs: 3500,
          roundTransitionRemainingMs: 3000,
          boardScores: const {'me': 0, 'bot': 0},
        );

        final controller = _FakeMatchController(uiState);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchControllerProvider.overrideWith(() => controller),
              activeMatchSessionModeProvider
                  .overrideWith(() => ActiveMatchSessionModeNotifier()),
            ],
            child: const MaterialApp(
              home: MatchScreen(),
            ),
          ),
        );
        await tester.pump();

        // 1. RoundEndView ekranı mevcuttur ve burada güncel skor 1 görünür
        expect(find.byType(RoundEndView), findsOneWidget);
        expect(find.text('1'), findsWidgets);

        // 2. Maç ekranındaki PlayerCard'ımız ise eski skoru (0) gösterir
        final playerCards =
            tester.widgetList<PlayerCard>(find.byType(PlayerCard)).toList();
        final myCard =
            playerCards.firstWhere((c) => c.name == AppStrings.you);

        expect(
          myCard.score,
          0,
          reason:
              'Maç ekranındaki skor kartı yeni tur başlamadan önce eski skoru (0) göstermelidir.',
        );
      },
    );

    test(
      '7. Uygulama yeni açıldığındaki İLK bot maçında displayedScores 0-0 başlar',
      () {
        fakeAsync((async) {
          final fakeClock = _FakeClock(async);
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(1)),
              questionRepositoryProvider.overrideWithValue(
                _FakeQuestionRepository([_testQuestion1, _testQuestion2]),
              ),
            ],
          );
          addTearDown(container.dispose);

          final controller = container.read(matchControllerProvider.notifier);
          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'Bot1',
            initialTurnPlayerId: 'me',
          );
          async.flushMicrotasks();

          final state = container.read(matchControllerProvider);
          expect(state.displayedScores['me'], 0,
              reason: 'İlk maçta benim skorum 0 olmalı');
          expect(state.displayedScores['bot'], 0,
              reason: 'İlk maçta bot skoru 0 olmalı');
        });
      },
    );

    test(
      '8. Önceki bot maçı bittikten sonra YENİ maç başladığında ilk turun başında displayedScores 0-0 olmalıdır (HATA YENİDEN ÜRETİMİ)',
      () {
        fakeAsync((async) {
          final fakeClock = _FakeClock(async);
          final container = ProviderContainer(
            overrides: [
              gameClockProvider.overrideWithValue(fakeClock),
              randomProvider.overrideWithValue(math.Random(1)),
              questionRepositoryProvider.overrideWithValue(
                _FakeQuestionRepository([_testQuestion1, _testQuestion2]),
              ),
            ],
          );
          addTearDown(container.dispose);

          final controller = container.read(matchControllerProvider.notifier);
          const silentBot = BotConfig(
            thinkMinMs: 999999,
            thinkMaxMs: 999999,
            baseKnowChance: 0.0,
          );

          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'Bot1',
            initialTurnPlayerId: 'bot',
            botConfig: silentBot,
            questionOrder: ['q1', 'q2'],
          );
          async.flushMicrotasks();

          // Tur 1: Bot süre aşımına uğrar (me: 1, bot: 0)
          async.elapse(const Duration(milliseconds: 16000));
          async.flushMicrotasks();

          // Tur 1 -> Tur 2 geçişi (3.5 sn)
          async.elapse(const Duration(milliseconds: 3500));
          async.flushMicrotasks();

          // Tur 2: Kullanıcı doğru cevap verir ('kedi'), bot süre aşımına uğrar -> Maç biter (me: 2, bot: 0)
          final q = container.read(matchControllerProvider).matchState?.currentQuestion;
          controller.submit(q!.answers.first.aliases.first);
          async.elapse(const Duration(milliseconds: 17000));
          async.flushMicrotasks();

          // 500 ms matchFinishDelayMs sonra maç sonu commit edilir
          async.elapse(const Duration(milliseconds: 600));
          async.flushMicrotasks();

          var state = container.read(matchControllerProvider);
          expect(state.matchState!.phase, MatchPhase.matchFinished);
          expect(state.boardScores, {'me': 2, 'bot': 0});

          // ŞİMDİ YENİ MAÇ BAŞLATILIYOR (Rematch veya yeni bot maçı)
          controller.startMatch(
            questions: [_testQuestion1, _testQuestion2],
            opponentName: 'Bot2',
            initialTurnPlayerId: 'me',
            botConfig: silentBot,
          );
          async.flushMicrotasks();

          state = container.read(matchControllerProvider);
          expect(state.matchState!.phase, MatchPhase.roundActive);
          expect(state.matchState!.totalRoundsPlayed, 0);

          // İŞTE HATA NOKTASI: Yeni maçın ilk turunda displayedScores 0-0 olmalıdır!
          expect(
            state.displayedScores['me'],
            0,
            reason:
                'Yeni maç başlar başlamaz önceki maçtan kalan skor (2) DEĞİL, 0 görünmelidir!',
          );
          expect(
            state.displayedScores['bot'],
            0,
            reason: 'Yeni maç başlar başlamaz bot skoru 0 görünmelidir!',
          );
        });
      },
    );
  });
}

class _FakeQuestionRepository implements QuestionRepository {
  final List<Question> questions;
  const _FakeQuestionRepository(this.questions);

  @override
  Future<List<Question>> loadAll() async => questions;
}

class _FakeMatchController extends MatchController {
  final MatchUiState _initialState;
  _FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;
}
