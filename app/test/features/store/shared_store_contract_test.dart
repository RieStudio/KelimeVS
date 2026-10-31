import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/store/data/store_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';

File _resolveSharedFile(String relativePath) {
  final candidate1 = File('../shared/$relativePath');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = File('shared/$relativePath');
  if (candidate2.existsSync()) return candidate2;

  final candidate3 = File('../../shared/$relativePath');
  if (candidate3.existsSync()) return candidate3;

  throw StateError('shared/$relativePath dosyası bulunamadı!');
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  int statusCode;
  String responseBody;
  FakeHttpClientRequest? lastRequest;

  FakeHttpClient({required this.statusCode, required this.responseBody});

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    lastRequest = FakeHttpClientRequest(
      FakeHttpClientResponse(statusCode: statusCode, body: responseBody),
    );
    return lastRequest!;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    lastRequest = FakeHttpClientRequest(
      FakeHttpClientResponse(statusCode: statusCode, body: responseBody),
    );
    return lastRequest!;
  }

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
  group('Shared Store Contract Tests (shared/test-vectors/store_contract.json)',
      () {
    late Map<String, dynamic> contract;

    setUpAll(() {
      final file = _resolveSharedFile('test-vectors/store_contract.json');
      expect(file.existsSync(), isTrue);
      contract = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('1. GET /store sözleşme çıktısı StoreItem.fromJson ve StoreState tarafından eksiksiz ayrıştırılır',
        () async {
      final getStore = contract['get_store'] as Map<String, dynamic>;
      final resp200 = getStore['response_200'] as Map<String, dynamic>;
      final body = resp200['body'] as Map<String, dynamic>;

      final rawItems = body['items'] as List<dynamic>;
      expect(rawItems.length, equals(12));

      // Her öğeyi StoreItem.fromJson ile ayrıştır ve alan adı doğruluğunu sına
      for (final raw in rawItems) {
        final itemMap = raw as Map<String, dynamic>;
        final parsed = StoreItem.fromJson(itemMap);

        expect(parsed.id, equals(itemMap['id']));
        expect(parsed.name, equals(itemMap['name']));

        // KRİTİK: Sunucu 'cost' alanı döner. 'cost' doğru okunmalı, fiyat sıfır olmamalıdır!
        expect(parsed.price, equals(itemMap['cost']));
        if (itemMap['id'] != 'classic') {
          expect(parsed.price, greaterThan(0));
        }

        // KRİTİK: Sunucu 'isOwned' alanı döner.
        expect(parsed.owned, equals(itemMap['isOwned']));
        expect(parsed.isEquipped, equals(itemMap['isEquipped']));
      }

      // HttpStoreApiClient üzerinden uçtan uca getStore testi
      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode(body),
      );
      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('token-123'),
        clientFactory: () => fakeHttp,
      );

      final state = await client.getStore();
      expect(state, isNotNull);
      expect(state!.coins, equals(body['coins']));
      expect(state.equippedFrame, equals(body['equippedFrame']));
      expect(state.items.length, equals(12));
    });

    test('2. POST /store/purchase istek ve yanıt sözleşmesi istemciyle birebir uyumludur',
        () async {
      final purchaseContract =
          contract['purchase_item'] as Map<String, dynamic>;
      final expectedReq =
          purchaseContract['request'] as Map<String, dynamic>;
      final resp200 = purchaseContract['response_200'] as Map<String, dynamic>;

      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode(resp200['body']),
      );
      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('token-123'),
        clientFactory: () => fakeHttp,
      );

      // İstemci isteği gönderir
      final res = await client.purchaseItem(expectedReq['itemId'] as String);

      // İstek gövdesi sözleşmedeki itemId anahtarını içermeli
      expect(fakeHttp.lastRequest, isNotNull);
      final sentBody =
          jsonDecode(fakeHttp.lastRequest!.bodyAsString) as Map<String, dynamic>;
      expect(sentBody['itemId'], equals(expectedReq['itemId']));

      // 200 Başarılı Yanıt doğrulaması
      expect(res, isA<StorePurchaseSuccess>());
      final successRes = res as StorePurchaseSuccess;
      expect(successRes.itemId, equals(resp200['body']['itemId']));
      expect(successRes.coins, equals(resp200['body']['coins']));

      // 402 Yetersiz Bakiye doğrulaması
      final resp402 = purchaseContract['response_402_not_enough_coins']
          as Map<String, dynamic>;
      fakeHttp.statusCode = resp402['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp402['body']);
      final res402 = await client.purchaseItem('gold');
      expect(res402, isA<StorePurchaseNotEnoughCoins>());

      // 400 Zaten Sahip Olunan Ürün doğrulaması
      final resp400Already = purchaseContract['response_400_already_owned']
          as Map<String, dynamic>;
      fakeHttp.statusCode = resp400Already['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp400Already['body']);
      final resAlready = await client.purchaseItem('mint');
      expect(resAlready, isA<StorePurchaseAlreadyOwned>());

      // 400 Geçersiz Ürün doğrulaması
      final resp400Invalid = purchaseContract['response_400_invalid_item']
          as Map<String, dynamic>;
      fakeHttp.statusCode = resp400Invalid['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp400Invalid['body']);
      final resInvalid = await client.purchaseItem('bad_item');
      expect(resInvalid, isA<StorePurchaseInvalidItem>());
    });

    test('3. PUT /me/frame istek ve yanıt sözleşmesi istemciyle birebir uyumludur',
        () async {
      final equipContract = contract['equip_frame'] as Map<String, dynamic>;
      final resp200 = equipContract['response_200'] as Map<String, dynamic>;
      final clientPayload =
          equipContract['request_client_payload'] as Map<String, dynamic>;

      final fakeHttp = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode(resp200['body']),
      );
      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('token-123'),
        clientFactory: () => fakeHttp,
      );

      final res = await client.equipFrame(clientPayload['frameId'] as String);

      // İstemcinin gönderdiği gövdede hem frameId hem frame yer almalıdır
      expect(fakeHttp.lastRequest, isNotNull);
      final sentBody =
          jsonDecode(fakeHttp.lastRequest!.bodyAsString) as Map<String, dynamic>;
      expect(sentBody['frameId'], equals(clientPayload['frameId']));
      expect(sentBody['frame'], equals(clientPayload['frame']));

      // 200 Başarılı Kuşanma doğrulaması
      expect(res, isA<StoreEquipSuccess>());
      final successRes = res as StoreEquipSuccess;
      expect(successRes.frameId, equals(resp200['body']['equippedFrame']));

      // 400 Sahip Olunmayan Çerçeve doğrulaması
      final resp400NotOwned = equipContract['response_400_item_not_owned']
          as Map<String, dynamic>;
      fakeHttp.statusCode = resp400NotOwned['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp400NotOwned['body']);
      final resNotOwned = await client.equipFrame('gold');
      expect(resNotOwned, isA<StoreEquipNotOwned>());
      expect((resNotOwned as StoreEquipNotOwned).message,
          equals(AppStrings.itemNotOwnedError));

      // 400 Geçersiz Çerçeve doğrulaması
      final resp400InvalidFrame = equipContract['response_400_invalid_frame']
          as Map<String, dynamic>;
      fakeHttp.statusCode = resp400InvalidFrame['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp400InvalidFrame['body']);
      final resInvalidFrame = await client.equipFrame('bad_frame');
      expect(resInvalidFrame, isA<StoreEquipInvalidFrame>());
      expect((resInvalidFrame as StoreEquipInvalidFrame).message,
          equals(AppStrings.storeInvalidFrameError));
    });

    test('4. Ortak hata kodları (410, 500) sözleşmeye göre doğru modellenmelidir',
        () async {
      final common = contract['common_errors'] as Map<String, dynamic>;
      final resp410 =
          common['response_410_account_deleted'] as Map<String, dynamic>;
      final resp500 =
          common['response_500_internal_error'] as Map<String, dynamic>;

      bool deletedCalled = false;
      final fakeHttp = FakeHttpClient(
        statusCode: resp410['status'] as int,
        responseBody: jsonEncode(resp410['body']),
      );
      final client = HttpStoreApiClient(
        authTokenProvider: const MockAuthTokenProvider('token-123'),
        clientFactory: () => fakeHttp,
        onAccountDeleted: () => deletedCalled = true,
      );

      // 410 -> StorePurchaseAccountDeleted / StoreEquipAccountDeleted
      final purchase410 = await client.purchaseItem('mint');
      expect(purchase410, isA<StorePurchaseAccountDeleted>());
      expect(deletedCalled, isTrue);

      final equip410 = await client.equipFrame('mint');
      expect(equip410, isA<StoreEquipAccountDeleted>());

      // 500 -> StorePurchaseNetworkError / StoreEquipNetworkError
      fakeHttp.statusCode = resp500['status'] as int;
      fakeHttp.responseBody = jsonEncode(resp500['body']);

      final purchase500 = await client.purchaseItem('mint');
      expect(purchase500, isA<StorePurchaseNetworkError>());

      final equip500 = await client.equipFrame('mint');
      expect(equip500, isA<StoreEquipNetworkError>());
      expect((equip500 as StoreEquipNetworkError).message,
          equals(AppStrings.storeServerError));
    });
  });
}

