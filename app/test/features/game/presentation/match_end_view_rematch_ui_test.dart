import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/friend_match/presentation/friend_reveal_screen.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';

class _TestSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode _initial;
  _TestSessionModeNotifier(this._initial);
  @override
  MatchSessionMode build() => _initial;
}

class _MockOnlineMatchSession extends OnlineMatchSession {
  int offerRematchCalls = 0;
  int acceptRematchCalls = 0;
  int declineRematchCalls = 0;
  int leaveRematchCalls = 0;

  @override
  bool offerRematch() {
    offerRematchCalls++;
    return true;
  }

  @override
  bool acceptRematch() {
    acceptRematchCalls++;
    return true;
  }

  @override
  bool declineRematch() {
    declineRematchCalls++;
    return true;
  }

  @override
  void leaveRematch() {
    leaveRematchCalls++;
  }
}

class _TestProfileNotifier extends ProfileNotifier {
  final int energyCurrent;

  _TestProfileNotifier({this.energyCurrent = 5});

  @override
  ProfileState build() {
    return ProfileState(
      nickname: 'TestPlayer',
      energy: EnergyState(
        enabled: true,
        current: energyCurrent,
        max: 5,
      ),
    );
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
    playerIds: const ['me', 'opponent'],
    scores: const {'me': 2, 'opponent': 1},
    decisiveRounds: 3,
    totalRoundsPlayed: 3,
    phase: MatchPhase.matchFinished,
    currentQuestion: testQuestion,
    usedAnswerIds: const {},
    turnPlayerId: null,
    deadlineMs: 0,
    remainingNearMisses: const {'me': 0, 'opponent': 0},
    usedQuestionIds: const {},
    currentRoundAttempts: const [],
    roundHistory: const [],
    winnerId: 'me',
  );

  MatchUiState createUiState({
    bool isFriendly = false,
    MatchEndReason endReason = MatchEndReason.normal,
    String opponentName = 'Selim',
  }) {
    return MatchUiState(
      matchState: finishedMatchState,
      opponentName: opponentName,
      isFriendly: isFriendly,
      coinsAwarded: isFriendly ? null : 30,
      lastSavedMatch: MatchHistoryEntry(
        id: 'hist_1',
        matchId: 'match_123',
        opponentName: opponentName,
        finishedAtMs: 12345678,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        endReason: endReason,
        roundRecords: const [],
        isFriendly: isFriendly,
        botlaOynandi: false,
      ),
    );
  }

  Widget buildTestApp({
    required MatchSessionMode mode,
    required RematchState rematchState,
    required _MockOnlineMatchSession mockSession,
    MatchUiState? uiState,
    bool isFriendly = false,
    int energyCurrent = 5,
    double screenWidth = 360,
    double screenHeight = 640,
    double textScale = 1.0,
  }) {
    final state = uiState ?? createUiState(isFriendly: isFriendly);

    return ProviderScope(
      overrides: [
        activeMatchSessionModeProvider.overrideWith(() => _TestSessionModeNotifier(mode)),
        activeMatchUiStateProvider.overrideWithValue(state),
        rematchStateProvider.overrideWithValue(rematchState),
        onlineMatchSessionProvider.overrideWith(() => mockSession),
        profileProvider.overrideWith(() => _TestProfileNotifier(energyCurrent: energyCurrent)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(screenWidth, screenHeight),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(
            body: MatchEndView(),
          ),
        ),
      ),
    );
  }

  group('MatchEndView Rematch UI State Tests', () {
    testWidgets('1. idle durumu: PrimaryButton "Rövanş" gösterilir ve dokununca offerRematch çağrılır', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.idle,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      final rematchBtn = find.byKey(const Key('match_end_rematch_button'));
      expect(rematchBtn, findsOneWidget);
      expect(find.text(AppStrings.rematchAction), findsOneWidget);

      await tester.tap(rematchBtn);
      await tester.pump();

      expect(mockSession.offerRematchCalls, 1);
    });

    testWidgets('2. pendingSent durumu: pasif PrimaryButton "Rövanş bekleniyor (N)" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.pendingSent(secondsRemaining: 42),
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      final waitingBtn = find.byKey(const Key('match_end_rematch_waiting_button'));
      expect(waitingBtn, findsOneWidget);
      expect(find.text(AppStrings.rematchWaiting(42)), findsOneWidget);

      // Buton pasiftir, dokunulsa bile offerRematch tetiklenmez
      await tester.tap(waitingBtn);
      await tester.pump();

      expect(mockSession.offerRematchCalls, 0);
    });

    testWidgets('3. pendingReceived durumu: Rakip adı satırı, Reddet ve Kabul Et (N) butonları gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.pendingReceived(secondsRemaining: 38),
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      // Üstte bilgi: "Selim rövanş istiyor!"
      expect(find.text(AppStrings.rematchOfferedBy('Selim')), findsOneWidget);

      // Yan yana iki buton: Reddet (Secondary) ve Kabul Et (Primary)
      final declineBtn = find.byKey(const Key('match_end_rematch_decline_button'));
      final acceptBtn = find.byKey(const Key('match_end_rematch_accept_button'));

      expect(declineBtn, findsOneWidget);
      expect(acceptBtn, findsOneWidget);
      expect(find.text(AppStrings.rematchDecline), findsOneWidget);
      expect(find.text(AppStrings.rematchAccept(38)), findsOneWidget);

      // Reddet'e basılınca declineRematch çağrılır
      await tester.tap(declineBtn);
      await tester.pump();
      expect(mockSession.declineRematchCalls, 1);

      // Kabul Et'e basılınca acceptRematch çağrılır
      await tester.tap(acceptBtn);
      await tester.pump();
      expect(mockSession.acceptRematchCalls, 1);
    });

    testWidgets('4. starting durumu: pasif PrimaryButton "Rövanş başlıyor..." gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.starting,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      final startingBtn = find.byKey(const Key('match_end_rematch_starting_button'));
      expect(startingBtn, findsOneWidget);
      expect(find.text(AppStrings.rematchStarting), findsOneWidget);
    });

    testWidgets('5. declined durumu: "Rövanş reddedildi" bilgi satırı ve PrimaryButton "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.declined,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchDeclined), findsOneWidget);
      final homeBtn = find.byKey(const Key('match_end_home_button'));
      expect(homeBtn, findsOneWidget);
      expect(find.text(AppStrings.homeAction), findsOneWidget);
    });

    testWidgets('6. expired durumu: "Süre doldu" bilgi satırı ve PrimaryButton "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.expired,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchExpired), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('7. opponentLeft durumu: "Rakip ayrıldı" bilgi satırı ve PrimaryButton "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.opponentLeft,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchOpponentLeft), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('8. error(no_energy) durumu: "Enerjin yetersiz" bilgi satırı ve "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.error(RematchErrorCode.noEnergy),
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchNoEnergy), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('9. error(opponent_no_energy) durumu: "Rakibin enerjisi yetersiz" bilgi satırı ve "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.error(RematchErrorCode.opponentNoEnergy),
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchOpponentNoEnergy), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('10. error(blocked / unavailable) durumu: "Rövanş şu anda mümkün değil" bilgi satırı ve "Ana Sayfa" gösterilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.error(RematchErrorCode.blocked),
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchUnavailable), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('11. unavailable durumu: üstte bilgi metni GÖRÜNMEZ, yalnızca "Ana Sayfa" butonu görünür', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.unavailable,
        mockSession: mockSession,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchDeclined), findsNothing);
      expect(find.text(AppStrings.rematchExpired), findsNothing);
      expect(find.text(AppStrings.rematchOpponentLeft), findsNothing);
      expect(find.text(AppStrings.rematchUnavailable), findsNothing);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
      expect(find.text(AppStrings.homeAction), findsOneWidget);
    });
  });

  group('Ranked Energy Pre-check Tests', () {
    testWidgets('12. Rankli maçta enerjisi 0 olan kullanıcı "Rövanş"a basınca offer gönderilmez, EnergyDepletedBottomSheet açılır', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.idle,
        mockSession: mockSession,
        isFriendly: false,
        energyCurrent: 0,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pumpAndSettle();

      // İstek gönderilmemeli
      expect(mockSession.offerRematchCalls, 0);
      // Enerji sayfası açılmalı
      expect(find.byType(EnergyDepletedBottomSheet), findsOneWidget);
    });

    testWidgets('13. Rankli maçta enerjisi 0 olan kullanıcı "Kabul Et"e basınca accept gönderilmez, EnergyDepletedBottomSheet açılır', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.pendingReceived(secondsRemaining: 30),
        mockSession: mockSession,
        isFriendly: false,
        energyCurrent: 0,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_accept_button')));
      await tester.pumpAndSettle();

      // Kabul gönderilmemeli
      expect(mockSession.acceptRematchCalls, 0);
      // Enerji sayfası açılmalı
      expect(find.byType(EnergyDepletedBottomSheet), findsOneWidget);
    });

    testWidgets('14. Arkadaş (friendly) maçında enerjisi 0 olan kullanıcı "Rövanş"a basınca kontrol bypass edilir ve offer gönderilir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.idle,
        mockSession: mockSession,
        isFriendly: true,
        energyCurrent: 0,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      // Friendly olduğu için istek hemen gider
      expect(mockSession.offerRematchCalls, 1);
      expect(find.byType(EnergyDepletedBottomSheet), findsNothing);
    });
  });

  group('Bot Match Rematch Flow Tests', () {
    testWidgets('15. Bot maçı normal bittiğinde Rövanş butonu görünür, basılınca geri sayım başlar', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.bot,
        rematchState: RematchState.unavailable,
        mockSession: mockSession,
        uiState: createUiState(isFriendly: false, endReason: MatchEndReason.normal),
      ));
      await tester.pumpAndSettle();

      final rematchBtn = find.byKey(const Key('match_end_rematch_button'));
      expect(rematchBtn, findsOneWidget);

      await tester.tap(rematchBtn);
      await tester.pump();

      // Bot geri sayımı başlar
      expect(find.byKey(const Key('match_end_rematch_waiting_button')), findsOneWidget);
      expect(find.text(AppStrings.rematchWaiting(45)), findsOneWidget);

      // Ağ veya sunucu çağrısı yapılmaz
      expect(mockSession.offerRematchCalls, 0);
      expect(mockSession.leaveRematchCalls, 0);
    });

    testWidgets('16. Bot maçı terk ile bittiğinde (anormal) Rövanş butonu görünmez, doğrudan Ana Sayfa görünür', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.bot,
        rematchState: RematchState.unavailable,
        mockSession: mockSession,
        uiState: createUiState(isFriendly: false, endReason: MatchEndReason.terk),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('match_end_rematch_button')), findsNothing);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
      expect(find.text(AppStrings.rematchUnavailable), findsNothing);
    });
  });

  group('Matched State Transition & Leave Safety Tests', () {
    testWidgets('17. matched mesajı geldiğinde openRematchReveal tetiklenir ve dispose leaveRematch çağırmaz', (tester) async {
      final mockSession = _MockOnlineMatchSession();
      final matchedMessage = MatchedServerMessage(
        matchId: 'new_match_999',
        opponentName: 'Can',
        opponentFrame: 'mint',
        opponentUid: 'uid_can_123',
        isFriendly: false,
      );

      await tester.pumpWidget(buildTestApp(
        mode: MatchSessionMode.online,
        rematchState: RematchState.matched(matchedMessage),
        mockSession: mockSession,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // FriendMatchRevealScreen'e geçilmiş olmalı
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);

      // MatchEndView dispose edilmiş olmalı ama leaveRematch ÇAĞRILMAMIŞ olmalı!
      expect(mockSession.leaveRematchCalls, 0);
    });
  });

  group('Responsive Layout & Overflow Tests', () {
    testWidgets('18. 320 dp ve 360 dp genişlikte, 1.5 yazı ölçeğinde pendingReceived ve idle sıfır taşma üretir', (tester) async {
      final mockSession = _MockOnlineMatchSession();

      for (final width in [320.0, 360.0]) {
        // Test idle
        await tester.pumpWidget(buildTestApp(
          mode: MatchSessionMode.online,
          rematchState: RematchState.idle,
          mockSession: mockSession,
          screenWidth: width,
          textScale: 1.5,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'idle overflow at width $width');

        // Test pendingReceived (yan yana 2 buton)
        await tester.pumpWidget(buildTestApp(
          mode: MatchSessionMode.online,
          rematchState: RematchState.pendingReceived(secondsRemaining: 45),
          mockSession: mockSession,
          screenWidth: width,
          textScale: 1.5,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'pendingReceived overflow at width $width');

        // Test declined info
        await tester.pumpWidget(buildTestApp(
          mode: MatchSessionMode.online,
          rematchState: RematchState.declined,
          mockSession: mockSession,
          screenWidth: width,
          textScale: 1.5,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'declined overflow at width $width');
      }
    });
  });
}
