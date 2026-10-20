import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/friend_match/data/friend_match_client.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/websocket_connector.dart';

class FakeWebSocketConnection implements WebSocketConnection {
  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  final List<String> sentMessages = [];
  bool isClosed = false;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  void send(String data) {
    sentMessages.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    await _streamController.close();
  }

  @override
  int? get closeCode => isClosed ? 1000 : null;

  @override
  String? get closeReason => isClosed ? 'closed' : null;

  void emitFromServer(dynamic data) {
    _streamController.add(data);
  }
}

class FakeWebSocketConnector implements WebSocketConnector {
  FakeWebSocketConnection? lastConnection;
  String? lastUrl;

  @override
  Future<WebSocketConnection> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? timeout,
  }) async {
    lastUrl = url;
    final conn = FakeWebSocketConnection();
    lastConnection = conn;
    return conn;
  }
}

class FakeAuthTokenProvider implements AuthTokenProvider {
  final String? token;
  FakeAuthTokenProvider({this.token = 'mock_token'});

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => token;
}

void main() {
  group('FriendMatchClient Tests', () {
    late FakeWebSocketConnector connector;
    late FakeAuthTokenProvider tokenProvider;
    late FriendMatchClient client;

    setUp(() {
      connector = FakeWebSocketConnector();
      tokenProvider = FakeAuthTokenProvider();
      client = FriendMatchClient(
        connector: connector,
        tokenProvider: tokenProvider,
        serverWsUrl: 'wss://test.server.com',
      );
    });

    tearDown(() async {
      await client.close();
    });

    test('1. createRoom doğru JSON mesajı gönderir ve room_created olayını yayar',
        () async {
      final events = <FriendMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.createRoom(name: 'Ali');

      expect(connector.lastConnection, isNotNull);
      final sent = connector.lastConnection!.sentMessages;
      expect(sent.length, 1);
      final sentJson = jsonDecode(sent.first);
      expect(sentJson['t'], 'create_room');
      expect(sentJson['name'], 'Ali');

      // Sunucudan room_created gelir
      final expiresAt = DateTime.now().millisecondsSinceEpoch + 300000;
      connector.lastConnection!.emitFromServer(
        jsonEncode({
          't': 'room_created',
          'code': 'K7M9P2',
          'expiresAt': expiresAt,
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final createdEvent = events.whereType<FriendMatchRoomCreated>().firstOrNull;
      expect(createdEvent, isNotNull);
      expect(createdEvent!.code, 'K7M9P2');
      expect(createdEvent.expiresAt, expiresAt);

      await sub.cancel();
    });

    test('2. resumeRoom doğru JSON mesajı gönderir ve room_resumed olayını yayar',
        () async {
      final events = <FriendMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.resumeRoom('K7M9P2');

      final sentJson = jsonDecode(connector.lastConnection!.sentMessages.first);
      expect(sentJson['t'], 'resume_room');
      expect(sentJson['code'], 'K7M9P2');

      connector.lastConnection!.emitFromServer(
        jsonEncode({
          't': 'room_resumed',
          'code': 'K7M9P2',
          'expiresAt': 12345678,
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final resumedEvent = events.whereType<FriendMatchRoomResumed>().firstOrNull;
      expect(resumedEvent, isNotNull);
      expect(resumedEvent!.code, 'K7M9P2');

      await sub.cancel();
    });

    test('3. joinRoom doğru JSON mesajı gönderir ve matched olayını yayar',
        () async {
      final events = <FriendMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.joinRoom('B3D5G7', name: 'Zeynep');

      final sentJson = jsonDecode(connector.lastConnection!.sentMessages.first);
      expect(sentJson['t'], 'join_room');
      expect(sentJson['code'], 'B3D5G7');
      expect(sentJson['name'], 'Zeynep');

      connector.lastConnection!.emitFromServer(
        jsonEncode({
          't': 'matched',
          'matchId': 'match_friend_1',
          'opponentName': 'Ali',
          'isFriendly': true,
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final matchedEvent = events.whereType<FriendMatchMatched>().firstOrNull;
      expect(matchedEvent, isNotNull);
      expect(matchedEvent!.matchId, 'match_friend_1');
      expect(matchedEvent.opponentName, 'Ali');

      await sub.cancel();
    });

    test('4. Hata mesajında FriendMatchFailed olayı kod ve mesajla yayılır',
        () async {
      final events = <FriendMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.joinRoom('B3D5G7');

      connector.lastConnection!.emitFromServer(
        jsonEncode({
          't': 'error',
          'code': 'room_not_found',
          'message': 'Bu oda bulunamadı veya süresi dolmuş.',
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final failedEvent = events.whereType<FriendMatchFailed>().firstOrNull;
      expect(failedEvent, isNotNull);
      expect(failedEvent!.code, 'room_not_found');
      expect(failedEvent.message, 'Bu oda bulunamadı veya süresi dolmuş.');

      await sub.cancel();
    });
  });
}

