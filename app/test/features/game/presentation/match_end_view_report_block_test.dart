import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/profile/data/blocked_users_api_client.dart';
import 'package:app/features/profile/domain/blocked_user_model.dart';

class FakeBlockedUsersClient implements BlockedUsersApiClient {
  bool reportCalled = false;
  String? reportedMatchId;
  String? reportedReason;

  bool blockCalled = false;
  String? blockedMatchId;

  ReportUserResult reportResultToReturn = const ReportUserSuccess();
  BlockUserResult blockResultToReturn = const BlockUserSuccess('block_id_1');

  @override
  Future<List<BlockedUser>> getBlockedUsers() async => const [];

  @override
  Future<bool> unblockUser(String id) async => true;

  @override
  Future<BlockUserResult> blockUser(String matchId) async {
    blockCalled = true;
    blockedMatchId = matchId;
    return blockResultToReturn;
  }

  @override
  Future<ReportUserResult> reportUser({
    required String matchId,
    required String reason,
  }) async {
    reportCalled = true;
    reportedMatchId = matchId;
    reportedReason = reason;
    return reportResultToReturn;
  }
}

class FakeSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode mode;
  FakeSessionModeNotifier(this.mode);

  @override
  MatchSessionMode build() => mode;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MatchState createMatchState() {
    return MatchState(
      config: const MatchConfig(),
      playerIds: const ['me', 'opponent'],
      scores: const {'me': 2, 'opponent': 1},
      decisiveRounds: 0,
      totalRoundsPlayed: 3,
      phase: MatchPhase.matchFinished,
      currentQuestion: null,
      usedAnswerIds: const {},
      turnPlayerId: null,
      deadlineMs: 0,
      remainingNearMisses: const {'me': 1, 'opponent': 1},
      usedQuestionIds: const {},
      roundHistory: const [],
      currentRoundAttempts: const [],
      winnerId: 'me',
      lastSubmitTimes: const {},
      currentTurnAttempts: 0,
      endedBy: null,
    );
  }

  Widget buildTestScreen({
    required MatchSessionMode mode,
    required MatchUiState uiState,
    required FakeBlockedUsersClient client,
  }) {
    return ProviderScope(
      overrides: [
        activeMatchSessionModeProvider.overrideWith(() => FakeSessionModeNotifier(mode)),
        activeMatchUiStateProvider.overrideWithValue(uiState),
        blockedUsersApiClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: MatchEndView(),
        ),
      ),
    );
  }

  testWidgets('1. Bot maçlarında (sunucuya gitmeyen) Bildir ve Engelle düğmeleri ASLA gösterilmez', (tester) async {
    final client = FakeBlockedUsersClient();
    final uiState = MatchUiState(
      matchState: createMatchState(),
      lastSavedMatch: const MatchHistoryEntry(
        id: 'local_bot_1',
        opponentName: 'Bot Ahmet',
        finishedAtMs: 1000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        botlaOynandi: true, // Bot maçı
      ),
    );

    await tester.pumpWidget(buildTestScreen(
      mode: MatchSessionMode.bot,
      uiState: uiState,
      client: client,
    ));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.reportAction), findsNothing);
    expect(find.text(AppStrings.blockAction), findsNothing);
  });

  testWidgets('2. Online maçta rakip kartı ile Bildir ve Engelle düğmeleri görünür', (tester) async {
    final client = FakeBlockedUsersClient();
    final uiState = MatchUiState(
      matchState: createMatchState(),
      lastSavedMatch: const MatchHistoryEntry(
        id: 'online_123',
        matchId: 'match_server_123',
        opponentName: 'CanliRakip',
        finishedAtMs: 1000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        botlaOynandi: false, // Online maç
      ),
    );

    await tester.pumpWidget(buildTestScreen(
      mode: MatchSessionMode.online,
      uiState: uiState,
      client: client,
    ));
    await tester.pumpAndSettle();

    expect(find.text('CanliRakip'), findsOneWidget);
    expect(find.text(AppStrings.reportAction), findsOneWidget);
    expect(find.text(AppStrings.blockAction), findsOneWidget);
  });

  testWidgets('3. Bildir akışı: Bottom sheet açılır, sebep seçilir ve bildirim gönderilip buton Bildirildi olur', (tester) async {
    final client = FakeBlockedUsersClient();
    final uiState = MatchUiState(
      matchState: createMatchState(),
      lastSavedMatch: const MatchHistoryEntry(
        id: 'online_123',
        matchId: 'match_server_123',
        opponentName: 'CanliRakip',
        finishedAtMs: 1000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        botlaOynandi: false,
      ),
    );

    await tester.pumpWidget(buildTestScreen(
      mode: MatchSessionMode.online,
      uiState: uiState,
      client: client,
    ));
    await tester.pumpAndSettle();

    // Bildir düğmesine dokun
    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.reportAction));
    await tester.pumpAndSettle();

    // Bottom sheet görünmeli
    expect(find.text(AppStrings.reportDialogTitle), findsOneWidget);
    expect(find.text(AppStrings.reasonInappropriateNickname), findsOneWidget);
    expect(find.text(AppStrings.reasonInappropriateContent), findsOneWidget);
    expect(find.text(AppStrings.reasonCheating), findsOneWidget);
    expect(find.text(AppStrings.reasonOther), findsOneWidget);

    // Bir sebep seç ("Uygunsuz takma ad")
    await tester.tap(find.text(AppStrings.reasonInappropriateNickname));
    await tester.pumpAndSettle();

    // Bildir (PrimaryButton) düğmesine dokun
    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.reportAction));
    await tester.pumpAndSettle();

    expect(client.reportCalled, isTrue);
    expect(client.reportedMatchId, 'match_server_123');
    expect(client.reportedReason, 'inappropriate_nickname');

    // Başarı SnackBar'ı görünmeli
    expect(find.text(AppStrings.reportSuccess), findsOneWidget);

    // Düğme "Bildirildi" olmuş ve kapanmış (onPressed: null) olmalı
    expect(find.text(AppStrings.reportedStatus), findsOneWidget);
    final reportedBtn = tester.widget<SecondaryButton>(
      find.widgetWithText(SecondaryButton, AppStrings.reportedStatus),
    );
    expect(reportedBtn.onPressed, isNull);
  });

  testWidgets('4. Engelle akışı: Onay penceresi açılır, onaylanınca engellenir ve buton Engellendi olur', (tester) async {
    final client = FakeBlockedUsersClient();
    final uiState = MatchUiState(
      matchState: createMatchState(),
      lastSavedMatch: const MatchHistoryEntry(
        id: 'online_123',
        matchId: 'match_server_123',
        opponentName: 'CanliRakip',
        finishedAtMs: 1000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: [],
        botlaOynandi: false,
      ),
    );

    await tester.pumpWidget(buildTestScreen(
      mode: MatchSessionMode.online,
      uiState: uiState,
      client: client,
    ));
    await tester.pumpAndSettle();

    // Engelle düğmesine dokun
    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.blockAction));
    await tester.pumpAndSettle();

    // AlertDialog açılmalı
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppStrings.blockDialogTitle), findsOneWidget);

    // Onayla ("Engelle" PrimaryButton)
    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.blockConfirm));
    await tester.pumpAndSettle();

    expect(client.blockCalled, isTrue);
    expect(client.blockedMatchId, 'match_server_123');

    // Başarı SnackBar'ı görünmeli
    expect(find.text(AppStrings.blockSuccess('CanliRakip')), findsOneWidget);

    // Düğme "Engellendi" durumuna geçmiş ve kapanmış olmalı
    expect(find.text(AppStrings.blockedStatus), findsOneWidget);
    final blockedBtn = tester.widget<SecondaryButton>(
      find.widgetWithText(SecondaryButton, AppStrings.blockedStatus),
    );
    expect(blockedBtn.onPressed, isNull);
  });
}
