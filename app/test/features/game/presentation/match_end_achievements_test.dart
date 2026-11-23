import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/achievements/application/achievement_notification_service.dart';
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
    int oppScore = 1,
    String winnerId = 'me',
  }) {
    return MatchState(
      config: const MatchConfig(),
      playerIds: const ['me', 'opp'],
      scores: {'me': myScore, 'opp': oppScore},
      decisiveRounds: 3,
      totalRoundsPlayed: 3,
      phase: MatchPhase.matchFinished,
      currentQuestion: testQuestion,
      usedAnswerIds: const {},
      turnPlayerId: null,
      deadlineMs: 0,
      remainingNearMisses: const {'me': 0, 'opp': 0},
      usedQuestionIds: const {},
      currentRoundAttempts: const [],
      roundHistory: const [],
      winnerId: winnerId,
    );
  }

  group('MatchEndView Achievements Separation & Notification Forwarding Tests', () {
    testWidgets('1. MatchEndView gövdesinde eski "BAŞARIM AÇILDI" inline kartı ARTIK BULUNMAZ', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        coinsAwarded: 30,
        unlockedAchievements: const ['first_win'],
      );

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider.overrideWith(
            () => _TestSessionModeNotifier(MatchSessionMode.bot),
          ),
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Eski inline başarım kartı gövdede olmamalıdır
      expect(find.text('BAŞARIM AÇILDI'), findsNothing);

      // Jeton ödülü kartı gövdede görünmeye devam eder
      expect(find.text('+30${AppStrings.coinSuffix}'), findsOneWidget);
    });

    testWidgets('2. Açılan başarımlar (600ms gecikmeli olarak) global bildirim servisine iletilir', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        coinsAwarded: 50,
        unlockedAchievements: const ['first_match', 'first_win', 'streak_3'],
      );

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider.overrideWith(
            () => _TestSessionModeNotifier(MatchSessionMode.online),
          ),
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      // İlk çizim
      await tester.pump();
      // 600ms gecikme dolmadan önce henüz bildirim servisinde aktif öğe yoktur
      expect(container.read(achievementNotificationProvider).currentItem, isNull);

      // 600ms gecikmeyi ilerlet
      await tester.pump(const Duration(milliseconds: 600));

      // Artık ilk başarım aktif olmalıdır
      final active = container.read(achievementNotificationProvider).currentItem;
      expect(active, isNotNull);
      expect(active!.id, equals('first_match'));

      // Kalan 2 başarım kuyrukta bekler
      expect(
        container.read(achievementNotificationProvider.notifier).queueLength,
        equals(2),
      );
    });

    testWidgets('3. Tekrar önleme (dedup): Ekran yeniden çizildiğinde aynı başarımlar mükerrer sıraya alınmaz', (tester) async {
      final uiState = MatchUiState(
        matchState: makeFinishedMatch(),
        myPlayerId: 'me',
        unlockedAchievements: const ['streak_5'],
      );

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider.overrideWith(
            () => _TestSessionModeNotifier(MatchSessionMode.bot),
          ),
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(container.read(achievementNotificationProvider).currentItem?.id, equals('streak_5'));

      // Ekranı birden fazla kez yeniden çizdir
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Kuyrukta mükerrer öğe oluşmamalıdır
      expect(
        container.read(achievementNotificationProvider.notifier).queueLength,
        equals(0),
      );
    });

    testWidgets('4. Maç sonu ekranında yasaklı kelimeler (bot, yapay zeka, alıştırma maçı) geçmez', (tester) async {
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
        expect(content.contains('alıştırma'), isFalse, reason: 'Yasaklı "alıştırma" ifadesi bulundu: $content');
      }
    });
  });
}
