import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';

class FakeProfileRepository implements ProfileRepository {
  String? _nickname;
  int _coins = 100;
  bool _syncPending = false;
  String _equippedFrame = 'classic';

  FakeProfileRepository({String? initialNickname, int initialCoins = 100})
      : _nickname = initialNickname,
        _coins = initialCoins;

  @override
  Future<String?> getNickname() async => _nickname;

  @override
  Future<void> setNickname(String nickname) async {
    _nickname = nickname.trim();
  }

  @override
  Future<bool> hasNickname() async => _nickname != null && _nickname!.isNotEmpty;

  @override
  Future<int> getCoins({int defaultCoins = 100}) async => _coins;

  @override
  Future<void> setCoins(int coins) async {
    _coins = coins;

  }

  @override
  Future<String> getEquippedFrame({String defaultFrame = 'classic'}) async =>
      _equippedFrame;

  @override
  Future<void> setEquippedFrame(String frame) async {
    _equippedFrame = frame;
  }

  @override
  Future<bool> isNicknameSyncPending() async => _syncPending;

  @override
  Future<void> setNicknameSyncPending(bool pending) async {
    _syncPending = pending;
  }

  @override
  Future<void> clear() async {
    _nickname = null;
    _coins = 100;
    _syncPending = false;
  }
}

class FakeProfileApiClient implements ProfileApiClient {
  UserProfileModel? mockProfile;
  ProfileUpdateResult updateResult = const ProfileUpdateSuccess('Success');
  String? lastUpdatedNickname;
  int updateNicknameCallCount = 0;

  @override
  Future<UserProfileModel?> getProfile() async => mockProfile;

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async {
    updateNicknameCallCount++;
    lastUpdatedNickname = nickname;
    return updateResult;
  }

  @override
  Future<bool> deleteProfile() async => true;
}

void main() {
  group('ProfileNotifier Sync & Resilience Tests', () {
    test('1. Kural 2 (Yerel Takma Ad Göçü): Bulutta ad yok ama yerelde varsa sunucuya yüklenir', () async {
      final fakeRepo = FakeProfileRepository(initialNickname: 'YerelOyuncu');
      final fakeApi = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'user_mig',
          nickname: null, // Bulutta henüz takma ad yok
          coins: 100,
        )
        ..updateResult = const ProfileUpdateSuccess('YerelOyuncu');

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      // syncWithServer'ın bitmesini bekle
      await container.read(profileProvider.notifier).syncWithServer();

      expect(fakeApi.updateNicknameCallCount, 1);
      expect(fakeApi.lastUpdatedNickname, 'YerelOyuncu');
      expect(container.read(profileProvider).nickname, 'YerelOyuncu');
      expect(await fakeRepo.isNicknameSyncPending(), false);
    });

    test('2. Kural 2: Bulutta takma ad varsa buluttaki esas alınır ve yerel güncellenir', () async {
      final fakeRepo = FakeProfileRepository(initialNickname: 'EskiYerelAd');
      final fakeApi = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'user_google',
          nickname: 'BuluttanGelenAd',
          coins: 250,
        );

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      await container.read(profileProvider.notifier).syncWithServer();

      final state = container.read(profileProvider);
      expect(state.nickname, 'BuluttanGelenAd');
      expect(state.coins, 250);
      expect(await fakeRepo.getNickname(), 'BuluttanGelenAd');
      expect(await fakeRepo.getCoins(), 250);
    });

    test('3. Kural 3 (Çevrimdışı Dayanıklılık): setNickname ağ hatasında yerel adı kaydeder ve pending işaretler', () async {
      final fakeRepo = FakeProfileRepository();
      final fakeApi = FakeProfileApiClient()
        ..updateResult = const ProfileUpdateNetworkError('No connection');

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      // Ağ hatası olsa bile oyun engellenmez, yerelde geçerli olur
      await container.read(profileProvider.notifier).setNickname('CevrimdisiAd');

      expect(container.read(profileProvider).nickname, 'CevrimdisiAd');
      expect(await fakeRepo.getNickname(), 'CevrimdisiAd');
      expect(await fakeRepo.isNicknameSyncPending(), true);

      // Daha sonra internet gelip retryPendingNicknameSync çağrıldığında sunucuya gider
      fakeApi.updateResult = const ProfileUpdateSuccess('CevrimdisiAd');
      await container.read(profileProvider.notifier).retryPendingNicknameSync();

      expect(await fakeRepo.isNicknameSyncPending(), false);
    });

    test('4. Kural 3: setNickname sunucudan 400 (geçersiz ad) alırsa pending işaretini temizler ve hata fırlatır', () async {
      final fakeRepo = FakeProfileRepository();
      final fakeApi = FakeProfileApiClient()
        ..updateResult = const ProfileUpdateInvalidNickname('Uygunsuz sözcük içeriyor');

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      await expectLater(
        () => container.read(profileProvider.notifier).setNickname('YasakAd'),
        throwsA(isA<Exception>()),
      );

      expect(await fakeRepo.isNicknameSyncPending(), false);
      expect(container.read(profileProvider).syncError, 'Uygunsuz sözcük içeriyor');
    });

    test('5. Kural 5: updateCoins mutlak bakiye üzerine yazar (toplamaz)', () async {
      final fakeRepo = FakeProfileRepository(initialCoins: 100);
      final fakeApi = FakeProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );

      expect(container.read(profileProvider).coins, 100);

      await container.read(profileProvider.notifier).updateCoins(160);
      expect(container.read(profileProvider).coins, 160);
      expect(await fakeRepo.getCoins(), 160);

      // Tekrar çağrıldığında yine mutlak değeri alır
      await container.read(profileProvider.notifier).updateCoins(130);
      expect(container.read(profileProvider).coins, 130);
      expect(await fakeRepo.getCoins(), 130);
    });
  });
}
