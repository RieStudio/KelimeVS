import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/data/match_request_messages.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';

class FakeSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode mode;
  FakeSessionModeNotifier(this.mode);

  @override
  MatchSessionMode build() => mode;
}

class FakeProfileNotifier extends ProfileNotifier {
  final ProfileState initialState;
  FakeProfileNotifier(this.initialState);

  @override
  ProfileState build() => initialState;
}

class FakeUserInboxClient extends UserInboxClient {
  final List<UserInboxClientMessage> sentMessages = [];
  bool connected = true;

  FakeUserInboxClient()
      : super(
          connector: const DummyWebSocketConnector(),
          tokenProvider: const DummyAuthTokenProvider(),
          getCurrentPresenceState: () => 'idle',
        );

  @override
  bool get isConnected => connected;

  @override
  bool send(UserInboxClientMessage message) {
    sentMessages.add(message);
    return true;
  }
}

class DummyWebSocketConnector implements WebSocketConnector {
  const DummyWebSocketConnector();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DummyAuthTokenProvider implements AuthTokenProvider {
  const DummyAuthTokenProvider();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MatchUiState createMatchUiState({
  bool rematchAvailable = true,
  String? opponentUid = 'user_opponent_1',
  String opponentName = 'Zeynep',
  bool isFriendly = false,
  MatchEndReason endReason = MatchEndReason.normal,
}) {
  final finishedMatchState = MatchState(
    config: const MatchConfig(),
    playerIds: const ['me', 'bot'],
    scores: const {'me': 2, 'bot': 1},
    decisiveRounds: 2,
    totalRoundsPlayed: 3,
    phase: MatchPhase.matchFinished,
    currentQuestion: const Question(
      id: 'q1',
      categoryId: 'c1',
      text: 'Soru',
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

  return MatchUiState(
    matchState: finishedMatchState,
    myPlayerId: 'me',
    isFriendly: isFriendly,
    opponentName: opponentName,
    coinsAwarded: 30,
    rematchAvailable: rematchAvailable,
    lastSavedMatch: MatchHistoryEntry(
      id: 'match_123',
      matchId: 'match_123',
      opponentName: opponentName,
      opponentUid: opponentUid,
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

void main() {
  group('MatchEndView Rematch UI & Action Area Tests', () {
    testWidgets('1. rematchAvailable=false veya opponentUid=null olduğunda yalnızca "Ana Sayfa" görünür', (tester) async {
      final uiState = createMatchUiState(rematchAvailable: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
      expect(find.text(AppStrings.homeAction), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_button')), findsNothing);
      expect(find.text(AppStrings.rematchAction), findsNothing);
    });

    testWidgets('2. İnsan rakip: Başlangıçta "Rövanş" butonu gösterilir (idle)', (tester) async {
      final uiState = createMatchUiState();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('match_end_rematch_button')), findsOneWidget);
      expect(find.text(AppStrings.rematchAction), findsOneWidget);
      expect(find.byKey(const Key('match_end_home_button')), findsNothing);
    });

    testWidgets('3. İnsan rakip: Rankli maçta enerjisi 0 iken "Rövanş"a basınca EnergyDepletedBottomSheet açılır', (tester) async {
      final uiState = createMatchUiState(isFriendly: false);
      final fakeClient = FakeUserInboxClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
            activeMatchUiStateProvider.overrideWithValue(uiState),
            profileProvider.overrideWith(() => FakeProfileNotifier(
              const ProfileState(
                energy: EnergyState(enabled: true, current: 0, max: 5),
              ),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pumpAndSettle();

      expect(find.byType(EnergyDepletedBottomSheet), findsOneWidget);
      expect(fakeClient.sentMessages, isEmpty);
    });

    testWidgets('4. İnsan rakip: Rövanş gönderildiğinde "Rövanş bekleniyor · NN sn" ve "İptal" görünür, iptal basılınca Ana Sayfa kalır', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rövanş butonuna tıkla
      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      expect(fakeClient.sentMessages.length, 1);
      final sent = fakeClient.sentMessages.first as UserInboxSendRequestMessage;
      expect(sent.origin, MatchRequestOrigin.rematch);
      expect(sent.toUid, 'user_opponent_1');
      expect(sent.matchId, 'match_123');

      // Sunucudan sent teyidi gelsin
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestSentMessage(
          id: 'req_rematch_1',
          toUid: 'user_opponent_1',
          toNickname: 'Zeynep',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('match_end_rematch_waiting_text')), findsOneWidget);
      expect(find.textContaining('Rövanş bekleniyor'), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_cancel_button')), findsOneWidget);
      expect(find.text(AppStrings.matchRequestCancel), findsOneWidget);

      // İptal butonuna tıkla
      await tester.tap(find.byKey(const Key('match_end_rematch_cancel_button')));
      await tester.pump();

      expect(fakeClient.sentMessages.any((m) => m is UserInboxCancelRequestMessage), isTrue);

      // İptal sonrası yalnızca Ana Sayfa butonu görünür, Rövanş butonu tekrar aktif olmaz
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_button')), findsNothing);
    });

    testWidgets('5. İnsan rakip: Gelen rövanş isteği satır içi gösterilir, Kabul Et basılınca "Rövanş başlıyor..." olur', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      // Rakipten gelen rövanş isteği
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestReceivedMessage(
          id: 'req_incoming_rematch',
          fromUid: 'user_opponent_1',
          fromNickname: 'Zeynep',
          fromFrame: 'classic',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.rematchOfferedBy('Zeynep')), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_accept_button')), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_decline_button')), findsOneWidget);

      // Kabul Et'e tıkla
      await tester.tap(find.byKey(const Key('match_end_rematch_accept_button')));
      await tester.pump();

      expect(fakeClient.sentMessages.any((m) => m is UserInboxAcceptRequestMessage), isTrue);
      expect(find.byKey(const Key('match_end_rematch_starting_button')), findsOneWidget);
      expect(find.text(AppStrings.rematchStarting), findsOneWidget);
    });

    testWidgets('6. İnsan rakip: Gelen istek reddedilince "Rövanş reddedildi" KIRMIZI metinle çıkar ve Ana Sayfa gösterilir', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestReceivedMessage(
          id: 'req_incoming_rematch',
          fromUid: 'user_opponent_1',
          fromNickname: 'Zeynep',
          fromFrame: 'classic',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reddet'e tıkla
      await tester.tap(find.byKey(const Key('match_end_rematch_decline_button')));
      await tester.pump();

      expect(fakeClient.sentMessages.any((m) => m is UserInboxDeclineRequestMessage), isTrue);

      final textFinder = find.text(AppStrings.rematchDeclined);
      expect(textFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.color, AppColors.dangerText);

      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_button')), findsNothing);
    });

    testWidgets('7. İnsan rakip: Karşı taraf reddettiğinde (declined status) "Rövanş reddedildi" kırmızı görünür', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rövanş teklif et
      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestSentMessage(
          id: 'req_out_1',
          toUid: 'user_opponent_1',
          toNickname: 'Zeynep',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();

      // Karşı taraf reddetti
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestStatusMessage(
          id: 'req_out_1',
          status: MatchRequestEndStatus.declined,
        ),
      );
      await tester.pump();

      final textFinder = find.text(AppStrings.rematchDeclined);
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.color, AppColors.dangerText);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('8. İnsan rakip: İstek zaman aşımına uğradığında "Süre doldu" (muted) görünür', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestSentMessage(
          id: 'req_out_exp',
          toUid: 'user_opponent_1',
          toNickname: 'Zeynep',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();

      // Süre doldu mesajı
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestStatusMessage(
          id: 'req_out_exp',
          status: MatchRequestEndStatus.expired,
        ),
      );
      await tester.pump();

      final textFinder = find.text(AppStrings.rematchExpired);
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.color, AppColors.muted);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('9. İnsan rakip: Sunucu unavailable döndüğünde satır içi "Rakip şu an müsait değil" görünür', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      // Sunucu unavailable döndü (alıcı çevrimdışı, meşgul veya kapalı)
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestErrorMessage(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      await tester.pump();

      final textFinder = find.text(AppStrings.rematchUnavailable);
      expect(textFinder, findsOneWidget);
      expect(find.text('Rakip şu an müsait değil'), findsOneWidget);
      // Alıcı müsait olmadığında hak yanmaz, "Rövanş" (tekrar dene) butonu aktif kalır
      final retryBtnFinder = find.byKey(const Key('match_end_rematch_retry_button'));
      expect(retryBtnFinder, findsOneWidget);

      // Tekrar dene butonuna tıklandığında yeniden istek gönderilir
      fakeClient.sentMessages.clear();
      await tester.tap(retryBtnFinder);
      await tester.pump();

      expect(fakeClient.sentMessages, hasLength(1));
      expect(fakeClient.sentMessages[0].toJson()['t'], 'send_match_request');
    });

    testWidgets('10. İnsan rakip: opponentNoEnergy geldiğinde "Rakibin enerjisi yetersiz" kırmızı görünür', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestErrorMessage(
          code: MatchRequestErrorCode.opponentNoEnergy,
        ),
      );
      await tester.pump();

      final textFinder = find.text(AppStrings.rematchOpponentNoEnergy);
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.color, AppColors.dangerText);
      expect(find.byKey(const Key('match_end_home_button')), findsOneWidget);
    });

    testWidgets('11. "Rakip ayrıldı" ifadesi ekranda kesinlikle bulunmaz', (tester) async {
      final uiState = createMatchUiState();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rakip ayrıldı'), findsNothing);
      expect(find.textContaining('ayrıldı'), findsNothing);
    });

    testWidgets('12. İnsan rakip: cooldown_active ve rate_limited geldiğinde doğru mesaj ve aktif Rövanş butonu görünür', (tester) async {
      final uiState = createMatchUiState();
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
            const ProfileState(
              energy: EnergyState(enabled: true, current: 3, max: 5),
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('match_end_rematch_button')));
      await tester.pump();

      // Cooldown hatası
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestErrorMessage(
          code: MatchRequestErrorCode.cooldownActive,
          retryAfterSec: 25,
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.matchRequestCooldownToast(25)), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_retry_button')), findsOneWidget);

      // Rate limit hatası
      await tester.tap(find.byKey(const Key('match_end_rematch_retry_button')));
      await tester.pump();

      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestErrorMessage(
          code: MatchRequestErrorCode.rateLimited,
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.matchRequestRateLimitedToast), findsOneWidget);
      expect(find.byKey(const Key('match_end_rematch_retry_button')), findsOneWidget);
    });
  });
}
