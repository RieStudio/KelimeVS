import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/widgets/player_card.dart';
import 'package:app/core/widgets/smooth_progress_bar.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';

import '../application/online_match_session_test.dart';

class _FakeBotMatchController extends MatchController {
  final MatchUiState _initialState;
  _FakeBotMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;

  @override
  void submit(String text) {}

  @override
  void leaveMatch() {}

  @override
  void useExtraTime() {}
}

void main() {
  group('Online ve Bot Süre Çubuğu İlerleme Doğrulama Testleri', () {
    testWidgets('1. Online maç başladı (sıra rakipte): Rakip kartında süre çubuğu %100 başlar ve 20 sn gösterir', (tester) async {
      final clock = FakeManualClock(10000);
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeMatchSessionModeProvider.notifier).setMode(MatchSessionMode.online);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_repro', opponentName: 'Rakip');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );
      await tester.pump();

      // Sunucudan gerçekçi "maç başladı" mesajı gelir:
      // Ranked maçta sunucu HER ZAMAN extraTimePowerup gönderir (cost: 30, seconds: 5, remainingUses: 1).
      // serverNowMs = 10000, deadlineMs = 30000 (tam 20 sn), answerSeconds = 20, sıra rakipte (turnIsMine: false)
      client.emit(OnlineMatchStateUpdate(const OnlineMatchState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 0,
        opponentScore: 0,
        question: OnlineQuestion(id: 'q1', text: 'Hayvanlar'),
        turnIsMine: false,
        deadlineMs: 30000,
        myHintsLeft: 1,
        attempts: [],
        opponentName: 'Rakip',
        opponentConnected: true,
        answerSeconds: 20,
        extraTimePowerup: OnlinePowerupConfig(cost: 30, seconds: 5, remainingUses: 1),
      )));

      // İlk kareyi çiz
      await tester.pump();

      final uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.remainingMs, equals(20000));
      expect(uiState.maxAllowedSeconds, equals(20));

      final playerCards = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).toList();
      final opponentCard = playerCards.firstWhere((c) => c.name == 'Rakip');
      expect(opponentCard.isActive, isTrue);
      expect(opponentCard.remainingSeconds, equals(20));
      expect(opponentCard.timeProgress, equals(1.0));
      expect(opponentCard.maxSeconds, equals(20));

      final sizedBoxes = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(SmoothProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      ).toList();
      expect(sizedBoxes.first.widthFactor, greaterThanOrEqualTo(0.99));

      // 200 ms sonra akışın devam ettiğini doğrula
      clock.currentMs = 10200;
      await tester.pump(const Duration(milliseconds: 200));

      final sizedBoxes200 = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(SmoothProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      ).toList();
      expect(sizedBoxes200.first.widthFactor, closeTo(0.99, 0.02));

      session.dispose();
    });

    testWidgets('2. Sıra değişiminde (sıra benden rakibe geçince) süre çubuğu %100 başlar', (tester) async {
      final clock = FakeManualClock(10000);
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeMatchSessionModeProvider.notifier).setMode(MatchSessionMode.online);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_turn_change', opponentName: 'Rakip');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );
      await tester.pump();

      // Sıra önce bende başlar (turnIsMine: true)
      client.emit(OnlineMatchStateUpdate(const OnlineMatchState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 0,
        opponentScore: 0,
        question: OnlineQuestion(id: 'q1', text: 'Meyveler'),
        turnIsMine: true,
        deadlineMs: 30000,
        myHintsLeft: 1,
        attempts: [],
        opponentName: 'Rakip',
        opponentConnected: true,
        answerSeconds: 20,
        extraTimePowerup: OnlinePowerupConfig(cost: 30, seconds: 5, remainingUses: 1),
      )));
      await tester.pump();

      var myCard = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).firstWhere((c) => c.name != 'Rakip');
      expect(myCard.isActive, isTrue);
      expect(myCard.timeProgress, equals(1.0));
      expect(myCard.remainingSeconds, equals(20));

      // Sıra rakibe geçer: yeni deadlineMs verilir
      clock.currentMs = 15000;
      client.emit(OnlineMatchStateUpdate(const OnlineMatchState(
        serverNowMs: 15000,
        receivedLocalMs: 15000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 1,
        opponentScore: 0,
        question: OnlineQuestion(id: 'q1', text: 'Meyveler'),
        turnIsMine: false,
        deadlineMs: 35000, // Rakip için yeni 20 sn
        myHintsLeft: 1,
        attempts: [],
        opponentName: 'Rakip',
        opponentConnected: true,
        answerSeconds: 20,
        extraTimePowerup: OnlinePowerupConfig(cost: 30, seconds: 5, remainingUses: 1),
      )));
      await tester.pump();

      final opponentCard = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).firstWhere((c) => c.name == 'Rakip');
      expect(opponentCard.isActive, isTrue);
      expect(opponentCard.timeProgress, equals(1.0));
      expect(opponentCard.remainingSeconds, equals(20));

      final sizedBoxes = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(SmoothProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      ).toList();
      expect(sizedBoxes.first.widthFactor, greaterThanOrEqualTo(0.99));

      session.dispose();
    });

    testWidgets('3. Yeni tur başladığında (Round 1 -> Round 2) süre çubuğu %100 başlar', (tester) async {
      final clock = FakeManualClock(10000);
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeMatchSessionModeProvider.notifier).setMode(MatchSessionMode.online);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_round_change', opponentName: 'Rakip');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );
      await tester.pump();

      // Round 2 başlar
      clock.currentMs = 40000;
      client.emit(OnlineMatchStateUpdate(const OnlineMatchState(
        serverNowMs: 40000,
        receivedLocalMs: 40000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 2,
        myScore: 1,
        opponentScore: 1,
        question: OnlineQuestion(id: 'q2', text: 'Şehirler'),
        turnIsMine: true,
        deadlineMs: 60000, // 20 sn
        myHintsLeft: 1,
        attempts: [],
        opponentName: 'Rakip',
        opponentConnected: true,
        answerSeconds: 20,
        extraTimePowerup: OnlinePowerupConfig(cost: 30, seconds: 5, remainingUses: 1),
      )));
      await tester.pump();

      final uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.remainingMs, equals(20000));
      expect(uiState.maxAllowedSeconds, equals(20));

      final myCard = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).firstWhere((c) => c.name != 'Rakip');
      expect(myCard.isActive, isTrue);
      expect(myCard.timeProgress, equals(1.0));
      expect(myCard.remainingSeconds, equals(20));

      final sizedBoxes = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(SmoothProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      ).toList();
      expect(sizedBoxes.first.widthFactor, greaterThanOrEqualTo(0.99));

      session.dispose();
    });

    testWidgets('4. Bot maçında süre çubuğu %100 başlar (bot davranışı bozulmaz)', (tester) async {
      final initialUi = MatchUiState(
        matchState: const MatchState(
          config: MatchConfig(answerSeconds: 20),
          playerIds: ['me', 'bot'],
          scores: {'me': 0, 'bot': 0},
          decisiveRounds: 0,
          totalRoundsPlayed: 0,
          phase: MatchPhase.roundActive,
          turnPlayerId: 'me',
          deadlineMs: 30000,
          remainingNearMisses: {'me': 2, 'bot': 2},
          currentQuestion: Question(
            id: 'q1',
            categoryId: 'c1',
            text: 'Hayvanlar',
            answers: [],
          ),
          usedAnswerIds: {},
          usedQuestionIds: {},
          roundHistory: [],
          currentRoundAttempts: [],
        ),
        remainingMs: 20000,
      );

      final fakeController = _FakeBotMatchController(initialUi);
      final container = ProviderContainer(
        overrides: [
          matchControllerProvider.overrideWith(() => fakeController),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeMatchSessionModeProvider.notifier).setMode(MatchSessionMode.bot);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );
      await tester.pump();

      final uiState = container.read(matchControllerProvider);
      expect(uiState.maxAllowedSeconds, equals(20));
      expect(uiState.remainingMs, equals(20000));

      final myCard = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).firstWhere((c) => c.name != 'Bot');
      expect(myCard.isActive, isTrue);
      expect(myCard.timeProgress, equals(1.0));
      expect(myCard.remainingSeconds, equals(20));

      final sizedBoxes = tester.widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(SmoothProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      ).toList();
      expect(sizedBoxes.first.widthFactor, greaterThanOrEqualTo(0.99));
    });

    test('5. Ek süre kullanıldığında tavan süre ve sayaç doğru davranır', () {
      final uiState = MatchUiState(
        matchState: const MatchState(
          config: MatchConfig(answerSeconds: 20),
          playerIds: ['me', 'bot'],
          scores: {'me': 0, 'bot': 0},
          decisiveRounds: 0,
          totalRoundsPlayed: 0,
          phase: MatchPhase.roundActive,
          turnPlayerId: 'me',
          deadlineMs: 34000,
          remainingNearMisses: {'me': 2, 'bot': 2},
          currentQuestion: Question(
            id: 'q1',
            categoryId: 'c1',
            text: 'Hayvanlar',
            answers: [],
          ),
          usedAnswerIds: {},
          usedQuestionIds: {},
          roundHistory: [],
          currentRoundAttempts: [],
        ),
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 0, // kullanıldı
        remainingMs: 24000, // tur başında ek süre basılmış (19 + 5 = 24 sn)
      );

      expect(uiState.maxAllowedSeconds, equals(24));
      // Sayaç 20'de kesilmeden tam 24 sn'yi gösterir
      expect((uiState.remainingMs / 1000).ceil().clamp(0, uiState.maxAllowedSeconds), equals(24));
    });
  });
}
