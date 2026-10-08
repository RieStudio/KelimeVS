import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/result_circle.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/round_end_view.dart';

class FakeMatchController extends MatchController {
  final MatchUiState _initialState;

  FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;
}

Widget _buildTestApp(
  FakeMatchController controller, {
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(
          body: RoundEndView(),
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
    answers: [
      Answer(id: 'boga', display: 'Boğa', aliases: ['boga']),
    ],
  );

  MatchState createMatchState({
    required int decisiveRounds,
    required Map<String, int> scores,
    required String? winnerId,
    required RoundEndReason reason,
  }) {
    return MatchState(
      config: const MatchConfig(totalDecisiveRounds: 3, answerSeconds: 15),
      playerIds: const ['me', 'bot'],
      scores: scores,
      decisiveRounds: decisiveRounds,
      totalRoundsPlayed: decisiveRounds,
      phase: MatchPhase.roundEnded,
      currentQuestion: testQuestion,
      usedAnswerIds: const {},
      turnPlayerId: 'me',
      deadlineMs: 15000,
      remainingNearMisses: const {'me': 1, 'bot': 1},
      usedQuestionIds: const {'q_test_1'},
      currentRoundAttempts: const [],
      roundHistory: [
        RoundRecord(
          questionId: 'q_test_1',
          starterPlayerId: 'me',
          attempts: const [],
          winnerId: winnerId,
          reason: reason,
        ),
      ],
    );
  }

  testWidgets('1. Tur kazanıldığında (win): yeşil daire, tik ikonu, "Turu kazandın!", neden ve skor doğru', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 1,
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      reason: RoundEndReason.timeout,
    );

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 2500,
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // Üst hap: Tur 1 / 3
    expect(find.text('${AppStrings.roundPrefix}1 / 3'), findsOneWidget);

    // ResultCircle: win varyantı, check ikonu
    final circleFinder = find.byType(ResultCircle);
    expect(circleFinder, findsOneWidget);
    final circle = tester.widget<ResultCircle>(circleFinder);
    expect(circle.variant, ResultCircleVariant.win);
    expect(circle.icon, AppIcons.check);

    // Başlık ve neden
    expect(find.text(AppStrings.roundWonTitle), findsOneWidget);
    expect(find.text(AppStrings.reasonOpponentTimeout), findsOneWidget);

    // Skor kartı
    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text(AppStrings.opponent), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);

    // Alt metin: Tur 2 birazdan başlıyor
    expect(find.text('${AppStrings.roundPrefix}2${AppStrings.nextRoundStartingSoonSuffix}'), findsOneWidget);
  });

  testWidgets('2. Tur kaybedildiğinde (lose): kırmızımsı daire, çarpı ikonu, "Turu kaybettin", neden ve skor doğru', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 2,
      scores: {'me': 1, 'bot': 1},
      winnerId: 'bot',
      reason: RoundEndReason.timeout,
    );

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 2000,
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // Üst hap: Tur 2 / 3
    expect(find.text('${AppStrings.roundPrefix}2 / 3'), findsOneWidget);

    // ResultCircle: lose varyantı, close ikonu
    final circleFinder = find.byType(ResultCircle);
    expect(circleFinder, findsOneWidget);
    final circle = tester.widget<ResultCircle>(circleFinder);
    expect(circle.variant, ResultCircleVariant.lose);
    expect(circle.icon, AppIcons.close);

    // Başlık ve neden (ünlemsiz)
    expect(find.text(AppStrings.roundLostTitle), findsOneWidget);
    expect(find.text(AppStrings.reasonMyTimeout), findsOneWidget);

    // Alt metin: Tur 3 birazdan başlıyor
    expect(find.text('${AppStrings.roundPrefix}3${AppStrings.nextRoundStartingSoonSuffix}'), findsOneWidget);
  });

  testWidgets('3. Tur berabere bittiğinde (draw): mint daire, eşit ikonu, "Tur berabere", neden ve alt metin doğru', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 1,
      scores: {'me': 1, 'bot': 0},
      winnerId: null,
      reason: RoundEndReason.exhausted,
    );

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 1800,
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // Üst hap: decisiveRounds + 1 = Tur 2 / 3
    expect(find.text('${AppStrings.roundPrefix}2 / 3'), findsOneWidget);

    // ResultCircle: draw varyantı, equal ikonu
    final circleFinder = find.byType(ResultCircle);
    expect(circleFinder, findsOneWidget);
    final circle = tester.widget<ResultCircle>(circleFinder);
    expect(circle.variant, ResultCircleVariant.draw);
    expect(circle.icon, AppIcons.equal);

    // Başlık ve neden
    expect(find.text(AppStrings.roundDrawTitle), findsOneWidget);
    expect(find.text(AppStrings.reasonExhausted), findsOneWidget);

    // Alt metin: "Yeni tur birazdan başlıyor"
    expect(find.text(AppStrings.newRoundStartingSoon), findsOneWidget);
  });

  testWidgets('4. Final reveal (isFinalReveal = true) durumunda "Maç sonucu birazdan" yazar', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 3,
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
      reason: RoundEndReason.timeout,
    ).copyWith(phase: MatchPhase.matchFinished);

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      isFinalReveal: true,
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 1500,
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // Üst hap: Tur 3 / 3
    expect(find.text('${AppStrings.roundPrefix}3 / 3'), findsOneWidget);

    // Alt metin: Maç sonucu birazdan
    expect(find.text(AppStrings.matchResultStartingSoon), findsOneWidget);
  });

  testWidgets('5. Geri sayım çubuğu ilerleme oranı controller kalan süresine göre ayarlanır', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 1,
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      reason: RoundEndReason.timeout,
    );

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 1500, // %50
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // FractionallySizedBox widthFactor 0.5 olmalı
    final fractionallySizedBox = tester.widget<FractionallySizedBox>(
      find.byWidgetPredicate(
        (w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft,
      ),
    );
    expect(fractionallySizedBox.widthFactor, closeTo(0.5, 0.01));
  });

  testWidgets('6. disableAnimations aktifken FadeTransition olmadan doğrudan çizilir', (tester) async {
    final matchState = createMatchState(
      decisiveRounds: 1,
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      reason: RoundEndReason.timeout,
    );

    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      roundTransitionTotalMs: 3000,
      roundTransitionRemainingMs: 2500,
    );

    final controller = FakeMatchController(uiState);
    await tester.pumpWidget(_buildTestApp(controller, disableAnimations: true));

    // pump() tek seferde doğrudan çizilir, RoundEndView içinde FadeTransition olmaz
    expect(
      find.descendant(
        of: find.byType(RoundEndView),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.text(AppStrings.roundWonTitle), findsOneWidget);
  });
}
