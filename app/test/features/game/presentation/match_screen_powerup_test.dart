import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class MockPowerupSession implements MatchSession {
  bool extraTimeCalled = false;

  @override
  MatchUiState get state => const MatchUiState();

  @override
  void submit(String text) {}

  @override
  void useExtraTime() {
    extraTimeCalled = true;
  }

  @override
  void leaveMatch() {}

  @override
  void dispose() {}
}

class FakeModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode initialMode;
  FakeModeNotifier(this.initialMode);

  @override
  MatchSessionMode build() => initialMode;
}

class TestUiStateNotifier extends Notifier<MatchUiState> {
  final MatchUiState initial;
  TestUiStateNotifier(this.initial);

  @override
  MatchUiState build() => initial;

  void updateState(MatchUiState next) {
    state = next;
  }
}

class FakeProfileNotifier extends ProfileNotifier {
  final int initialCoins;
  FakeProfileNotifier({this.initialCoins = 100});

  @override
  ProfileState build() {
    return ProfileState(
      nickname: 'TestPlayer',
      coins: initialCoins,
    );
  }
}

void main() {
  const testQuestion = Question(
    id: 'q1',
    categoryId: 'c1',
    text: 'Türkiye\'nin başkenti?',
    answers: [],
  );

  final testMatchState = MatchState(
    config: const MatchConfig(answerSeconds: 15),
    playerIds: const ['me', 'bot'],
    scores: const {'me': 0, 'bot': 0},
    decisiveRounds: 0,
    totalRoundsPlayed: 0,
    phase: MatchPhase.roundActive,
    currentQuestion: testQuestion,
    usedAnswerIds: const {},
    turnPlayerId: 'me',
    deadlineMs: 15000,
    remainingNearMisses: const {'me': 1, 'bot': 0},
    usedQuestionIds: const {},
    currentRoundAttempts: const [],
    roundHistory: const [],
  );

  Widget createWidget({
    required MatchSessionMode mode,
    required MatchUiState uiState,
    required MockPowerupSession session,
    int coins = 100,
  }) {
    final stateNotifier = TestUiStateNotifier(uiState);
    return ProviderScope(
      overrides: [
        activeMatchSessionModeProvider
            .overrideWith(() => FakeModeNotifier(mode)),
        activeMatchUiStateProvider
            .overrideWith((ref) => ref.watch(
                  NotifierProvider<TestUiStateNotifier, MatchUiState>(
                    () => stateNotifier,
                  ),
                )),
        activeMatchSessionProvider.overrideWithValue(session),
        profileProvider.overrideWith(() => FakeProfileNotifier(initialCoins: coins)),
      ],
      child: const MaterialApp(
        home: MatchScreen(),
      ),
    );
  }

  testWidgets('1. Bot maçında ek süre güçlendirici butonu gösterilmez', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.bot,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Bot Ahmet',
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
    ));
    await tester.pump();

    expect(find.text('+5 sn'), findsNothing);
    expect(find.text(AppStrings.extraTimeUsed), findsNothing);
  });

  testWidgets('2. Arkadaş maçında (friendly) ek süre güçlendirici butonu gösterilmez', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Arkadaş Ali',
        isFriendly: true,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
    ));
    await tester.pump();

    expect(find.text('+5 sn'), findsNothing);
    expect(find.text(AppStrings.extraTimeUsed), findsNothing);
  });

  testWidgets('3. Çevrimiçi ranked maçta güçlendirici butonu "+5 sn · 30" olarak görünür ve tıklanınca useExtraTime çağrılır', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
      coins: 100,
    ));
    await tester.pump();

    expect(find.text('+5 sn'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await tester.tap(find.text('+5 sn'));
    await tester.pump();

    expect(session.extraTimeCalled, isTrue);
  });

  testWidgets('4. Jeton yetersizken (bakiye < cost) buton soluk görünür ve tıklanınca yetersiz bakiye uyarısı verir', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
      coins: 10, // < 30
    ));
    await tester.pump();

    expect(find.text('+5 sn'), findsOneWidget);

    await tester.tap(find.text('+5 sn'));
    await tester.pump();

    expect(session.extraTimeCalled, isFalse);
    expect(find.text(AppStrings.notEnoughCoinsForExtraTime(30)), findsOneWidget);
  });

  testWidgets('5. Güçlendirici maçta kullanıldıktan sonra (remainingUses = 0) "Kullanıldı" rozetine dönüşür', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 0, // kullanıldı
      ),
      session: session,
      coins: 100,
    ));
    await tester.pump();

    expect(find.text(AppStrings.extraTimeUsed), findsOneWidget);
    expect(find.text('+5 sn'), findsNothing);

    await tester.tap(find.text(AppStrings.extraTimeUsed));
    await tester.pump();

    expect(session.extraTimeCalled, isFalse);
  });

  testWidgets('6. Rakip ek süre kullandığında üst çubuk altında bildirim şeridi görünür', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        opponentExtraTimeBanner: AppStrings.opponentUsedExtraTime,
      ),
      session: session,
    ));
    await tester.pump();

    expect(find.text(AppStrings.opponentUsedExtraTime), findsOneWidget);
  });

  testWidgets('7. temporary_error bildirimi geldiğinde ekranda SnackBar gösterilir ve buton sessiz kalmaz', (tester) async {
    final session = MockPowerupSession();
    final stateNotifier = TestUiStateNotifier(
      MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
    );

    final testUiStateProvider =
        NotifierProvider<TestUiStateNotifier, MatchUiState>(
      () => stateNotifier,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider
              .overrideWith((ref) => ref.watch(testUiStateProvider)),
          activeMatchSessionProvider.overrideWithValue(session),
          profileProvider.overrideWith(() => FakeProfileNotifier(initialCoins: 100)),
        ],
        child: const MaterialApp(
          home: MatchScreen(),
        ),
      ),
    );
    await tester.pump();

    // temporary_error geldiğinde
    stateNotifier.updateState(
      stateNotifier.state.copyWith(
        isUsingPowerup: false,
        powerupErrorNotice: AppStrings.powerupTemporaryError,
        powerupErrorCounter: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(AppStrings.powerupTemporaryError), findsOneWidget);
  });
}
