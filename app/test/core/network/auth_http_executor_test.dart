import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/network/auth_http_executor.dart';
import 'package:app/features/online/data/auth_token_provider.dart';

class TrackingTokenProvider implements AuthTokenProvider {
  final List<bool> forceRefreshHistory = [];
  String? tokenToReturn;
  String? refreshedTokenToReturn;

  TrackingTokenProvider({
    this.tokenToReturn = 'initial_token',
    this.refreshedTokenToReturn = 'refreshed_token',
  });

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    forceRefreshHistory.add(forceRefresh);
    if (forceRefresh) {
      return refreshedTokenToReturn;
    }
    return tokenToReturn;
  }
}

class MockHttpClient implements HttpClient {
  final List<MockHttpClientRequest> createdRequests = [];
  final List<int> responseStatusCodes;
  final List<String> responseBodies;
  int _callIndex = 0;

  MockHttpClient({
    required this.responseStatusCodes,
    this.responseBodies = const [],
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final status = _callIndex < responseStatusCodes.length
        ? responseStatusCodes[_callIndex]
        : 500;
    final body = _callIndex < responseBodies.length
        ? responseBodies[_callIndex]
        : '{}';
    _callIndex++;
    final req = MockHttpClientRequest(statusCode: status, responseBody: body);
    createdRequests.add(req);
    return req;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final String responseBody;
  final MockHttpHeaders mockHeaders = MockHttpHeaders();

  MockHttpClientRequest({
    required this.statusCode,
    required this.responseBody,
  });

  @override
  HttpHeaders get headers => mockHeaders;

  @override
  int contentLength = 0;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(statusCode: statusCode, body: responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockHttpClientResponse({required this.statusCode, required this.body});

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthHttpExecutor', () {
    test('1. Başarılı 200 yanıtında token yenilenmez ve tek istek yapılır', () async {
      final tokenProvider = TrackingTokenProvider(tokenToReturn: 'valid_jwt');
      final mockHttp = MockHttpClient(
        responseStatusCodes: [200],
        responseBodies: ['{"ok": true}'],
      );

      final res = await AuthHttpExecutor.execute(
        authTokenProvider: tokenProvider,
        uri: Uri.parse('https://api.example.com/me'),
        method: 'GET',
        clientFactory: () => mockHttp,
      );

      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(tokenProvider.forceRefreshHistory, [false]);
      expect(mockHttp.createdRequests.length, 1);
      expect(
        mockHttp.createdRequests[0].mockHeaders.values['authorization'],
        'Bearer valid_jwt',
      );
    });

    test('2. 401 yanıtında token forceRefresh: true ile yenilenip istek 1 kez tekrar denenir ve 200 döner', () async {
      final tokenProvider = TrackingTokenProvider(
        tokenToReturn: 'expired_jwt',
        refreshedTokenToReturn: 'fresh_jwt',
      );
      final mockHttp = MockHttpClient(
        responseStatusCodes: [401, 200],
        responseBodies: ['{"error":"unauthorized"}', '{"ok": true}'],
      );

      final res = await AuthHttpExecutor.execute(
        authTokenProvider: tokenProvider,
        uri: Uri.parse('https://api.example.com/me'),
        method: 'GET',
        clientFactory: () => mockHttp,
      );

      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(res.decodeJsonMap()['ok'], isTrue);
      // İlk çağrı false, 401 sonrası forceRefresh: true
      expect(tokenProvider.forceRefreshHistory, [false, true]);
      expect(mockHttp.createdRequests.length, 2);
      expect(
        mockHttp.createdRequests[0].mockHeaders.values['authorization'],
        'Bearer expired_jwt',
      );
      expect(
        mockHttp.createdRequests[1].mockHeaders.values['authorization'],
        'Bearer fresh_jwt',
      );
    });

    test('3. İkinci denemede de 401 gelirse döngüye girmeden sonlanır (en fazla 1 tekrar)', () async {
      final tokenProvider = TrackingTokenProvider(
        tokenToReturn: 'bad_token_1',
        refreshedTokenToReturn: 'bad_token_2',
      );
      final mockHttp = MockHttpClient(
        responseStatusCodes: [401, 401],
        responseBodies: ['{"error":"unauthorized"}', '{"error":"still_unauthorized"}'],
      );

      final res = await AuthHttpExecutor.execute(
        authTokenProvider: tokenProvider,
        uri: Uri.parse('https://api.example.com/me'),
        method: 'GET',
        clientFactory: () => mockHttp,
      );

      expect(res, isNotNull);
      expect(res!.statusCode, 401);
      expect(mockHttp.createdRequests.length, 2);
      expect(tokenProvider.forceRefreshHistory, [false, true]);
    });

    test('4. 401 sonrasında forceRefresh null dönerse tekrar denenmez', () async {
      final tokenProvider = TrackingTokenProvider(
        tokenToReturn: 'expired_jwt',
        refreshedTokenToReturn: null,
      );
      final mockHttp = MockHttpClient(
        responseStatusCodes: [401],
        responseBodies: ['{"error":"unauthorized"}'],
      );

      final res = await AuthHttpExecutor.execute(
        authTokenProvider: tokenProvider,
        uri: Uri.parse('https://api.example.com/me'),
        method: 'GET',
        clientFactory: () => mockHttp,
      );

      expect(res, isNotNull);
      expect(res!.statusCode, 401);
      expect(mockHttp.createdRequests.length, 1);
      expect(tokenProvider.forceRefreshHistory, [false, true]);
    });

    test('5. İlk token null dönerse HTTP isteği yapılmaz ve null döner', () async {
      final tokenProvider = TrackingTokenProvider(tokenToReturn: null);
      final mockHttp = MockHttpClient(responseStatusCodes: []);

      final res = await AuthHttpExecutor.execute(
        authTokenProvider: tokenProvider,
        uri: Uri.parse('https://api.example.com/me'),
        method: 'GET',
        clientFactory: () => mockHttp,
      );

      expect(res, isNull);
      expect(mockHttp.createdRequests.isEmpty, isTrue);
      expect(tokenProvider.forceRefreshHistory, [false]);
    });
  });
}
