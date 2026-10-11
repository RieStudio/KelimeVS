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

    test('10 sn eşleşme penceresinde rakip bulunamazsa cancel gönderilir ve noOpponent yayılır',
        () async {
      final client = MatchmakingClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        matchWindowDuration: const Duration(milliseconds: 30),
      );

      final events = <MatchmakingEvent>[];
      final sub = client.events.listen(events.add);

      await client.start('TestUser');
      fakeConnection.emitIncoming('{"t":"queued"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.any((e) => e is MatchmakingQueued), isTrue);

      // 30 ms'lik pencerenin dolmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.any((e) => e is MatchmakingNoOpponent), isTrue);
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
