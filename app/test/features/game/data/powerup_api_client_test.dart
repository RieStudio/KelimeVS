import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:app/features/game/data/powerup_api_client.dart';
import 'package:app/features/online/data/auth_token_provider.dart';

class MockAuthTokenProvider implements AuthTokenProvider {
  final String? token;
  const MockAuthTokenProvider([this.token = 'mock-jwt-token']);

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => token;
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
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
    return Stream.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) => _map[name.toLowerCase()]?.first;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  final HttpHeaders _headers = _MockHttpHeaders();
  final List<List<int>> _body = [];
  final Future<HttpClientResponse> Function() onClose;

  FakeHttpClientRequest({
    required this.onClose,
  });

  @override
  HttpHeaders get headers => _headers;

  @override
  int contentLength = 0;

  @override
  void add(List<int> data) {
    _body.add(data);
  }

  String get bodyAsString => utf8.decode(_body.expand((x) => x).toList());

  @override
  Future<HttpClientResponse> close() => onClose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  final Future<HttpClientRequest> Function(Uri uri)? onPostUrl;
  final int statusCode;
  final String responseBody;
  FakeHttpClientRequest? lastRequest;

  FakeHttpClient({
    this.statusCode = 200,
    this.responseBody = '{}',
    this.onPostUrl,
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (onPostUrl != null) {
      return onPostUrl!(url);
    }
    lastRequest = FakeHttpClientRequest(
      onClose: () async => FakeHttpClientResponse(
        statusCode: statusCode,
        body: responseBody,
      ),
    );
    return lastRequest!;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'KelimeVS',
      packageName: 'com.riestudio.kelimevs',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('HttpPowerupApiClient.spend', () {
    test('200 OK: returns SpendPowerupSuccess with alreadySpent = false', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'ok': true,
          'coins': 120,
          'alreadySpent': false,
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupSuccess>());
      final success = result as SpendPowerupSuccess;
      expect(success.coins, equals(120));
      expect(success.alreadySpent, isFalse);
    });

    test('200 OK: returns SpendPowerupSuccess with alreadySpent = true on idempotent repeat', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'ok': true,
          'coins': 150,
          'alreadySpent': true,
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupSuccess>());
      final success = result as SpendPowerupSuccess;
      expect(success.coins, equals(150));
      expect(success.alreadySpent, isTrue);
    });

    test('402 Payment Required: returns SpendPowerupNotEnoughCoins with current coins', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 402,
        responseBody: jsonEncode({
          'ok': false,
          'error': 'not_enough_coins',
          'coins': 15,
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'give_answer',
      );

      expect(result, isA<SpendPowerupNotEnoughCoins>());
      final notEnough = result as SpendPowerupNotEnoughCoins;
      expect(notEnough.coins, equals(15));
    });

    test('410 Gone: calls onAccountDeleted and returns SpendPowerupAccountDeleted', () async {
      var deletedCalled = false;
      final fakeHttp = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({
          'ok': false,
          'error': 'account_deleted',
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
        onAccountDeleted: () => deletedCalled = true,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupAccountDeleted>());
      expect(deletedCalled, isTrue);
    });

    test('400 Bad Request: returns SpendPowerupBadRequest with parsed message', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({
          'ok': false,
          'error': 'bad_request',
          'message': 'matchId must start with bot: prefix',
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'invalid-match-id',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupBadRequest>());
      final badRequest = result as SpendPowerupBadRequest;
      expect(badRequest.message, equals('matchId must start with bot: prefix'));
    });

    test('404 Not Found: returns SpendPowerupNetworkError', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 404,
        responseBody: 'Not Found',
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupNetworkError>());
    });

    test('500 Internal Server Error: returns SpendPowerupNetworkError', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 500,
        responseBody: jsonEncode({
          'error': 'internal_server_error',
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupNetworkError>());
    });

    test('401 Unauthorized: returns SpendPowerupNetworkError', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 401,
        responseBody: jsonEncode({
          'error': 'unauthorized',
        }),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupNetworkError>());
    });

    test('null auth token: returns SpendPowerupNetworkError without making HTTP request', () async {
      var requestCreated = false;
      final fakeHttp = FakeHttpClient(
        onPostUrl: (uri) async {
          requestCreated = true;
          return FakeHttpClientRequest(
            onClose: () async => FakeHttpClientResponse(statusCode: 200, body: '{}'),
          );
        },
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider(null),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupNetworkError>());
      expect(requestCreated, isFalse);
    });

    test('SocketException: returns SpendPowerupNetworkError', () async {
      final fakeHttp = FakeHttpClient(
        onPostUrl: (uri) => throw const SocketException('Network unreachable'),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.spend(
        matchId: 'bot:validMatchId12345678',
        powerup: 'extra_time',
      );

      expect(result, isA<SpendPowerupNetworkError>());
      final error = result as SpendPowerupNetworkError;
      expect(error.error, isA<SocketException>());
    });

    test('Timeout (> 3 seconds): returns SpendPowerupNetworkError', () {
      fakeAsync((async) {
        final fakeHttp = FakeHttpClient(
          onPostUrl: (uri) async {
            await Future.delayed(const Duration(seconds: 4));
            return FakeHttpClientRequest(
              onClose: () async => FakeHttpClientResponse(statusCode: 200, body: '{}'),
            );
          },
        );

        final client = HttpPowerupApiClient(
          authTokenProvider: const MockAuthTokenProvider('test-token'),
          clientFactory: () => fakeHttp,
        );

        SpendPowerupResult? result;
        client
            .spend(matchId: 'bot:validMatchId12345678', powerup: 'extra_time')
            .then((r) => result = r);

        async.elapse(const Duration(seconds: 4));

        expect(result, isA<SpendPowerupNetworkError>());
      });
    });

    test('Payload does NOT include amount, only matchId and powerup', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'ok': true, 'coins': 90}),
      );

      final client = HttpPowerupApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      await client.spend(
        matchId: 'bot:customMatch12345678',
        powerup: 'give_answer',
      );

      expect(fakeHttp.lastRequest, isNotNull);
      final rawBody = fakeHttp.lastRequest!.bodyAsString;
      final body = jsonDecode(rawBody) as Map<String, dynamic>;

      expect(body['matchId'], equals('bot:customMatch12345678'));
      expect(body['powerup'], equals('give_answer'));
      expect(body.containsKey('amount'), isFalse, reason: 'amount must NOT be sent by client');
    });
  });

  group('generateBotMatchId', () {
    final serverBotMatchIdRegex = RegExp(r'^bot:[A-Za-z0-9_-]{8,64}$');

    test('generates an ID matching the server regex', () {
      for (var i = 0; i < 50; i++) {
        final id = generateBotMatchId();
        expect(serverBotMatchIdRegex.hasMatch(id), isTrue,
            reason: 'Generated ID "$id" does not match regex ^bot:[A-Za-z0-9_-]{8,64}\$');
        expect(id.startsWith('bot:'), isTrue);
        expect(id.length, equals(28)); // 'bot:' (4) + 24 chars
      }
    });

    test('generates unique IDs across calls', () {
      final ids = List.generate(100, (_) => generateBotMatchId()).toSet();
      expect(ids.length, equals(100));
    });

    test('supports injected deterministic math.Random', () {
      final id1 = generateBotMatchId(math.Random(12345));
      final id2 = generateBotMatchId(math.Random(12345));

      expect(id1, equals(id2));
      expect(serverBotMatchIdRegex.hasMatch(id1), isTrue);
    });
  });
}
