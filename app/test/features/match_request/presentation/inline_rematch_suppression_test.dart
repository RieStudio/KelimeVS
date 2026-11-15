import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/application/match_requests_providers.dart';
import 'package:app/features/match_request/application/presence_controller.dart';
import 'package:app/features/match_request/data/match_request_messages.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:app/features/match_request/presentation/global_match_request_overlay.dart';
import 'package:app/features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import 'package:app/features/match_request/presentation/widgets/outgoing_match_request_chip.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class FakePresenceNotifier extends PresenceController {
  final UserPresenceState _initial;
  FakePresenceNotifier([this._initial = UserPresenceState.idle]);

  @override
  UserPresenceState build() => _initial;
}

class FakeProfileNotifier extends ProfileNotifier {
  final ProfileState initialState;
  FakeProfileNotifier(this.initialState);

  @override
  ProfileState build() => initialState;
}

class FakeSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode mode;
  FakeSessionModeNotifier(this.mode);

  @override
  MatchSessionMode build() => mode;
}

class FakeUserInboxClient extends UserInboxClient {
  FakeUserInboxClient()
      : super(
          connector: const DummyWebSocketConnector(),
          tokenProvider: const DummyAuthTokenProvider(),
          getCurrentPresenceState: () => 'idle',
        );

  @override
  bool get isConnected => true;
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
  required String opponentUid,
  String opponentName = 'Zeynep',
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
    opponentName: opponentName,
    rematchAvailable: true,
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
      roundRecords: const [],
      isFriendly: false,
      botlaOynandi: false,
    ),
  );
}

void main() {
  group('Inline Rematch Suppression & Unmount Restore Tests', () {
    testWidgets('1. MatchEndView açıkken kayıtlı rakipten gelen rematch isteğinde global banner bastırılır', (tester) async {
      final uiState = createMatchUiState(opponentUid: 'user_zeynep');
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
                const ProfileState(nickname: 'Ben', isLoaded: true),
              )),
          presenceControllerProvider.overrideWith(FakePresenceNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => GlobalMatchRequestOverlay(child: child!),
            home: const Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // MatchEndView 'user_zeynep'i satır içi kayıt etmiş olmalı
      expect(container.read(inlineHandledRematchOpponentUidProvider), 'user_zeynep');

      // 'user_zeynep'ten rematch isteği gelsin
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestReceivedMessage(
          id: 'req_rematch_in',
          fromUid: 'user_zeynep',
          fromNickname: 'Zeynep',
          fromFrame: 'classic',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();

      // Satır içi Kabul/Red butonları MatchEndView içinde görünür
      expect(find.byKey(const Key('match_end_rematch_accept_button')), findsOneWidget);

      // Ancak üstte GLOBAL IncomingMatchRequestBanner bastırılmıştır (görünmez)
      expect(find.byType(IncomingMatchRequestBanner), findsNothing);
      expect(find.byKey(const Key('incoming_match_request_banner')), findsNothing);
    });

    testWidgets('2. MatchEndView açıkken kayıtlı rakibe giden rematch isteğinde global çip bastırılır', (tester) async {
      final uiState = createMatchUiState(opponentUid: 'user_zeynep');
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
                const ProfileState(nickname: 'Ben', isLoaded: true),
              )),
          presenceControllerProvider.overrideWith(FakePresenceNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => GlobalMatchRequestOverlay(child: child!),
            home: const Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 'user_zeynep'e giden istek oluştur
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestSentMessage(
          id: 'req_rematch_out',
          toUid: 'user_zeynep',
          toNickname: 'Zeynep',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();

      // Satır içi bekleme metni MatchEndView'de görünür
      expect(find.byKey(const Key('match_end_rematch_waiting_text')), findsOneWidget);

      // Ancak global OutgoingMatchRequestChip bastırılmıştır
      expect(find.byType(OutgoingMatchRequestChip), findsNothing);
      expect(find.byKey(const Key('outgoing_match_request_chip')), findsNothing);
    });

    testWidgets('3. Kullanıcı MatchEndView ekranından ayrıldığında kayıt temizlenir ve bekleyen istek global bildirim olarak görünür', (tester) async {
      final uiState = createMatchUiState(opponentUid: 'user_zeynep');
      final fakeClient = FakeUserInboxClient();

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
          profileProvider.overrideWith(() => FakeProfileNotifier(
                const ProfileState(nickname: 'Ben', isLoaded: true),
              )),
          presenceControllerProvider.overrideWith(FakePresenceNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(matchRequestsProvider.notifier);
      notifier.attachClient(fakeClient);

      // Ana Sayfa üzerinde MatchEndView push edilmiş gibi rota yapısı kuralım
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => GlobalMatchRequestOverlay(child: child!),
            home: const Scaffold(body: Text('Ana Sayfa')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // MatchEndView'e geç
      rootNavigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const Scaffold(body: MatchEndView())),
      );
      await tester.pumpAndSettle();

      expect(container.read(inlineHandledRematchOpponentUidProvider), 'user_zeynep');

      // 'user_zeynep'ten istek gelsin (MatchEndView açıkken banner bastırılır)
      notifier.state = reduceMatchRequestMessage(
        container.read(matchRequestsProvider),
        UserInboxRequestReceivedMessage(
          id: 'req_rematch_leave_test',
          fromUid: 'user_zeynep',
          fromNickname: 'Zeynep',
          fromFrame: 'classic',
          type: MatchRequestType.ranked,
          origin: MatchRequestOrigin.rematch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        ),
      );
      await tester.pump();
      expect(find.byType(IncomingMatchRequestBanner), findsNothing);

      // Kullanıcı sol üst Kapat ikonuna basarak ana sayfaya dönsün
      await tester.tap(find.bySemanticsLabel(AppStrings.close));
      await tester.pumpAndSettle();

      // MatchEndView dispose oldu; kayıt sıfırlandı!
      expect(container.read(inlineHandledRematchOpponentUidProvider), isNull);

      // Ana Sayfadayız ve istek hâlâ geçerli olduğu için GLOBAL BANNER ortaya çıkar!
      expect(find.text('Ana Sayfa'), findsOneWidget);
      expect(find.byType(IncomingMatchRequestBanner), findsOneWidget);
      expect(find.text(AppStrings.matchRequestTitleRematch('Zeynep')), findsOneWidget);
    });

    testWidgets('4. Kayıt sızıntısı garantisi: dispose çağrısı inlineHandledRematchOpponentUidProvider sıfırlar', (tester) async {
      final uiState = createMatchUiState(opponentUid: 'user_ali');

      final container = ProviderContainer(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeSessionModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MatchEndView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(inlineHandledRematchOpponentUidProvider), 'user_ali');

      // Widget ağacını kaldır (unmount/dispose)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Text('Boş')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sıfır sızıntı: Provider değeri kesinlikle null
      expect(container.read(inlineHandledRematchOpponentUidProvider), isNull);
    });
  });
}
