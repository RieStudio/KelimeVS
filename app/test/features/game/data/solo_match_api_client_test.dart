import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:app/features/game/data/solo_match_api_client.dart';
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

  FakeHttpClientRequest({required this.onClose});

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

  const sampleSubmission = SoloMatchSubmission(
    matchId: 'bot:validMatchId12345678',
    outcome: 'win',
    myScore: 2,
    oppScore: 1,
    correctAnswers: 4,
    durationSeconds: 35,
    endedBy: 'normal',
    submittedAtMs: 1700000000000,
  );

  group('HttpSoloMatchApiClient.submit', () {
    test('200 OK: counted: true durumunda ödül, enerji ve başarımlar doğru parse edilir', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'ok': true,
          'counted': true,
          'coins': 150,
          'coinsAwarded': 30,
          'unlockedAchievements': ['first_win', 'wins_10'],
          'alreadyProcessed': false,
          'energy': {
            'enabled': true,
            'current': 4,
            'max': 5,
            'secondsToNext': 1200,
            'isUnlimited': false,
          },
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchSuccess>());
      final success = result as SubmitSoloMatchSuccess;
      expect(success.counted, isTrue);
      expect(success.coins, equals(150));
      expect(success.coinsAwarded, equals(30));
      expect(success.alreadyProcessed, isFalse);
      expect(success.unlockedAchievements, equals(['first_win', 'wins_10']));
      expect(success.energy, isNotNull);
      expect(success.energy!.current, equals(4));
      expect(success.energy!.max, equals(5));
      expect(success.energy!.regenSeconds, equals(1200));
    });

    test('200 OK: counted: false durumunda (yetersiz enerji vb.) coinsAwarded null döner', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'ok': true,
          'counted': false,
          'coins': 120,
          'coinsAwarded': null,
          'unlockedAchievements': [],
          'alreadyProcessed': false,
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchSuccess>());
      final success = result as SubmitSoloMatchSuccess;
      expect(success.counted, isFalse);
      expect(success.coinsAwarded, equals(0));
      expect(success.coins, equals(120));
      expect(success.unlockedAchievements, isEmpty);
    });

    test('400 Bad Request: SubmitSoloMatchPermanentError döner ve tekrar denenmez', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({
          'ok': false,
          'error': 'invalid_payload',
          'message': 'Duration too short',
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchPermanentError>());
      final err = result as SubmitSoloMatchPermanentError;
      expect(err.statusCode, equals(400));
      expect(err.error, equals('invalid_payload'));
    });

    test('410 Gone: onAccountDeleted tetiklenir ve SubmitSoloMatchPermanentError döner', () async {
      var deletedCalled = false;
      final fakeHttp = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({
          'ok': false,
          'error': 'account_deleted',
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
        onAccountDeleted: () => deletedCalled = true,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchPermanentError>());
      final err = result as SubmitSoloMatchPermanentError;
      expect(err.statusCode, equals(410));
      expect(err.error, equals('account_deleted'));
      expect(deletedCalled, isTrue);
    });

    test('401 Unauthorized: SubmitSoloMatchTransientError döner (kuyrukta kalır)', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 401,
        responseBody: jsonEncode({
          'error': 'unauthorized',
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchTransientError>());
    });

    test('500 Internal Server Error: SubmitSoloMatchTransientError döner', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 500,
        responseBody: jsonEncode({
          'error': 'internal_server_error',
        }),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchTransientError>());
    });

    test('Auth token null ise istek yapmadan SubmitSoloMatchTransientError döner', () async {
      var requestMade = false;
      final fakeHttp = FakeHttpClient(
        onPostUrl: (uri) async {
          requestMade = true;
          return FakeHttpClientRequest(
            onClose: () async => FakeHttpClientResponse(statusCode: 200, body: '{}'),
          );
        },
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider(null),
        clientFactory: () => fakeHttp,
      );

      final result = await client.submit(sampleSubmission);

      expect(result, isA<SubmitSoloMatchTransientError>());
      expect(requestMade, isFalse);
    });

    test('İstek gövdesi sadece sunucunun beklediği alanları içerir, jeton/ödül beyanı içermez', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'ok': true, 'counted': true}),
      );

      final client = HttpSoloMatchApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      await client.submit(sampleSubmission);

      expect(fakeHttp.lastRequest, isNotNull);
      final raw = fakeHttp.lastRequest!.bodyAsString;
      final map = jsonDecode(raw) as Map<String, dynamic>;

      expect(map['matchId'], equals('bot:validMatchId12345678'));
      expect(map['outcome'], equals('win'));
      expect(map['myScore'], equals(2));
      expect(map['oppScore'], equals(1));
      expect(map['correctAnswers'], equals(4));
      expect(map['durationSeconds'], equals(35));
      expect(map['endedBy'], equals('normal'));

      // İstemci ödül ve jeton hesaplaması göndermez
      expect(map.containsKey('coins'), isFalse);
      expect(map.containsKey('coinsAwarded'), isFalse);
      expect(map.containsKey('reward'), isFalse);
    });
  });
}
