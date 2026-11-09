import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/domain/energy_state.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('1b. getProfile() gerçek sunucu misafir JSON yanıtını (isGuest, M-####, energy, serverNowMs) eksiksiz ayrıştırır', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_guest_123');
      final realServerJson = {
        'uid': 'guest_firebase_uid_999',
        'nickname': 'M-4821',
        'coins': 100,
        'stats': {
          'played': 0,
          'won': 0,
          'lost': 0,
          'correctAnswers': 0,
        },
        'createdAt': 1730000000000,
        'equippedFrame': 'classic',
        'isGuest': true,
        'isSystemNickname': true,
        'serverNowMs': 1730000000500,
        'energy': {
          'enabled': true,
          'current': 5,
          'max': 5,
          'nextEnergyAtMs': null,
          'regenSeconds': 1200,
          'packs': [
            {'id': 'one', 'cost': 100, 'energy': 1},
            {'id': 'full', 'cost': 400, 'energy': 5},
          ],
        },
      };

      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 200,
          responseBody: jsonEncode(realServerJson),
        ),
      );

      final profile = await client.getProfile();
      expect(profile, isNotNull);
      expect(profile!.uid, 'guest_firebase_uid_999');
      expect(profile.nickname, 'M-4821');
      expect(profile.coins, 100);
      expect(profile.isGuest, isTrue);
      expect(profile.stats.correctAnswers, 0);
      expect(profile.serverNowMs, 1730000000500);
      expect(profile.energy, isNotNull);
      expect(profile.energy!.enabled, isTrue);
      expect(profile.energy!.current, 5);
      expect(profile.energy!.packs.length, 2);
      expect(profile.energy!.packs.first.id, 'one');
    });

    test('1c. getProfile() canlı sunucu şeması ile birebir uyumlu ayrıştırma (equipped_frame, regenMinutes/regenSeconds, packs "one" ve "full", frameMigration, serverNowMs)', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_live_test');
      final livePayload = {
        'uid': 'guest_live_uid_4821',
        'nickname': 'M-4821',
        'coins': 100,
        'played': 1,
        'won': 1,
        'lost': 0,
        'stats': {
          'played': 1,
          'won': 1,
          'lost': 0,
          'correctAnswers': 4,
        },
        'createdAt': 1730000000000,
        'equipped_frame': 'gold_frame',
        'is_guest': 1,
        'isSystemNickname': true,
        'serverNowMs': 1730000000500,
        'frameMigration': {
          'refundedCoins': 150,
          'removedFrames': ['retro_neon'],
        },
        'energy': {
          'enabled': true,
          'current': 3,
          'max': 5,
          'nextEnergyAtMs': 1730000001000,
          'regenMinutes': 20,
          'regenSeconds': 1200,
          'packs': [
            {'id': 'one', 'cost': 20, 'energy': 1},
            {'id': 'full', 'cost': 80, 'energy': 5},
          ],
        },
      };

      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 200,
          responseBody: jsonEncode(livePayload),
        ),
      );

      final profile = await client.getProfile();
      expect(profile, isNotNull);
      expect(profile!.uid, 'guest_live_uid_4821');
      expect(profile.nickname, 'M-4821');
      expect(profile.coins, 100);
      expect(profile.isGuest, isTrue);
      expect(profile.equippedFrame, 'gold_frame');
      expect(profile.stats.played, 1);
      expect(profile.stats.won, 1);
      expect(profile.stats.correctAnswers, 4);
      expect(profile.serverNowMs, 1730000000500);

      // frameMigration kontrolü
      expect(profile.frameMigration, isNotNull);
      expect(profile.frameMigration!.refundedCoins, 150);
      expect(profile.frameMigration!.removedFrames, ['retro_neon']);

      // energy kontrolü
      expect(profile.energy, isNotNull);
      expect(profile.energy!.enabled, isTrue);
      expect(profile.energy!.current, 3);
      expect(profile.energy!.max, 5);
      expect(profile.energy!.nextEnergyAtMs, 1730000001000);
      expect(profile.energy!.regenSeconds, 1200);
      expect(profile.energy!.packs.length, 2);

      final packOne = profile.energy!.packs[0];
      expect(packOne.id, 'one');
      expect(packOne.cost, 20);
      expect(packOne.energy, 1);

      final packFull = profile.energy!.packs[1];
      expect(packFull.id, 'full');
      expect(packFull.cost, 80);
      expect(packFull.energy, 5);
    });

    test('1d. EnergyState.fromJson bağımsız olarak packs ("one" ve "full") ile ENERGY_ENABLED=true durumunda başarıyla parse edilir', () {
      final json = {
        'enabled': true,
        'current': 4,
        'max': 5,
        'nextEnergyAtMs': 1730000000000,
        'regenMinutes': 20,
        'packs': [
          {'id': 'one', 'cost': 20, 'energy': 1},
          {'id': 'full', 'cost': 80, 'energy': 5},
        ],
      };

      final state = EnergyState.fromJson(json);
      expect(state.enabled, isTrue);
      expect(state.current, 4);
      expect(state.max, 5);
      expect(state.regenSeconds, 1200); // 20 * 60
      expect(state.nextEnergyAtMs, 1730000000000);
      expect(state.packs.length, 2);
      expect(state.packs[0].id, 'one');
      expect(state.packs[0].cost, 20);
      expect(state.packs[0].energy, 1);
      expect(state.packs[1].id, 'full');
      expect(state.packs[1].cost, 80);
      expect(state.packs[1].energy, 5);
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

    test('6. updateNickname() 429 döndüğünde ProfileUpdateCooldown üretir', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 429,
          responseBody: jsonEncode({
            'error': 'nickname_cooldown',
            'message': 'Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: 2 saat sonra.',
            'remainingSeconds': 7200,
          }),
        ),
      );

      final res = await client.updateNickname('YeniAd');
      expect(res, isA<ProfileUpdateCooldown>());
      final cooldown = res as ProfileUpdateCooldown;
      expect(cooldown.remainingSeconds, 7200);
      expect(cooldown.message, 'Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: 2 saat sonra.');
    });

    test('6b. updateNickname() 429 döndüğünde gövdede message yoksa AppStrings.nicknameCooldownError fallback kullanılır', () async {
      final fakeAuth = FakeAuthTokenProvider(token: 'token_123');
      final client = HttpProfileApiClient(
        authTokenProvider: fakeAuth,
        clientFactory: () => FakeHttpClient(
          statusCode: 429,
          responseBody: jsonEncode({
            'error': 'nickname_cooldown',
            'remainingSeconds': 7200,
          }),
        ),
      );

      final res = await client.updateNickname('YeniAd');
      expect(res, isA<ProfileUpdateCooldown>());
      final cooldown = res as ProfileUpdateCooldown;
      expect(cooldown.remainingSeconds, 7200);
      expect(cooldown.message, AppStrings.nicknameCooldownError);
    });
  });
}
