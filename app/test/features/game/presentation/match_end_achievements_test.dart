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

  MatchState makeFinishedMatch({
    int myScore = 2,
    int botScore = 1,
    String winnerId = 'me',
  }) {
    return MatchState(
      config: const MatchConfig(),
      playerIds: const ['me', 'bot'],
      scores: {'me': myScore, 'bot': botScore},
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
      winnerId: winnerId,
    );
  }

  group('MatchEndView Achievements Display Tests', () {
    testWidgets('1. Açılan başarımlar (örn. first_win) bildirim kartı olarak doğru başlık ve açıklamayla gösterilir', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        coinsAwarded: 30,
        unlockedAchievements: const ['first_win'],
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

      // Başarım kartı semantics ve metinleri
      expect(find.text('BAŞARIM AÇILDI'), findsOneWidget);
      expect(find.text('İlk Zafer'), findsOneWidget);
      expect(find.text('İlk galibiyetini al'), findsOneWidget);

      // Jeton kartı da görünür
      expect(find.text('+30${AppStrings.coinSuffix}'), findsOneWidget);
    });

    testWidgets('2. 3 ten fazla başarım açıldığında en fazla 3 tanesi gösterilir', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        coinsAwarded: 50,
        unlockedAchievements: const [
          'first_match',
          'first_win',
          'streak_3',
          'wins_10',
          'matches_10',
        ],
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

      // En fazla 3 adet "BAŞARIM AÇILDI" rozeti olmalıdır
      expect(find.text('BAŞARIM AÇILDI'), findsNWidgets(3));
      expect(find.text('İlk Adım'), findsOneWidget);
      expect(find.text('İlk Zafer'), findsOneWidget);
      expect(find.text('Üçlü Seri'), findsOneWidget);
      // 4. ve 5. başarım gösterilmez
      expect(find.text('Yükselen Yıldız'), findsNothing);
      expect(find.text('Alışma Süreci'), findsNothing);
    });

    testWidgets('3. Bilinmeyen bir başarım kimliği geldiğinde sessizce atlanır, uygulama çökmez', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        unlockedAchievements: const ['unknown_future_achievement'],
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

      // Hiçbir başarım kartı gösterilmez
      expect(find.text('BAŞARIM AÇILDI'), findsNothing);
    });

    testWidgets('4. Dostluk maçında jeton kartı gizlenir ancak başarım açılmışsa başarım kartı gösterilir', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        isFriendly: true,
        coinsAwarded: 30, // Dostluk maçında coinsAwarded set edilse bile kart gizlenmeli
        unlockedAchievements: const ['streak_5'],
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

      // Jeton ödülü kartı HİÇ görünmez
      expect(find.text('+30${AppStrings.coinSuffix}'), findsNothing);

      // Başarım kartı görünür
      expect(find.text('BAŞARIM AÇILDI'), findsOneWidget);
      expect(find.text('Beşli Seri'), findsOneWidget);
    });

    testWidgets('5. Maç sonu ekranında yasaklı kelimeler (bot, yapay zeka, alıştırma maçı) geçmez', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        unlockedAchievements: const ['first_match', 'first_win', 'streak_3'],
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

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final text in textWidgets) {
        final content = text.data?.toLowerCase() ?? '';
        expect(content.contains('bot'), isFalse, reason: 'Yasaklı "bot" ifadesi bulundu: $content');
        expect(content.contains('yapay zeka'), isFalse, reason: 'Yasaklı "yapay zeka" ifadesi bulundu: $content');
        expect(content.contains('alıştırma maçı'), isFalse, reason: 'Yasaklı "alıştırma maçı" ifadesi bulundu: $content');
      }
    });
  });
}
