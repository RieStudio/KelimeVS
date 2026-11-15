import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/application/match_requests_providers.dart';
import 'package:app/features/match_request/application/presence_controller.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthNotifier extends AuthNotifier {
  final AuthUiState _state;
  FakeAuthNotifier(this._state);

  @override
  AuthUiState build() => _state;

  void updateAuthenticated(bool auth) {
    state = state.copyWith(isAuthenticated: auth);
  }
}

class FakeProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  FakeProfileNotifier(this._state);

  @override
  ProfileState build() => _state;

  void updateNickname(String? nickname) {
    state = state.copyWith(nickname: nickname);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserInboxLifecycleCoordinator', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;
    late FakeAuthNotifier fakeAuthNotifier;
    late FakeProfileNotifier fakeProfileNotifier;
    late ProviderContainer container;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');

      fakeAuthNotifier = FakeAuthNotifier(
        const AuthUiState(isAuthenticated: true, isGoogleLinked: false),
      );
      fakeProfileNotifier = FakeProfileNotifier(
        const ProfileState(nickname: 'Alice'),
      );

      container = ProviderContainer(
        overrides: [
          userInboxConnectorProvider.overrideWithValue(fakeConnector),
          userInboxTokenProvider.overrideWithValue(fakeTokenProvider),
          authNotifierProvider.overrideWith(() => fakeAuthNotifier),
          profileProvider.overrideWith(() => fakeProfileNotifier),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Kullanıcı giriş yapmış ve takma adı varsa ön plandayken bağlanır', () async {
      final coordinator = container.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      final client = container.read(userInboxClientProvider);
      expect(client.isConnected, isTrue);
    });

    test('Kullanıcı giriş yapmamışsa bağlanmaz veya açıksa kapatır', () async {
      fakeAuthNotifier = FakeAuthNotifier(
        const AuthUiState(isAuthenticated: false, isGoogleLinked: false),
      );

      final unauthContainer = ProviderContainer(
        overrides: [
          userInboxConnectorProvider.overrideWithValue(fakeConnector),
          userInboxTokenProvider.overrideWithValue(fakeTokenProvider),
          authNotifierProvider.overrideWith(() => fakeAuthNotifier),
          profileProvider.overrideWith(() => fakeProfileNotifier),
        ],
      );

      final coordinator = unauthContainer.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      final client = unauthContainer.read(userInboxClientProvider);
      expect(client.isConnected, isFalse);

      unauthContainer.dispose();
    });

    test('Takma adı yoksa (onboarding tamamlanmamışsa) bağlanmaz', () async {
      fakeProfileNotifier = FakeProfileNotifier(
        const ProfileState(nickname: null),
      );

      final noNickContainer = ProviderContainer(
        overrides: [
          userInboxConnectorProvider.overrideWithValue(fakeConnector),
          userInboxTokenProvider.overrideWithValue(fakeTokenProvider),
          authNotifierProvider.overrideWith(() => fakeAuthNotifier),
          profileProvider.overrideWith(() => fakeProfileNotifier),
        ],
      );

      final coordinator = noNickContainer.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      final client = noNickContainer.read(userInboxClientProvider);
      expect(client.isConnected, isFalse);

      noNickContainer.dispose();
    });

    test('Arka plana geçildiğinde (paused/inactive) yerel istekler temizlenir ve soket 1000 ile kapatılır', () async {
      final coordinator = container.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      final client = container.read(userInboxClientProvider);
      expect(client.isConnected, isTrue);

      // Bekleyen istek simüle et
      fakeConnection.emitIncoming(
        '{"t":"match_request_received","id":"req_in","fromUid":"u_1","fromNickname":"One","fromFrame":"f1","type":"friendly","origin":"profile","expiresAtMs":90000}',
      );
      expect(container.read(matchRequestsProvider).incoming, isNotNull);

      // Uygulama arka plana geçiyor
      await coordinator.disconnectDueToBackground();

      // Bekleyen istek temizlenmiş olmalı
      expect(container.read(matchRequestsProvider).incoming, isNull);
      expect(client.isConnected, isFalse);
      expect(fakeConnection.closeCode, 1000);
      expect(fakeConnection.closeReason, 'app_backgrounded');
    });

    test('Ön plana dönüldüğünde (resumed) soket yeniden bağlanır', () async {
      final coordinator = container.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      // Arka plana geç
      await coordinator.disconnectDueToBackground();
      final client = container.read(userInboxClientProvider);
      expect(client.isConnected, isFalse);

      // Ön plana geçiş için yeni bağlantı hazırla
      final nextConnection = FakeWebSocketConnection();
      fakeConnector.connectionToReturn = nextConnection;

      await coordinator.evaluateConnection();

      expect(client.isConnected, isTrue);
    });

    test('onSignOut çağrıldığında presence sıfırlanır, istekler temizlenir ve soket kapatılır', () async {
      final coordinator = container.read(userInboxLifecycleCoordinatorProvider);
      await coordinator.evaluateConnection();

      final client = container.read(userInboxClientProvider);
      final presence = container.read(presenceControllerProvider.notifier);

      presence.acquireBusy('some_screen');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(presenceControllerProvider), UserPresenceState.busy);

      await coordinator.onSignOut();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(presenceControllerProvider), UserPresenceState.idle);
      expect(presence.activeTokens, isEmpty);
      expect(container.read(matchRequestsProvider).incoming, isNull);
      expect(client.isConnected, isFalse);
      expect(fakeConnection.closeCode, 1000);
      expect(fakeConnection.closeReason, 'sign_out');
    });
  });
}
