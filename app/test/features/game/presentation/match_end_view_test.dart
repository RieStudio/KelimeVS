import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/config/app_config.dart';
import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/result_circle.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';

class FakeMatchController extends MatchController {
  final MatchUiState _initialState;
  bool startMatchCalled = false;

  FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
  }) async {
    startMatchCalled = true;
  }
}

Widget _buildTestApp(
  FakeMatchController controller, {
  bool disableAnimations = false,
  NavigatorObserver? navigatorObserver,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(
      navigatorObservers: navigatorObserver != null ? [navigatorObserver] : [],
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(
          body: MatchEndView(),
        ),
      ),
    ),
  );
}

void main() {
  const testQuestion = Question(
    id: 'q_test_1',
    categoryId: 'hayvanlar',
    text: 'B ile başlayan hayvanlar',
    answers: [],
  );

  MatchState createMatchState({
    required Map<String, int> scores,
    required String winnerId,
    String? endedBy = 'normal',
  }) {
    return MatchState(
      config: const MatchConfig(totalDecisiveRounds: 3, answerSeconds: 15),
      playerIds: const ['me', 'bot'],
      scores: scores,
      decisiveRounds: scores.values.fold(0, (a, b) => a + b),
      totalRoundsPlayed: 3,
      phase: MatchPhase.matchFinished,
      currentQuestion: testQuestion,
      endedBy: endedBy,
      usedAnswerIds: const {},
      turnPlayerId: 'me',
      deadlineMs: 15000,
      remainingNearMisses: const {'me': 1, 'bot': 1},
      usedQuestionIds: const {'q_test_1'},
      currentRoundAttempts: const [],
      roundHistory: const [],
      winnerId: winnerId,
    );
  }

  testWidgets('1. Maç kazanıldığında (win): kupa ikonu, "Kazandın!", +30 jeton, skor doğru', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // ResultCircle: win varyantı, trophy ikonu
    final circleFinder = find.byType(ResultCircle);
    expect(circleFinder, findsOneWidget);
    final circle = tester.widget<ResultCircle>(circleFinder);
    expect(circle.variant, ResultCircleVariant.win);
    expect(circle.icon, AppIcons.trophy);

    // Başlık
    expect(find.text(AppStrings.wonExclamation), findsOneWidget);

    // Skor satırı: "Sen", "2 – 1", "Rakip"
    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
    expect(find.text(AppStrings.opponent), findsOneWidget);

    // Jeton ödülü kartı (+30 jeton)
    expect(
      find.text('+${AppConfig.matchWinCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );

    // Terk notu olmamalı
    expect(find.text(AppStrings.opponentLeftMatch), findsNothing);
    expect(find.text(AppStrings.youLeftMatch), findsNothing);
  });

  testWidgets('2. Maç kaybedildiğinde (lose): tekrar ikonu, "Kaybettin", +10 jeton, skor doğru', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 2},
      winnerId: 'bot',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // ResultCircle: lose varyantı, refresh ikonu
    final circleFinder = find.byType(ResultCircle);
    expect(circleFinder, findsOneWidget);
    final circle = tester.widget<ResultCircle>(circleFinder);
    expect(circle.variant, ResultCircleVariant.lose);
    expect(circle.icon, AppIcons.refresh);

    // Başlık (ünlemsiz)
    expect(find.text(AppStrings.lost), findsOneWidget);

    // Skor satırı
    expect(find.text('1${AppStrings.scoreDash}2'), findsOneWidget);

    // Jeton ödülü kartı (+10 jeton)
    expect(
      find.text('+${AppConfig.matchLoseCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('3. Rakip terk ettiğinde (forfeit win): "Rakip maçtan ayrıldı" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      endedBy: 'forfeit',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
    expect(find.text(AppStrings.opponentLeftMatch), findsOneWidget);
    expect(
      find.text('+${AppConfig.matchWinCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('4. Ben terk ettiğimde (forfeit lose): "Maçı terk ettin" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 0, 'bot': 0},
      winnerId: 'bot',
      endedBy: 'forfeit',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lost), findsOneWidget);
    expect(find.text(AppStrings.youLeftMatch), findsOneWidget);
    expect(
      find.text('+${AppConfig.matchLoseCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('5. "Tekrar Oyna" butonuna tıklandığında controller.startMatch() çağrılır', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(controller.startMatchCalled, isFalse);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.playAgain));
    await tester.pump();

    expect(controller.startMatchCalled, isTrue);
  });

  testWidgets('6. "Maç Detayı" butonu henüz ekranda bulunmaz (TODO doğrulaması)', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text('Maç Detayı'), findsNothing);
    expect(find.textContaining('Detay'), findsNothing);
  });

  testWidgets('7. Kapat ikonu tıklandığında Navigator.pop çalışır', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MatchEndView(),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Open MatchEndView
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchEndView), findsOneWidget);

    // Tap Close icon button
    await tester.tap(find.bySemanticsLabel(AppStrings.close));
    await tester.pumpAndSettle();

    expect(find.byType(MatchEndView), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('8. disableAnimations aktifken FadeTransition olmadan doğrudan çizilir', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller, disableAnimations: true));

    expect(
      find.descendant(
        of: find.byType(MatchEndView),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
  });
}
