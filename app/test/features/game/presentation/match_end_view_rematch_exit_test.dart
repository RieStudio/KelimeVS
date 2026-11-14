import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/app_icon_button.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/online/application/online_match_session.dart';

class _TestSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode _initial;
  _TestSessionModeNotifier(this._initial);
  @override
  MatchSessionMode build() => _initial;
}

class _MockOnlineMatchSession extends OnlineMatchSession {
  int leaveRematchCalls = 0;

  @override
  void leaveRematch() {
    leaveRematchCalls++;
  }
}

void main() {
  const testQuestion = Question(
    id: 'q_test_1',
    categoryId: 'c1',
    text: 'Test soru',
    answers: [],
  );

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

  final testUiState = MatchUiState(
    matchState: finishedMatchState,
    myPlayerId: 'me',
    opponentName: 'Rakip',
  );

  group('MatchEndView Rematch Exit Hooks Tests', () {
    testWidgets('1. Online maçta Kapat (X) butonuna basılınca leaveRematch çağrılır', (tester) async {
      final mockOnlineSession = _MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.online),
            ),
            activeMatchUiStateProvider.overrideWithValue(testUiState),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockOnlineSession.leaveRematchCalls, 0);

      // Kapat butonuna bas
      final closeButton = find.byWidgetPredicate(
        (widget) => widget is AppIconButton && widget.icon == AppIcons.close,
      );
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pump();

      expect(mockOnlineSession.leaveRematchCalls, 1);
    });

    testWidgets('2. Online maçta Tekrar Oyna butonuna basılınca leaveRematch çağrılır', (tester) async {
      final mockOnlineSession = _MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.online),
            ),
            activeMatchUiStateProvider.overrideWithValue(testUiState),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockOnlineSession.leaveRematchCalls, 0);

      // Tekrar Oyna butonuna bas
      final playAgainBtn = find.widgetWithText(PrimaryButton, AppStrings.playAgain);
      expect(playAgainBtn, findsOneWidget);
      await tester.tap(playAgainBtn);
      await tester.pump();

      expect(mockOnlineSession.leaveRematchCalls, 1);
    });

    testWidgets('3. Online maçta sayfa dispose / unmount olduğunda leaveRematch çağrılır ve hata fırlatmaz', (tester) async {
      final mockOnlineSession = _MockOnlineMatchSession();
      bool showView = true;
      late StateSetter setStateCallback;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.online),
            ),
            activeMatchUiStateProvider.overrideWithValue(testUiState),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setStateCallback = setState;
                  return showView ? const MatchEndView() : const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockOnlineSession.leaveRematchCalls, 0);

      // Widget ağacından kaldır (dispose)
      setStateCallback(() {
        showView = false;
      });
      await tester.pumpAndSettle();

      // Dispose sırasında leaveRematch çağrılmış olmalı
      expect(mockOnlineSession.leaveRematchCalls, 1);
    });

    testWidgets('4. Bot maçında Kapat veya Tekrar Oyna basılınca leaveRematch ÇAĞRILMAZ', (tester) async {
      final mockOnlineSession = _MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider.overrideWith(
              () => _TestSessionModeNotifier(MatchSessionMode.bot),
            ),
            activeMatchUiStateProvider.overrideWithValue(testUiState),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeButton = find.byWidgetPredicate(
        (widget) => widget is AppIconButton && widget.icon == AppIcons.close,
      );
      await tester.tap(closeButton);
      await tester.pump();

      expect(mockOnlineSession.leaveRematchCalls, 0);
    });
  });
}
