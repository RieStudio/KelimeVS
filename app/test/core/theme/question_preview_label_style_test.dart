import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/theme/app_text_styles.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/round_end_view.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/matchmaking_client.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

class _FakeMatchmakingClient extends MatchmakingClient {
  final StreamController<MatchmakingEvent> controller =
      StreamController<MatchmakingEvent>.broadcast(sync: true);

  @override
  Stream<MatchmakingEvent> get events => controller.stream;

  @override
  Future<void> start(String name) async {
    controller.add(const MatchmakingConnecting());
  }

  @override
  Future<void> cancel() async {
    if (!controller.isClosed) {
      controller.add(const MatchmakingCancelled());
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await controller.close();
  }

  void emit(MatchmakingEvent event) {
    controller.add(event);
  }
}

class _FakeMatchController extends MatchController {
  final MatchUiState _initialState;

  _FakeMatchController([this._initialState = const MatchUiState()]);

  @override
  MatchUiState build() => _initialState;

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
    String? initialTurnPlayerId,
    BotConfig? botConfig,
    String? preselectedQuestionId,
    List<String>? questionOrder,
  }) async {
    state = state.copyWith(opponentName: opponentName ?? '', isLoading: true);
  }
}

class _FakeOnlineMatchSession extends OnlineMatchSession {
  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    String? opponentUid,
    String opponentFrame = 'classic',
    bool isFriendly = false,
    OnlineMatchClient? client,
  }) async {
    state = state.copyWith(opponentName: opponentName, isLoading: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Soru Önizleme Etiketi Stil ve Sabit Doğrulaması', () {
    test('1. Sabit değerler ve AppTextStyles.questionPreviewLabel tanımı doğrudur', () {
      expect(AppDimens.questionPreviewLabelFontSize, 14.0);
      expect(AppDimens.questionPreviewLabelLetterSpacing, 0.3);
      expect(AppColors.questionPreviewLabelOpacity, 0.80);
      expect(AppColors.questionPreviewLabel, const Color(0xCC14532D));

      final style = AppTextStyles.questionPreviewLabel;
      expect(style.fontFamily, AppTextStyles.fontNunito);
      expect(style.fontSize, 14.0);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.letterSpacing, 0.3);
      expect(style.color, AppColors.questionPreviewLabel);
    });

    testWidgets(
      '2. Eşleşme ekranındaki "İlk soru" etiketi AppTextStyles.questionPreviewLabel kullanır ve karttan 6 dp yukarıdadır',
      (tester) async {
        final botController = _FakeMatchController();
        final onlineSession = _FakeOnlineMatchSession();
        final mmClient = _FakeMatchmakingClient();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchControllerProvider.overrideWith(() => botController),
              onlineMatchSessionProvider.overrideWith(() => onlineSession),
              matchmakingClientFactoryProvider.overrideWithValue(
                () => mmClient,
              ),
              onlineMatchmakingEnabledProvider.overrideWithValue(true),
            ],
            child: const MaterialApp(
              home: MatchmakingScreen(),
            ),
          ),
        );
        await tester.pump();

        mmClient.emit(
          const MatchmakingMatched(
            matchId: 'm_test_1',
            opponentName: 'Deniz',
            opponentFrame: 'classic',
            firstQuestion: FirstQuestionPreview(
              id: 'q1',
              text: 'Hayvanlar Alemi',
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pump(const Duration(milliseconds: 600));

        final labelFinder = find.text(AppStrings.firstQuestionLabel);
        expect(labelFinder, findsOneWidget);
        final labelWidget = tester.widget<Text>(labelFinder);

        expect(labelWidget.style, equals(AppTextStyles.questionPreviewLabel));
        expect(labelWidget.style?.fontSize, 14.0);
        expect(labelWidget.style?.fontFamily, AppTextStyles.fontNunito);
        expect(labelWidget.style?.fontWeight, FontWeight.w800);
        expect(labelWidget.style?.letterSpacing, 0.3);
        expect(labelWidget.style?.color, AppColors.questionPreviewLabel);

        final cardFinder = find.byKey(const ValueKey('first_question_card'));
        expect(cardFinder, findsOneWidget);
        final labelBottom = tester.getBottomLeft(labelFinder).dy;
        final cardTop = tester.getTopLeft(cardFinder).dy;
        expect(cardTop - labelBottom, closeTo(AppDimens.space6, 0.5));
      },
    );

    testWidgets(
      '3. Tur sonu ekranındaki "Sıradaki soru" etiketi AppTextStyles.questionPreviewLabel kullanır ve karttan 6 dp yukarıdadır',
      (tester) async {
        const testQuestion = Question(
          id: 'q_test_1',
          categoryId: 'tarih',
          text: 'Tarihi Olaylar',
          answers: [
            Answer(id: 'a1', display: 'Cevap', aliases: ['cevap']),
          ],
        );

        final matchState = MatchState(
          config: const MatchConfig(totalDecisiveRounds: 3, answerSeconds: 20),
          playerIds: const ['me', 'bot'],
          scores: const {'me': 1, 'bot': 0},
          decisiveRounds: 1,
          totalRoundsPlayed: 1,
          phase: MatchPhase.roundEnded,
          currentQuestion: testQuestion,
          usedAnswerIds: const {},
          turnPlayerId: 'me',
          deadlineMs: 20000,
          remainingNearMisses: const {'me': 1, 'bot': 1},
          usedQuestionIds: const {'q_test_1'},
          currentRoundAttempts: const [],
          roundHistory: const [],
        );

        final roundEndUiState = MatchUiState(
          matchState: matchState,
          opponentName: 'Deniz',
          roundTransitionTotalMs: 3500,
          roundTransitionRemainingMs: 3000,
          nextQuestionText: 'Tarihi Olaylar',
          nextQuestionId: 'q2',
        );

        final roundEndController = _FakeMatchController(roundEndUiState);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              matchControllerProvider.overrideWith(() => roundEndController),
            ],
            child: const MaterialApp(
              home: RoundEndView(),
            ),
          ),
        );
        await tester.pump();

        final labelFinder = find.text(AppStrings.nextQuestionLabel);
        expect(labelFinder, findsOneWidget);
        final labelWidget = tester.widget<Text>(labelFinder);

        expect(labelWidget.style, equals(AppTextStyles.questionPreviewLabel));
        expect(labelWidget.style?.fontSize, 14.0);
        expect(labelWidget.style?.fontFamily, AppTextStyles.fontNunito);
        expect(labelWidget.style?.fontWeight, FontWeight.w800);
        expect(labelWidget.style?.letterSpacing, 0.3);
        expect(labelWidget.style?.color, AppColors.questionPreviewLabel);

        final cardFinder =
            find.byKey(const ValueKey('round_end_next_question_card'));
        expect(cardFinder, findsOneWidget);
        final labelBottom = tester.getBottomLeft(labelFinder).dy;
        final cardTop = tester.getTopLeft(cardFinder).dy;
        expect(cardTop - labelBottom, closeTo(AppDimens.space6, 0.5));
      },
    );
  });
}
