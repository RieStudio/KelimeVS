import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/coin_icon.dart';
import 'package:app/core/widgets/match_card.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';

class FakeSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode mode;
  FakeSessionModeNotifier(this.mode);

  @override
  MatchSessionMode build() => mode;
}

void main() {
  group('Friend Duel UI & History Badges', () {
    testWidgets('1. MatchCard isFriendly: true olduğunda "Dostluk" rozeti göstermez, normal maç görünümü sunar',
        (tester) async {
      const entry = MatchHistoryEntry(
        id: 'friend_1',
        matchId: 'friend_1',
        opponentName: 'Zeynep',
        finishedAtMs: 123456789,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        isFriendly: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchCard(entry: entry),
          ),
        ),
      );

      expect(find.text('Zeynep'), findsOneWidget);
      expect(find.text('Dostluk'), findsNothing);
      expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
      expect(find.text(AppStrings.won), findsOneWidget);
    });

    testWidgets(
        '2. MatchEndView isFriendly: true olduğunda "Dostluk Düellosu" / "Jeton verilmez" rozeti gösterilmez; skor, rakip kartı, Tekrar Oyna ve Maç Detayı gösterilir',
        (tester) async {
      final finishedMatchState = MatchState(
        config: const MatchConfig(),
        playerIds: const ['me', 'bot'],
        scores: const {'me': 2, 'bot': 1},
        decisiveRounds: 2,
        totalRoundsPlayed: 3,
        phase: MatchPhase.matchFinished,
        currentQuestion: const Question(
          id: 'q_test_1',
          categoryId: 'c1',
          text: 'Test soru',
          answers: [],
        ),
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
        isFriendly: true,
        opponentName: 'Mehmet',
        coinsAwarded: 0,
        lastSavedMatch: const MatchHistoryEntry(
          id: 'friend_match_1',
          matchId: 'friend_match_1',
          opponentName: 'Mehmet',
          finishedAtMs: 12345678,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
          isFriendly: true,
          botlaOynandi: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
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

      // Dostluk Düellosu / Jeton verilmez rozeti görünmemeli
      expect(find.textContaining('Dostluk Düellosu'), findsNothing);
      expect(find.textContaining('Jeton verilmez'), findsNothing);

      // Jeton ödülü kartı görünmemeli
      expect(find.text('+0 Jeton'), findsNothing);
      expect(find.text('+30 Jeton'), findsNothing);
      expect(find.byType(CoinIcon), findsNothing);

      // Skor görünmeli ("Sen", "2 – 1", "Mehmet")
      expect(find.text(AppStrings.you), findsOneWidget);
      expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
      expect(find.text('Mehmet'), findsWidgets);

      // Rakip kartı (Engelle butonu görünmeli, Bildir butonu görünmemeli)
      expect(find.text(AppStrings.blockAction), findsOneWidget);
      expect(find.text('Bildir'), findsNothing);

      // Butonlar görünmeli
      expect(find.text(AppStrings.playAgain), findsOneWidget);
      expect(find.text(AppStrings.matchDetail), findsOneWidget);
    });
  });
}
