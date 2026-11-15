import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/data/user_inbox_client.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchRequestsNotifier', () {
    late ProviderContainer container;
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;
    late UserInboxClient client;

    final notifierProvider =
        NotifierProvider<MatchRequestsNotifier, MatchRequestsState>(
      MatchRequestsNotifier.new,
    );

    setUp(() async {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');

      container = ProviderContainer();

      client = UserInboxClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        getCurrentPresenceState: () => 'idle',
      );

      container.read(notifierProvider.notifier).attachClient(client);
    });

    tearDown(() async {
      await client.close();
      container.dispose();
    });

    test('Bağlantı durumları akışı yansıtılır', () async {
      var state = container.read(notifierProvider);
      expect(state.connectionState, UserInboxConnectionState.disconnected);

      await client.connect();

      state = container.read(notifierProvider);
      expect(state.connectionState, UserInboxConnectionState.connected);

      await client.close();
      state = container.read(notifierProvider);
      expect(state.connectionState, UserInboxConnectionState.disconnected);
    });

    test('sendRequest: bağlantı yokken çağrılırsa hata kaydeder ve false döner', () async {
      final notifier = container.read(notifierProvider.notifier);

      final result = await notifier.sendRequest(
        origin: MatchRequestOrigin.profile,
        toUid: 'u_target',
      );

      expect(result, isFalse);
      final state = container.read(notifierProvider);
      expect(state.lastError?.code, MatchRequestErrorCode.unavailable);
    });

    test('sendRequest: bağlıyken başarıyla gönderir ve sokete mesaj iletilir', () async {
      await client.connect();
      fakeConnection.sentMessages.clear();

      final notifier = container.read(notifierProvider.notifier);

      final result = await notifier.sendRequest(
        origin: MatchRequestOrigin.profile,
        toUid: 'u_alice',
      );

      expect(result, isTrue);
      expect(fakeConnection.sentMessages.length, 1);
      expect(
        fakeConnection.sentMessages.first,
        '{"t":"send_match_request","origin":"profile","toUid":"u_alice"}',
      );
    });

    test('sendRequest: zaten giden bir istek varken ikinci istek engellenir', () async {
      await client.connect();
      final notifier = container.read(notifierProvider.notifier);

      // Simüle edilen giden istek bildirimi al
      fakeConnection.emitIncoming(
        '{"t":"match_request_sent","id":"req_1","toUid":"u_alice","toNickname":"Alice","type":"friendly","origin":"profile","expiresAtMs":90000}',
      );

      expect(container.read(notifierProvider).outgoing, isNotNull);

      // İkinci istek denemesi yerelde engellenir ve sokete gitmez
      fakeConnection.sentMessages.clear();
      final result = await notifier.sendRequest(
        origin: MatchRequestOrigin.rematch,
        toUid: 'u_bob',
        matchId: 'm_123',
      );

      expect(result, isFalse);
      expect(fakeConnection.sentMessages, isEmpty);
      expect(container.read(notifierProvider).lastError?.code, MatchRequestErrorCode.unavailable);
    });

    test('sendRequest: geçersiz parametrelerde ArgumentError fırlatır', () async {
      await client.connect();
      final notifier = container.read(notifierProvider.notifier);

      // toUid boş
      expect(
        () => notifier.sendRequest(
          origin: MatchRequestOrigin.profile,
          toUid: '',
        ),
        throwsArgumentError,
      );

      // origin=rematch fakat matchId yok
      expect(
        () => notifier.sendRequest(
          origin: MatchRequestOrigin.rematch,
          toUid: 'u_alice',
        ),
        throwsArgumentError,
      );

      // origin=rematch fakat matchId boş
      expect(
        () => notifier.sendRequest(
          origin: MatchRequestOrigin.rematch,
          toUid: 'u_alice',
          matchId: '  ',
        ),
        throwsArgumentError,
      );

      // origin=profile fakat matchId verilmiş
      expect(
        () => notifier.sendRequest(
          origin: MatchRequestOrigin.profile,
          toUid: 'u_alice',
          matchId: 'm_should_not_exist',
        ),
        throwsArgumentError,
      );
    });

    test('accept, decline, cancel mesajları sokete iletilir', () async {
      await client.connect();
      fakeConnection.sentMessages.clear();

      final notifier = container.read(notifierProvider.notifier);

      await notifier.accept('req_in_1');
      expect(fakeConnection.sentMessages.last, '{"t":"accept_match_request","id":"req_in_1"}');

      await notifier.decline('req_in_2');
      expect(fakeConnection.sentMessages.last, '{"t":"decline_match_request","id":"req_in_2"}');

      await notifier.cancel('req_out_1');
      expect(fakeConnection.sentMessages.last, '{"t":"cancel_match_request","id":"req_out_1"}');
    });

    test('matched mesajı geldiğinde matchedEvents akışına yayılır ve istekler temizlenir', () async {
      await client.connect();

      final notifier = container.read(notifierProvider.notifier);
      final events = <MatchedEvent>[];
      final sub = notifier.matchedEvents.listen(events.add);

      // Bekleyen istekler olsun
      fakeConnection.emitIncoming(
        '{"t":"match_request_received","id":"req_in_3","fromUid":"u_charlie","fromNickname":"Charlie","fromFrame":"f1","type":"ranked","origin":"rematch","expiresAtMs":90000}',
      );
      expect(container.read(notifierProvider).incoming, isNotNull);

      // Eşleşme bildirimi gelince
      fakeConnection.emitIncoming(
        '{"t":"matched","matchId":"m_match_456","opponentName":"Charlie","opponentFrame":"f1","opponentUid":"u_charlie","isFriendly":false}',
      );

      expect(events.length, 1);
      final event = events.first;
      expect(event.matchId, 'm_match_456');
      expect(event.opponentName, 'Charlie');
      expect(event.isFriendly, isFalse);

      // İstekler temizlenmiş olmalı
      final state = container.read(notifierProvider);
      expect(state.incoming, isNull);
      expect(state.outgoing, isNull);

      await sub.cancel();
    });

    test('clearLocalRequests hem incoming hem outgoing temizler', () async {
      await client.connect();

      fakeConnection.emitIncoming(
        '{"t":"match_request_received","id":"req_in","fromUid":"u_1","fromNickname":"One","fromFrame":"f1","type":"friendly","origin":"profile","expiresAtMs":90000}',
      );
      fakeConnection.emitIncoming(
        '{"t":"match_request_sent","id":"req_out","toUid":"u_2","toNickname":"Two","type":"friendly","origin":"profile","expiresAtMs":90000}',
      );

      var state = container.read(notifierProvider);
      expect(state.incoming, isNotNull);
      expect(state.outgoing, isNotNull);

      container.read(notifierProvider.notifier).clearLocalRequests();

      state = container.read(notifierProvider);
      expect(state.incoming, isNull);
      expect(state.outgoing, isNull);
    });
  });
}
