import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

void main() {
  group('OnlineMatchClient Rematch Tests', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    test('offerRematch, acceptRematch, declineRematch, leaveRematch send correct JSON', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      await client.connect('m_123');

      // 1. offerRematch
      final offerOk = client.offerRematch();
      expect(offerOk, isTrue);
      expect(fakeConnection.sentMessages.length, 1);
      final offerMap = jsonDecode(fakeConnection.sentMessages.last) as Map<String, dynamic>;
      expect(offerMap['t'], 'rematch_offer');

      // 2. acceptRematch
      final acceptOk = client.acceptRematch();
      expect(acceptOk, isTrue);
      expect(fakeConnection.sentMessages.length, 2);
      final acceptMap = jsonDecode(fakeConnection.sentMessages.last) as Map<String, dynamic>;
      expect(acceptMap['t'], 'rematch_accept');

      // 3. declineRematch
      final declineOk = client.declineRematch();
      expect(declineOk, isTrue);
      expect(fakeConnection.sentMessages.length, 3);
      final declineMap = jsonDecode(fakeConnection.sentMessages.last) as Map<String, dynamic>;
      expect(declineMap['t'], 'rematch_decline');

      // 4. leaveRematch
      final leaveOk = client.leaveRematch();
      expect(leaveOk, isTrue);
      expect(fakeConnection.sentMessages.length, 4);
      final leaveMap = jsonDecode(fakeConnection.sentMessages.last) as Map<String, dynamic>;
      expect(leaveMap['t'], 'rematch_leave');

      await client.dispose();
    });

    test('calling rematch methods when disconnected returns false', () {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      expect(client.offerRematch(), isFalse);
      expect(client.acceptRematch(), isFalse);
      expect(client.declineRematch(), isFalse);
      expect(client.leaveRematch(), isFalse);
    });

    test('incoming rematch server messages dispatch corresponding events', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');
      expect(events.length, 1);
      expect(events[0], isA<OnlineMatchConnected>());

      // 1. rematch_offered
      fakeConnection.emitIncoming('{"t":"rematch_offered","byUid":"u_opponent","expiresAtMs":1760000045000}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 2);
      expect(events[1], isA<OnlineMatchRematchOffered>());
      final offered = events[1] as OnlineMatchRematchOffered;
      expect(offered.message.byUid, 'u_opponent');
      expect(offered.message.expiresAtMs, 1760000045000);

      // 2. rematch_status
      fakeConnection.emitIncoming('{"t":"rematch_status","status":"declined"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 3);
      expect(events[2], isA<OnlineMatchRematchStatus>());
      final statusEv = events[2] as OnlineMatchRematchStatus;
      expect(statusEv.message.status, RematchStatusType.declined);

      // 3. rematch_error
      fakeConnection.emitIncoming('{"t":"rematch_error","code":"no_energy"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 4);
      expect(events[3], isA<OnlineMatchRematchError>());
      final errEv = events[3] as OnlineMatchRematchError;
      expect(errEv.message.code, RematchErrorCode.noEnergy);

      // 4. matched (new match from rematch)
      fakeConnection.emitIncoming('{"t":"matched","matchId":"m_new456","opponentName":"Ali","opponentFrame":"mint","opponentUid":"u_opponent","isFriendly":false}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 5);
      expect(events[4], isA<OnlineMatchMatched>());
      final matchedEv = events[4] as OnlineMatchMatched;
      expect(matchedEv.message.matchId, 'm_new456');
      expect(matchedEv.message.opponentName, 'Ali');
      expect(matchedEv.message.isFriendly, isFalse);

      await sub.cancel();
      await client.dispose();
    });

    test('socket close with 1000 / rematch_started maps to rematchStarted and does NOT reconnect', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 5)],
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      // Server closes socket with 1000 and "rematch_started" after rematch accept
      fakeConnection.simulateServerClose(1000, 'rematch_started');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        events.any((e) =>
            e is OnlineMatchDisconnected &&
            e.reason == DisconnectReason.rematchStarted &&
            e.closeCode == 1000 &&
            e.closeReason == 'rematch_started'),
        isTrue,
      );

      // No reconnect attempt should happen
      expect(events.whereType<OnlineMatchConnected>().length, 1);

      await sub.cancel();
      await client.dispose();
    });
  });
}
