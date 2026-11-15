import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/application/match_requests_providers.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:app/features/match_request/presentation/global_match_request_overlay.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/profile/application/public_profile_provider.dart';
import 'package:app/features/profile/data/public_profile_api_client.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';
import 'package:app/features/profile/presentation/public_profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeUser implements User {
  @override
  final String uid;
  FakeUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  final User? user;
  FakeAuthRepository([this.user]);

  @override
  User? get currentUser => user;

  @override
  bool get isAuthenticated => user != null;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePublicProfileApiClient implements PublicProfileApiClient {
  final PublicProfile? profileToReturn;
  FakePublicProfileApiClient({this.profileToReturn});

  @override
  Future<PublicProfile> getPublicProfile(String uid) async {
    return profileToReturn ??
        PublicProfile(
          uid: uid,
          nickname: 'Alice',
          equippedFrame: 'classic',
          stats: const PublicProfileStats(
            played: 10,
            won: 7,
            lost: 3,
            winRate: 70,
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PublicProfileScreen Match Request Action Tests', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    Widget createTestWidget({
      required ProviderContainer container,
      required String targetUid,
    }) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) =>
              GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
          home: PublicProfileScreen(uid: targetUid),
        ),
      );
    }

    testWidgets('başkasının profilinde "Maç İsteği Gönder" butonu görünür ve basılınca istek gönderir',
        (tester) async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(FakeUser('my_uid'))),
          publicProfileApiClientProvider.overrideWithValue(FakePublicProfileApiClient()),
          userInboxClientProvider.overrideWithValue(client),
        ],
      );

      try {
        await client.connect();
        container.read(matchRequestsProvider.notifier).attachClient(client);

        await tester.pumpWidget(
          createTestWidget(container: container, targetUid: 'u_target_alice'),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.matchRequestSendAction), findsOneWidget);
        expect(find.text(AppStrings.blockAction), findsOneWidget);

        // Butona dokun
        await tester.tap(find.text(AppStrings.matchRequestSendAction));
        await tester.pump();

        // Sokete istek gönderilmiş olmalı
        expect(fakeConnection.sentMessages, contains(
          '{"t":"send_match_request","origin":"profile","toUid":"u_target_alice"}',
        ));
      } finally {
        await client.close();
        container.dispose();
      }
    });

    testWidgets('bu kişiye giden istek beklerken "İstek Bekleniyor" (disabled) ve "İptal" görünür',
        (tester) async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(FakeUser('my_uid'))),
          publicProfileApiClientProvider.overrideWithValue(FakePublicProfileApiClient()),
          userInboxClientProvider.overrideWithValue(client),
        ],
      );

      try {
        await client.connect();
        container.read(matchRequestsProvider.notifier).attachClient(client);

        // Bu kişiye bekleyen giden istek ver
        container.read(matchRequestsProvider.notifier).state =
            MatchRequestsState(
          connectionState: UserInboxConnectionState.connected,
          outgoing: OutgoingMatchRequest(
            id: 'out_req_alice',
            toUid: 'u_target_alice',
            toNickname: 'Alice',
            type: MatchRequestType.friendly,
            origin: MatchRequestOrigin.profile,
            expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
          ),
        );

        await tester.pumpWidget(
          createTestWidget(container: container, targetUid: 'u_target_alice'),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.matchRequestWaitingAction), findsOneWidget);
        expect(find.text(AppStrings.matchRequestCancel), findsOneWidget);

        final cancelButton = tester.widget<SecondaryButton>(
          find.widgetWithText(SecondaryButton, AppStrings.matchRequestCancel),
        );
        expect(cancelButton.textColor, AppColors.dangerText);
        expect(cancelButton.borderColor, AppColors.danger);
        expect(cancelButton.backgroundColor, AppColors.card);

        // İptal butonuna basıldığında sokete iptal mesajı gitmeli
        await tester.tap(find.text(AppStrings.matchRequestCancel));
        await tester.pump();

        expect(fakeConnection.sentMessages, contains(
          '{"t":"cancel_match_request","id":"out_req_alice"}',
        ));
      } finally {
        await client.close();
        container.dispose();
      }
    });

    testWidgets('başka birine giden istek varken butona dokunulursa uyarı mesajı verilir',
        (tester) async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(FakeUser('my_uid'))),
          publicProfileApiClientProvider.overrideWithValue(FakePublicProfileApiClient()),
          userInboxClientProvider.overrideWithValue(client),
        ],
      );

      try {
        await client.connect();
        container.read(matchRequestsProvider.notifier).attachClient(client);

        // Başka birine bekleyen istek ver
        container.read(matchRequestsProvider.notifier).state =
            MatchRequestsState(
          connectionState: UserInboxConnectionState.connected,
          outgoing: OutgoingMatchRequest(
            id: 'out_req_bob',
            toUid: 'u_target_bob',
            toNickname: 'Bob',
            type: MatchRequestType.friendly,
            origin: MatchRequestOrigin.profile,
            expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
          ),
        );

        await tester.pumpWidget(
          createTestWidget(container: container, targetUid: 'u_target_alice'),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.matchRequestSendAction), findsOneWidget);

        await tester.tap(find.text(AppStrings.matchRequestSendAction));
        await tester.pump();

        // SnackBar uyarısı çıkmalı
        expect(find.text(AppStrings.matchRequestAlreadyPendingToast), findsOneWidget);
      } finally {
        await client.close();
        container.dispose();
      }
    });

    testWidgets('soket bağlantısı kopukken butona dokunulursa "Bağlantı kuruluyor" tostu verilir',
        (tester) async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(FakeUser('my_uid'))),
          publicProfileApiClientProvider.overrideWithValue(FakePublicProfileApiClient()),
          userInboxClientProvider.overrideWithValue(client),
        ],
      );

      try {
        // Bağlanmadık, disconnected durumunda
        container.read(matchRequestsProvider.notifier).attachClient(client);
        container.read(matchRequestsProvider.notifier).state =
            const MatchRequestsState(
          connectionState: UserInboxConnectionState.disconnected,
        );

        await tester.pumpWidget(
          createTestWidget(container: container, targetUid: 'u_target_alice'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.matchRequestSendAction));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(AppStrings.matchRequestConnectingToast), findsOneWidget);
      } finally {
        await client.close();
        container.dispose();
      }
    });

    testWidgets('oyuncu engellenmişse maç isteği butonu gösterilmez (engelli görünümü)',
        (tester) async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(FakeUser('my_uid'))),
          publicProfileApiClientProvider.overrideWithValue(
            FakePublicProfileApiClient(
              profileToReturn: const PublicProfile(
                uid: 'u_target_alice',
                nickname: 'Alice',
                equippedFrame: 'classic',
                stats: PublicProfileStats(
                  played: 10,
                  won: 7,
                  lost: 3,
                  winRate: 70,
                ),
                isBlocked: true,
              ),
            ),
          ),
          userInboxClientProvider.overrideWithValue(client),
        ],
      );

      try {
        await tester.pumpWidget(
          createTestWidget(container: container, targetUid: 'u_target_alice'),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.matchRequestSendAction), findsNothing);
        expect(find.text(AppStrings.matchRequestWaitingAction), findsNothing);
        expect(find.text(AppStrings.profileBlockedBanner), findsOneWidget);
        expect(find.text(AppStrings.unblockAction), findsOneWidget);
      } finally {
        await client.close();
        container.dispose();
      }
    });
  });
}
