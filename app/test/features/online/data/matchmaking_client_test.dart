import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/matchmaking_client.dart';
import 'package:app/features/online/data/websocket_connector.dart';

void main() {
  group('MatchmakingClient', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    test('kuyruğa girme ve matched akışı başarıyla gerçekleşir', () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('Ahmet');

      expect(events.length, 1);
      expect(events[0], isA<MatchmakingConnecting>());
      expect(fakeConnection.sentMessages.length, 1);
      expect(fakeConnection.sentMessages[0], contains('"queue"'));
      expect(fakeConnection.sentMessages[0], contains('Ahmet'));
      expect(fakeConnection.sentMessages[0], contains('"supportsSoloTicket":true'));

      // Sunucu "queued" yanıtı döner
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 2);
      expect(events[1], isA<MatchmakingQueued>());

      // Sunucu "matched" yanıtı döner
      fakeConnection.emitIncoming(
        '{"t":"matched","matchId":"m_test123","opponentName":"Mehmet"}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 3);
      final matched = events[2] as MatchmakingMatched;
      expect(matched.matchId, 'm_test123');
      expect(matched.opponentName, 'Mehmet');

      await sub.cancel();
      await client.dispose();
    });

    test('sunucudan no_opponent bilet ile gelince MatchmakingNoOpponent yayılır',
        () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('TestUser');
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      fakeConnection.emitIncoming(
        '{"t":"no_opponent","ticketId":"ticket_abc","matchId":"bot:12345678","issuedAt":1700000000,"energy":{"current":4,"max":5}}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 3);
      final noOpp = events[2] as MatchmakingNoOpponent;
      expect(noOpp.ticketId, 'ticket_abc');
      expect(noOpp.matchId, 'bot:12345678');
      expect(noOpp.issuedAt, 1700000000);
      expect(noOpp.energy?.current, 4);
      expect(noOpp.energy?.max, 5);
      expect(fakeConnection.isClosed, isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('sunucudan no_opponent error:no_energy gelince MatchmakingNoEnergy yayılır',
        () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('TestUser');
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      fakeConnection.emitIncoming('{"t":"no_opponent","error":"no_energy"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 3);
      expect(events[2], isA<MatchmakingNoEnergy>());
      expect(fakeConnection.isClosed, isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('15 sn sunucu zaman aşımı durumunda cancel gönderilir ve server_timeout hatası yayılır',
        () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        serverTimeoutDuration: const Duration(milliseconds: 30),
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('TestUser');
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e is MatchmakingQueued), isTrue);

      // 30 ms'lik zaman aşımı süresinin dolmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        events.any(
          (e) => e is MatchmakingFailed && e.reason == 'server_timeout',
        ),
        isTrue,
      );
      expect(fakeConnection.sentMessages.any((msg) => msg.contains('"cancel"')), isTrue);
      expect(fakeConnection.isClosed, isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('bağlantı hatası durumunda unavailable yayılır', () async {
      fakeConnector = FakeWebSocketConnector(
        errorToThrow: Exception('Ağ bağlantısı kurulamadı'),
      );

      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('Test');
      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e is MatchmakingUnavailable), isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('sunucu content_unavailable hatası gönderdiğinde unavailable yayılır',
        () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('Test');
      fakeConnection.emitIncoming('{"t":"error","code":"content_unavailable"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e is MatchmakingUnavailable), isTrue);
      final unavail = events.firstWhere((e) => e is MatchmakingUnavailable)
          as MatchmakingUnavailable;
      expect(unavail.reason, 'content_unavailable');

      await sub.cancel();
      await client.dispose();
    });

    test('kullanıcı cancel çağırdığında zamanlayıcılar ve bağlantı kapanır', () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        matchWindowDuration: const Duration(seconds: 10),
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('Test');
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      await client.cancel();

      expect(events.any((e) => e is MatchmakingCancelled), isTrue);
      expect(fakeConnection.sentMessages.any((msg) => msg.contains('"cancel"')), isTrue);
      expect(fakeConnection.isClosed, isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('aynı istemci iki kez start edilirse StateError fırlatır', () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      await client.start('Test');
      expect(() => client.start('Test'), throwsStateError);

      await client.dispose();
    });
  });
}
