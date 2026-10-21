import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/store/data/store_api_client.dart';

class MockAuthTokenProvider implements AuthTokenProvider {
  final String? token;
  const MockAuthTokenProvider([this.token = 'mock-jwt-token']);

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => token;
}

class FakeHttpClientRequest implements HttpClientRequest {
  final HttpHeaders _headers = _MockHttpHeaders();
  final List<List<int>> _body = [];
  final HttpClientResponse response;

  FakeHttpClientRequest(this.response);

  @override
  HttpHeaders get headers => _headers;

  @override
  void add(List<int> data) {
    _body.add(data);
  }

  String get bodyAsString => utf8.decode(_body.expand((x) => x).toList());

  @override
  Future<HttpClientResponse> close() async => response;

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

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = [value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  final int statusCode;
  final String responseBody;
  FakeHttpClientRequest? lastRequest;

  FakeHttpClient({required this.statusCode, required this.responseBody});

  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    lastRequest = FakeHttpClientRequest(
      FakeHttpClientResponse(statusCode: statusCode, body: responseBody),
    );
    return lastRequest!;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HttpStoreApiClient.equipFrame Tests', () {
    test('sends both frameId and frame in body and returns StoreEquipSuccess on 200', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'success': true, 'equippedFrame': 'gold'}),
      );

      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.equipFrame('gold');

      expect(result, isA<StoreEquipSuccess>());
      expect((result as StoreEquipSuccess).frameId, equals('gold'));

      final sentBody = jsonDecode(fakeHttp.lastRequest!.bodyAsString) as Map<String, dynamic>;
      expect(sentBody['frameId'], equals('gold'));
      expect(sentBody['frame'], equals('gold'));
    });

    test('returns StoreEquipNotOwned on 400 item_not_owned', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'item_not_owned', 'message': 'Bu çerçeveye sahip değilsiniz'}),
      );

      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.equipFrame('gold');

      expect(result, isA<StoreEquipNotOwned>());
      expect((result as StoreEquipNotOwned).message, equals(AppStrings.itemNotOwnedError));
    });

    test('returns StoreEquipInvalidFrame with server message on 400 invalid_frame', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'invalid_frame', 'message': 'Geçersiz çerçeve kimliği'}),
      );

      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.equipFrame('unknown_frame');

      expect(result, isA<StoreEquipInvalidFrame>());
      expect((result as StoreEquipInvalidFrame).message, equals(AppStrings.storeInvalidFrameError));
    });

    test('returns StoreEquipNetworkError on 500 server error', () async {
      final fakeHttp = FakeHttpClient(
        statusCode: 500,
        responseBody: jsonEncode({'error': 'internal_error', 'message': 'DO down'}),
      );

      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
      );

      final result = await client.equipFrame('gold');

      expect(result, isA<StoreEquipNetworkError>());
      expect((result as StoreEquipNetworkError).message, equals(AppStrings.storeServerError));
    });

    test('returns StoreEquipAccountDeleted and triggers callback on 410', () async {
      bool deletedCalled = false;
      final fakeHttp = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({'error': 'account_deleted'}),
      );

      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('test-token'),
        clientFactory: () => fakeHttp,
        onAccountDeleted: () => deletedCalled = true,
      );

      final result = await client.equipFrame('mint');

      expect(result, isA<StoreEquipAccountDeleted>());
      expect(deletedCalled, isTrue);
    });
  });
}
