import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/profile/data/profile_api_client.dart';

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
  Future<HttpClientRequest> putUrl(Uri url) async {
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

void main() {
  group('HttpProfileApiClient Tests', () {
    test('1. getProfile() başarılı 200 yanıtında profili doğru modeller', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 200,
          responseBody: jsonEncode({
            'uid': 'user_1',
            'nickname': 'Ahmet',
            'coins': 130,
            'stats': {'played': 3, 'won': 2, 'lost': 1},
            'createdAt': 1790000000000,
          }),
        ),
      );

      final profile = await client.getProfile();
      expect(profile, isNotNull);
      expect(profile!.uid, 'user_1');
      expect(profile.nickname, 'Ahmet');
      expect(profile.coins, 130);
      expect(profile.played, 3);
      expect(profile.won, 2);
      expect(profile.lost, 1);
    });

    test('2. getProfile() ağ hatasında sessizce null döner', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(shouldThrow: true),
      );

      final profile = await client.getProfile();
      expect(profile, isNull);
    });

    test('3. updateNickname() 200 döndüğünde ProfileUpdateSuccess üretir', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 200,
          responseBody: jsonEncode({'ok': true, 'nickname': 'Mehmet'}),
        ),
      );

      final res = await client.updateNickname('  Mehmet  ');
      expect(res, isA<ProfileUpdateSuccess>());
      expect((res as ProfileUpdateSuccess).nickname, 'Mehmet');
    });

    test('4. updateNickname() 400 döndüğünde ProfileUpdateInvalidNickname üretir', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 400,
          responseBody: jsonEncode({
            'error': 'invalid_nickname',
            'message': 'Takma ad çok kısa',
          }),
        ),
      );

      final res = await client.updateNickname('ab');
      expect(res, isA<ProfileUpdateInvalidNickname>());
      expect((res as ProfileUpdateInvalidNickname).message, 'Takma ad çok kısa');
    });

    test('5. updateNickname() ağ hatasında ProfileUpdateNetworkError üretir', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(shouldThrow: true),
      );

      final res = await client.updateNickname('YeniAd');
      expect(res, isA<ProfileUpdateNetworkError>());
    });
  });
}
