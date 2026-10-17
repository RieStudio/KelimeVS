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
import 'package:app/features/game/presentation/match_end_view.dart';

class _TestSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode _initial;
  _TestSessionModeNotifier(this._initial);
  @override
  MatchSessionMode build() => _initial;
}

void main() {
  const testQuestion = Question(
    id: 'q_test_1',
    categoryId: 'c1',
    text: 'Test soru',
    answers: [],
  );

  group('MatchEndView Coin Reward Display Tests', () {
    testWidgets('1. Bot maçında jeton ödülü kartı HİÇ gösterilmez', (tester) async {
      final finishedMatchState = MatchState(
        config: const MatchConfig(),
        playerIds: const ['me', 'bot'],
        scores: const {'me': 2, 'bot': 0},
        decisiveRounds: 2,
        totalRoundsPlayed: 2,
        phase: MatchPhase.matchFinished,
        currentQuestion: testQuestion,
        usedAnswerIds: const {},
        turnPlayerId: null,
        deadlineMs: 0,
        remainingNearMisses: const {'me': 0, 'bot': 0},
        usedQuestionIds: const {},
        currentRoundAttempts: const [],
        roundHistory: const [],
        winnerId: 'me',
      );

      final uiState = MatchUiState(
        matchState: finishedMatchState,
        myPlayerId: 'me',
        coinsAwarded: null, // Bot maçında ödül yok
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.bot),
            ),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // "Kazandın!" başlığı görünür
      expect(find.text('Kazandın!'), findsOneWidget);

      // Jeton ödülü kartı ("Jeton ödülü" semantics veya "+30 jeton") HİÇ görünmemelidir
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label?.startsWith('Jeton ödülü') == true,
        ),
        findsNothing,
      );
      expect(find.text('+30${AppStrings.coinSuffix}'), findsNothing);
    });

    testWidgets('2. Online maçta sunucudan coinsAwarded (örn. 30) gelince "+30G" kartı gösterilir', (tester) async {
      final finishedMatchState = MatchState(
        config: const MatchConfig(),
        playerIds: const ['me', 'bot'],
        scores: const {'me': 2, 'bot': 1},
        decisiveRounds: 3,
        totalRoundsPlayed: 3,
        phase: MatchPhase.matchFinished,
        currentQuestion: testQuestion,
        usedAnswerIds: const {},
        turnPlayerId: null,
        deadlineMs: 0,
        remainingNearMisses: const {'me': 0, 'bot': 0},
        usedQuestionIds: const {},
        currentRoundAttempts: const [],
        roundHistory: const [],
        winnerId: 'me',
      );

      final uiState = MatchUiState(
        matchState: finishedMatchState,
        myPlayerId: 'me',
        coinsAwarded: 30, // Online maç ödülü
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.online),
            ),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Jeton ödülü kartı ve metni görünür
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Jeton ödülü: 30',
        ),
        findsOneWidget,
      );
      expect(find.text('+30${AppStrings.coinSuffix}'), findsOneWidget);
    });

    testWidgets('3. Online maçta coinsAwarded null ise (ödül alınamadı) kart gizlenir', (tester) async {
      final finishedMatchState = MatchState(
        config: const MatchConfig(),
        playerIds: const ['me', 'bot'],
        scores: const {'me': 2, 'bot': 1},
        decisiveRounds: 3,
        totalRoundsPlayed: 3,
        phase: MatchPhase.matchFinished,
        currentQuestion: testQuestion,
        usedAnswerIds: const {},
        turnPlayerId: null,
        deadlineMs: 0,
        remainingNearMisses: const {'me': 0, 'bot': 0},
        usedQuestionIds: const {},
        currentRoundAttempts: const [],
        roundHistory: const [],
        winnerId: 'me',
      );

      final uiState = MatchUiState(
        matchState: finishedMatchState,
        myPlayerId: 'me',
        coinsAwarded: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.online),
            ),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Jeton kartı görünmez
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label?.startsWith('Jeton ödülü') == true,
        ),
        findsNothing,
      );
      expect(find.text('+30${AppStrings.coinSuffix}'), findsNothing);
    });
  });
}
