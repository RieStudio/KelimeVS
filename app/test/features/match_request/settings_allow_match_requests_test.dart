import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/core/network/app_build_info.dart';

import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class CapturingSettingsHttpClient implements HttpClient {
  String? lastMethod;
  Uri? lastUrl;
  String? lastBody;
  int statusCode;
  String responseBody;

  CapturingSettingsHttpClient({
    this.statusCode = 200,
    this.responseBody = '{"ok":true,"allowMatchRequests":false}',
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    lastMethod = 'PUT';
    lastUrl = url;
    return CapturingSettingsRequest(
      statusCode: statusCode,
      responseBody: responseBody,
      onDataAdded: (body) => lastBody = body,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CapturingSettingsRequest implements HttpClientRequest {
  final int statusCode;
  final String responseBody;
  final void Function(String) onDataAdded;
  final List<int> _buffer = [];

  CapturingSettingsRequest({
    required this.statusCode,
    required this.responseBody,
    required this.onDataAdded,
  });

  @override
  final HttpHeaders headers = FakeHttpHeaders();

  @override
  int contentLength = 0;

  @override
  void add(List<int> data) {
    _buffer.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    onDataAdded(utf8.decode(_buffer));
    return CapturingSettingsResponse(statusCode: statusCode, body: responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, Object> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CapturingSettingsResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  CapturingSettingsResponse({required this.statusCode, required this.body});

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

class FakeSettingsProfileApiClient implements ProfileApiClient {
  bool shouldSucceed = true;
  bool? lastAllowPassed;
  UserProfileModel? mockProfile;

  @override
  Future<bool> updateAllowMatchRequests(bool allow) async {
    lastAllowPassed = allow;
    return shouldSucceed;
  }

  @override
  Future<UserProfileModel?> getProfile() async => mockProfile;

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      const ProfileUpdateSuccess('nickname');

  @override
  Future<bool> deleteProfile() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileModel allowMatchRequests', () {
    test('JSON ayrıştırma: varsayılan true (alan yoksa veya null ise)', () {
      final jsonEmpty = {
        'uid': 'u_1',
        'nickname': 'Alice',
        'coins': 100,
        'equippedFrame': 'classic',
      };

      final profile1 = UserProfileModel.fromJson(jsonEmpty);
      expect(profile1.allowMatchRequests, isTrue);

      final jsonNull = {
        ...jsonEmpty,
        'allowMatchRequests': null,
      };
      final profile2 = UserProfileModel.fromJson(jsonNull);
      expect(profile2.allowMatchRequests, isTrue);
    });

    test('JSON ayrıştırma: camelCase (allowMatchRequests) ve snake_case (allow_match_requests)', () {
      final jsonCamel = {
        'uid': 'u_2',
        'allowMatchRequests': false,
      };
      final profileCamel = UserProfileModel.fromJson(jsonCamel);
      expect(profileCamel.allowMatchRequests, isFalse);

      final jsonSnake = {
        'uid': 'u_3',
        'allow_match_requests': false,
      };
      final profileSnake = UserProfileModel.fromJson(jsonSnake);
      expect(profileSnake.allowMatchRequests, isFalse);
    });

    test('UserProfileModel kurucusu allowMatchRequests alanını doğru saklar', () {
      const profile = UserProfileModel(
        uid: 'u_4',
        nickname: 'Bob',
        coins: 150,
        equippedFrame: 'classic',
        allowMatchRequests: false,
      );

      expect(profile.allowMatchRequests, isFalse);
    });
  });

  group('ProfileNotifier.updateAllowMatchRequests', () {
    late FakeSettingsProfileApiClient fakeApiClient;
    late ProviderContainer container;

    setUp(() {
      fakeApiClient = FakeSettingsProfileApiClient();
      container = ProviderContainer(
        overrides: [
          profileApiClientProvider.overrideWithValue(fakeApiClient),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Başarılı güncellemede iyimser güncellenir ve API çağrılır', () async {
      final notifier = container.read(profileProvider.notifier);
      expect(container.read(profileProvider).allowMatchRequests, isTrue);

      final success = await notifier.updateAllowMatchRequests(false);

      expect(success, isTrue);
      expect(fakeApiClient.lastAllowPassed, isFalse);
      expect(container.read(profileProvider).allowMatchRequests, isFalse);
    });

    test('API hatasında (false dönerse) önceki değere geri döner (rollback)', () async {
      fakeApiClient.shouldSucceed = false;
      final notifier = container.read(profileProvider.notifier);

      expect(container.read(profileProvider).allowMatchRequests, isTrue);

      final success = await notifier.updateAllowMatchRequests(false);

      expect(success, isFalse);
      expect(fakeApiClient.lastAllowPassed, isFalse);
      // Rollback: Tekrar true olmalı
      expect(container.read(profileProvider).allowMatchRequests, isTrue);
    });
  });

  group('HttpProfileApiClient.updateAllowMatchRequests HTTP Sözleşmesi ve Ayrıştırma', () {
    setUp(() {
      AppBuildInfo.setMockBuildNumber(1);
    });

    tearDown(() {
      AppBuildInfo.resetForTesting();
    });

    test('Sunucu sözleşmesi: PUT /me/settings metodunu ve allowMatchRequests gövdesini doğrular', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'valid_jwt_token');
      final fakeHttp = CapturingSettingsHttpClient(
        statusCode: 200,
        responseBody: '{"ok":true,"allowMatchRequests":false}',
      );

      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => fakeHttp,
      );

      final result = await client.updateAllowMatchRequests(false);

      expect(result, isTrue);
      expect(fakeHttp.lastMethod, 'PUT');
      expect(fakeHttp.lastUrl?.path, '/me/settings');

      // İstek gövdesini assert et
      expect(fakeHttp.lastBody, isNotNull);
      final decodedBody = jsonDecode(fakeHttp.lastBody!) as Map<String, dynamic>;
      expect(decodedBody, {'allowMatchRequests': false});
    });

    test('Sunucu sözleşmesi: 200 OK ve ok:false veya bozuk gövdede false döner', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'valid_jwt_token');
      final fakeHttp = CapturingSettingsHttpClient(
        statusCode: 200,
        responseBody: '{"ok":false}',
      );

      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => fakeHttp,
      );

      final result = await client.updateAllowMatchRequests(true);
      expect(result, isFalse);
    });

    test('Sunucu sözleşmesi: 410 Gone durumunda onAccountDeleted çağrılır ve false döner', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'valid_jwt_token');
      final fakeHttp = CapturingSettingsHttpClient(
        statusCode: 410,
        responseBody: '{"error":"account_deleted","message":"Hesap silinmiş"}',
      );

      bool accountDeletedCalled = false;
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => fakeHttp,
        onAccountDeleted: () => accountDeletedCalled = true,
      );

      final result = await client.updateAllowMatchRequests(false);

      expect(result, isFalse);
      expect(accountDeletedCalled, isTrue);
    });

    test('Sunucu sözleşmesi: 400 Bad Request veya 500 Internal Error durumunda false döner', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'valid_jwt_token');
      final fakeHttp = CapturingSettingsHttpClient(
        statusCode: 400,
        responseBody: '{"error":"bad_request"}',
      );

      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => fakeHttp,
      );

      final result = await client.updateAllowMatchRequests(false);
      expect(result, isFalse);
    });
  });
}
