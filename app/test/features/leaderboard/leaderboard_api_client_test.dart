import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';

class FakeHttpClient implements HttpClient {
  final int statusCode;
  final String responseBody;
  final bool shouldThrow;

  FakeHttpClient({
    this.statusCode = 200,
    this.responseBody = '{}',
    this.shouldThrow = false,
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Network unreachable');
    return FakeHttpClientRequest(statusCode: statusCode, responseBody: responseBody);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final String responseBody;

  FakeHttpClientRequest({required this.statusCode, required this.responseBody});

  @override
  final HttpHeaders headers = FakeHttpHeaders();

  @override
  int contentLength = 0;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    return FakeHttpClientResponse(statusCode: statusCode, body: responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, Object> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  FakeHttpClientResponse({required this.statusCode, required this.body});

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HttpLeaderboardApiClient', () {
    test('1. 200 OK yanıtında LeaderboardData başarıyla ayrıştırılır', () async {
      const responsePayload = '''
      {
        "weekKey": "2026-W42",
        "endsAt": 1792357200000,
        "top": [
          {"rank": 1, "nickname": "Ahmet", "wins": 10, "isMe": false},
          {"rank": 2, "nickname": "Mehmet", "wins": 8, "isMe": true}
        ],
        "me": {
          "rank": 2,
          "wins": 8
        }
      }
      ''';

      final client = HttpLeaderboardApiClient(
        authTokenProvider: FakeAuthTokenProvider(token: 'valid_token'),
        clientFactory: () => FakeHttpClient(
          statusCode: 200,
          responseBody: responsePayload,
        ),
      );

      final data = await client.fetchLeaderboard();
      expect(data.weekKey, '2026-W42');
      expect(data.endsAt, 1792357200000);
      expect(data.top.length, 2);
      expect(data.top[0].rank, 1);
      expect(data.top[0].nickname, 'Ahmet');
      expect(data.top[0].wins, 10);
      expect(data.top[0].isMe, false);

      expect(data.top[1].rank, 2);
      expect(data.top[1].nickname, 'Mehmet');
      expect(data.top[1].wins, 8);
      expect(data.top[1].isMe, true);

      expect(data.me, isNotNull);
      expect(data.me!.rank, 2);
      expect(data.me!.wins, 8);
    });

    test('2. 401 veya 500 yanıtında HttpException fırlatır', () async {
      final client = HttpLeaderboardApiClient(
        authTokenProvider: FakeAuthTokenProvider(token: 'valid_token'),
        clientFactory: () => FakeHttpClient(
          statusCode: 401,
          responseBody: '{"error": "unauthorized"}',
        ),
      );

      expect(() => client.fetchLeaderboard(), throwsA(isA<HttpException>()));
    });

    test('3. Ağ hatasında SocketException fırlatır', () async {
      final client = HttpLeaderboardApiClient(
        authTokenProvider: FakeAuthTokenProvider(token: 'valid_token'),
        clientFactory: () => FakeHttpClient(shouldThrow: true),
      );

      expect(() => client.fetchLeaderboard(), throwsA(isA<SocketException>()));
    });

    test('4. Token alınamadığında SocketException fırlatır', () async {
      final client = HttpLeaderboardApiClient(
        authTokenProvider: FakeAuthTokenProvider(token: null),
      );

      expect(() => client.fetchLeaderboard(), throwsA(isA<SocketException>()));
    });
  });

  group('LeaderboardData.formatRemainingTime', () {
    test('Kalan süre gün ve saat formatı', () {
      final now = DateTime(2026, 10, 14, 12, 0);
      final endsAt = now.add(const Duration(days: 4, hours: 8)).millisecondsSinceEpoch;

      final data = LeaderboardData(
        weekKey: '2026-W42',
        endsAt: endsAt,
        top: const [],
      );

      expect(data.formatRemainingTime(now), '4g 8s');
    });

    test('Kalan süre saat ve dakika formatı', () {
      final now = DateTime(2026, 10, 18, 20, 0);
      final endsAt = now.add(const Duration(hours: 3, minutes: 45)).millisecondsSinceEpoch;

      final data = LeaderboardData(
        weekKey: '2026-W42',
        endsAt: endsAt,
        top: const [],
      );

      expect(data.formatRemainingTime(now), '3s 45d');
    });

    test('Kalan süre sadece dakika formatı', () {
      final now = DateTime(2026, 10, 18, 23, 40);
      final endsAt = now.add(const Duration(minutes: 19)).millisecondsSinceEpoch;

      final data = LeaderboardData(
        weekKey: '2026-W42',
        endsAt: endsAt,
        top: const [],
      );

      expect(data.formatRemainingTime(now), '19d');
    });

    test('Kalan süre geçmişse süre doldu yazar', () {
      final now = DateTime(2026, 10, 19, 0, 1);
      final endsAt = now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;

      final data = LeaderboardData(
        weekKey: '2026-W42',
        endsAt: endsAt,
        top: const [],
      );

      expect(data.formatRemainingTime(now), 'Süre doldu');
    });
  });
}

