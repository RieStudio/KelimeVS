import 'package:app/features/match_request/application/presence_controller.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresenceController', () {
    late ProviderContainer container;
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;
    late UserInboxClient client;

    setUp(() async {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');

      container = ProviderContainer();

      client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () =>
            container.read(presenceControllerProvider).toWireString(),
      );

      await client.connect();
      container.read(presenceControllerProvider.notifier).attachClient(client);
      fakeConnection.sentMessages.clear(); // connect ve attach anındaki ilk presence mesajlarını temizle
    });

    tearDown(() async {
      await client.close();
      container.dispose();
    });

    test('Başlangıç durumu idle ve activeTokens boştur', () {
      final state = container.read(presenceControllerProvider);
      final controller = container.read(presenceControllerProvider.notifier);

      expect(state, UserPresenceState.idle);
      expect(controller.activeTokens, isEmpty);
    });

    test('acquireBusy meşgul duruma geçirir ve sokete presence:busy gönderir', () async {
      final controller = container.read(presenceControllerProvider.notifier);

      controller.acquireBusy('matchmaking');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(presenceControllerProvider), UserPresenceState.busy);
      expect(controller.activeTokens, contains('matchmaking'));

      expect(fakeConnection.sentMessages.length, 1);
      expect(
        fakeConnection.sentMessages.first,
        '{"t":"presence","state":"busy"}',
      );
    });

    test('Mükerrer acquireBusy çağrıları durumu meşgul tutar ama mükerrer soket mesajı göndermez', () async {
      final controller = container.read(presenceControllerProvider.notifier);

      controller.acquireBusy('matchmaking');
      await Future<void>.delayed(Duration.zero);
      expect(fakeConnection.sentMessages.length, 1);

      // İkinci bir ekran meşguliyet bildiriyor
      controller.acquireBusy('friend_host');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(presenceControllerProvider), UserPresenceState.busy);
      expect(controller.activeTokens, containsAll(['matchmaking', 'friend_host']));

      // Dedup: Sokete yeni mesaj gitmemeli, toplam mesaj 1 kalmalı
      expect(fakeConnection.sentMessages.length, 1);
    });

    test('releaseBusy referans sayacını azaltır, son meşguliyet kalkınca idle olur', () async {
      final controller = container.read(presenceControllerProvider.notifier);

      controller.acquireBusy('screen_a');
      controller.acquireBusy('screen_b');
      await Future<void>.delayed(Duration.zero);
      expect(fakeConnection.sentMessages.length, 1); // 1 kez busy

      // screen_a bitti, screen_b hala meşgul
      controller.releaseBusy('screen_a');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(presenceControllerProvider), UserPresenceState.busy);
      expect(controller.activeTokens, contains('screen_b'));
      expect(fakeConnection.sentMessages.length, 1); // hala idle olmadı, ek mesaj yok

      // screen_b de bitti -> artık idle olmalı
      controller.releaseBusy('screen_b');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(presenceControllerProvider), UserPresenceState.idle);
      expect(controller.activeTokens, isEmpty);

      expect(fakeConnection.sentMessages.length, 2);
      expect(
        fakeConnection.sentMessages.last,
        '{"t":"presence","state":"idle"}',
      );
    });

    test('Aynı belirtecin mükerrer releaseBusy çağrılması sayacı eksiye düşürmez', () async {
      final controller = container.read(presenceControllerProvider.notifier);

      controller.acquireBusy('screen_x');
      await Future<void>.delayed(Duration.zero);
      controller.releaseBusy('screen_x');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(presenceControllerProvider), UserPresenceState.idle);

      // Tekrar release et
      controller.releaseBusy('screen_x');
      controller.releaseBusy('non_existent');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(presenceControllerProvider), UserPresenceState.idle);
      expect(controller.activeTokens, isEmpty);
    });

    test('forceReset güvenlik ağı: tüm sayaçları sıfırlar ve zorla idle yapar', () async {
      final controller = container.read(presenceControllerProvider.notifier);

      controller.acquireBusy('screen_1');
      controller.acquireBusy('screen_2');
      controller.acquireBusy('screen_3');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(presenceControllerProvider), UserPresenceState.busy);
      expect(controller.activeTokens.length, 3);

      // Güvenlik ağı tetiklenir
      controller.forceReset();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(presenceControllerProvider), UserPresenceState.idle);
      expect(controller.activeTokens, isEmpty);
      expect(
        fakeConnection.sentMessages.last,
        '{"t":"presence","state":"idle"}',
      );
    });
  });
}
