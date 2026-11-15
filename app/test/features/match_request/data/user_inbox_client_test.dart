import 'package:app/features/match_request/data/match_request_messages.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserInboxClient', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;
    String currentPresence = 'idle';

    setUp(() {
      currentPresence = 'idle';
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    test('Bağlantı kurulduğunda derhal güncel presence mesajı gönderir', () async {
      currentPresence = 'busy';
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        serverWsUrl: 'https://test.server',
        getCurrentPresenceState: () => currentPresence,
      );

      await client.connect();

      expect(client.isConnected, isTrue);
      expect(fakeConnection.sentMessages.length, 1);
      expect(
        fakeConnection.sentMessages.first,
        '{"t":"presence","state":"busy"}',
      );

      await client.close();
    });

    test('İstemci mesajı gönderme (send) ve gelen sunucu mesajlarını ayrıştırma', () async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => currentPresence,
      );

      final receivedMessages = <UserInboxServerMessage>[];
      final sub = client.messages.listen(receivedMessages.add);

      await client.connect();

      // İstemci mesajı gönder
      client.send(UserInboxSendRequestMessage(
        toUid: 'u_target',
        origin: MatchRequestOrigin.rematch,
        matchId: 'm_123',
      ));

      expect(fakeConnection.sentMessages.length, 2); // 1. presence, 2. send_request
      expect(
        fakeConnection.sentMessages[1],
        '{"t":"send_match_request","origin":"rematch","toUid":"u_target","matchId":"m_123"}',
      );

      // Sunucudan mesaj simüle et
      fakeConnection.emitIncoming(
        '{"t":"match_request_received","id":"req_abc","fromUid":"u_1","fromNickname":"Alice","fromFrame":"f1","type":"ranked","origin":"rematch","expiresAtMs":99000}',
      );

      expect(receivedMessages.length, 1);
      final msg = receivedMessages.first;
      expect(msg, isA<UserInboxRequestReceivedMessage>());
      final received = msg as UserInboxRequestReceivedMessage;
      expect(received.id, 'req_abc');
      expect(received.fromUid, 'u_1');
      expect(received.fromNickname, 'Alice');
      expect(received.type, MatchRequestType.ranked);

      await sub.cancel();
      await client.close();
    });

    test('Toleranslı ayrıştırma: bozuk JSON veya bilinmeyen t bağlantıyı koparmaz', () async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => currentPresence,
      );

      final receivedMessages = <UserInboxServerMessage>[];
      final sub = client.messages.listen(receivedMessages.add);

      await client.connect();

      // Bozuk JSON ve bilinmeyen t
      fakeConnection.emitIncoming('NOT_VALID_JSON{{{');
      fakeConnection.emitIncoming('{"t":"unknown_event_type"}');

      // Geçerli bir durum mesajı gönderelim (pong dahili tüketilir, messages akışına verilmez)
      fakeConnection.emitIncoming(
        '{"t":"match_request_status","id":"req_xyz","status":"declined"}',
      );

      expect(client.isConnected, isTrue);
      expect(receivedMessages.length, 1);
      expect(receivedMessages.first, isA<UserInboxRequestStatusMessage>());

      await sub.cancel();
      await client.close();
    });

    test('Heartbeat: pingInterval dolunca ping gönderir, pong watchdog çalışır', () async {
      fakeConnection.onSend = (msg) {
        if (msg == '{"t":"ping"}') {
          fakeConnection.emitIncoming('{"t":"pong"}');
        }
      };

      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        pingInterval: const Duration(milliseconds: 30),
        pongTimeout: const Duration(milliseconds: 25),
        getCurrentPresenceState: () => currentPresence,
      );

      await client.connect();
      expect(fakeConnection.sentMessages.length, 1); // presence

      // 40ms sonra ping gönderilmiş olmalı
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(
        fakeConnection.sentMessages.any((m) => m == '{"t":"ping"}'),
        isTrue,
      );

      // Pong otomatik yanıtlandığı için bağlantı açık kalır
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(client.isConnected, isTrue);

      await client.close();
    });

    test('Pong zaman aşımında bağlantı ölü kabul edilir ve yeniden bağlanma tetiklenir', () async {
      final nextConnection = FakeWebSocketConnection();
      nextConnection.onSend = (msg) {
        if (msg == '{"t":"ping"}') {
          nextConnection.emitIncoming('{"t":"pong"}');
        }
      };

      final connectionStates = <bool>[];

      // Üretimde pingInterval 25s, pongTimeout 10s (yani pongTimeout < pingInterval).
      // Testte de bu oranı koruyarak pingInterval: 40ms, pongTimeout: 15ms kullanıyoruz.
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        pingInterval: const Duration(milliseconds: 40),
        pongTimeout: const Duration(milliseconds: 15),
        customReconnectDelays: [const Duration(milliseconds: 5)],
        getCurrentPresenceState: () => currentPresence,
      );

      client.connectionStatus.listen(connectionStates.add);

      await client.connect();
      expect(client.isConnected, isTrue);

      // Bir sonraki connect çağrısı için yeni sahte bağlantı hazırla
      fakeConnector.connectionToReturn = nextConnection;

      // Pong dönmeyeceğiz. İlk bağlantıda 40ms ping + 15ms pong timeout = 55ms sonra
      // watchdog devreye girer ve kopmayı tetikler.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (client.isConnected && connectionStates.contains(false)) {
          break;
        }
      }

      // Bağlantı kopup (false) ardından tekrar kurulmuş (true) olmalı
      expect(connectionStates, contains(false));
      expect(client.isConnected, isTrue);
      expect(nextConnection.sentMessages.isNotEmpty, isTrue);

      await client.close();
    });

    test('Sunucu 4001 (account deleted) ile kapattığında yeniden bağlanmaz ve onAccountDeleted çağrılır', () async {
      bool accountDeletedCalled = false;
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        customReconnectDelays: [const Duration(milliseconds: 10)],
        onAccountDeleted: () {
          accountDeletedCalled = true;
        },
        getCurrentPresenceState: () => currentPresence,
      );

      await client.connect();
      expect(client.isConnected, isTrue);

      // Sunucu 4001 ile kapatsın
      fakeConnection.simulateServerClose(4001, 'account_deleted');

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(accountDeletedCalled, isTrue);
      expect(client.isConnected, isFalse);
      expect(client.isClosed, isTrue);
      expect(client.isReconnecting, isFalse);
    });

    test('Handshake esnasında HTTP 410 hatası gelirse yeniden bağlanmaz ve onAccountDeleted çağrılır', () async {
      bool accountDeletedCalled = false;
      fakeConnector.errorToThrow = Exception('HTTP status code 410');

      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        customReconnectDelays: [const Duration(milliseconds: 10)],
        onAccountDeleted: () {
          accountDeletedCalled = true;
        },
        getCurrentPresenceState: () => currentPresence,
      );

      await client.connect();

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(accountDeletedCalled, isTrue);
      expect(client.isConnected, isFalse);
      expect(client.isClosed, isTrue);
    });

    test('İstemci tarafından close() çağrıldığında temiz kapatılır ve yeniden bağlanmaz', () async {
      final client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        customReconnectDelays: [const Duration(milliseconds: 10)],
        getCurrentPresenceState: () => currentPresence,
      );

      await client.connect();
      expect(client.isConnected, isTrue);

      await client.close();

      expect(client.isConnected, isFalse);
      expect(client.isClosed, isTrue);

      // Bekleme süresince yeniden bağlanma girişimi olmamalı
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(client.isConnected, isFalse);
      expect(client.isReconnecting, isFalse);
    });
  });
}
