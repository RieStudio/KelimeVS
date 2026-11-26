import 'package:app/core/ads/ad_providers.dart';
import 'package:app/core/ads/ad_rewards_api_client.dart';
import 'package:app/core/ads/ad_rewards_state.dart';
import 'package:app/core/ads/ad_service.dart';
import 'package:app/core/ads/pending_ad_claim_store.dart';
import 'package:app/core/ads/widgets/ad_banner_slot.dart';
import 'package:app/core/ads/widgets/rewarded_ad_button.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/coins_tab_view.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNetworkNotifier extends NetworkStatusNotifier {
  final NetworkStatus initialStatus;
  _FakeNetworkNotifier(this.initialStatus);

  @override
  NetworkState build() => NetworkState(status: initialStatus);
}

class _TestAdConsentNotifier extends AdConsentNotifier {
  final AdConsentState _state;
  _TestAdConsentNotifier(this._state) : super(isAdsEnabledOverride: () => true);

  @override
  AdConsentState build() => _state;
}

class _FakeProfileRepository implements ProfileRepository {
  int coins = 100;
  @override
  Future<String?> getNickname() async => 'TestUser';
  @override
  Future<void> setNickname(String nickname) async {}
  @override
  Future<bool> hasNickname() async => true;
  @override
  Future<bool> isNicknameSyncPending() async => false;
  @override
  Future<void> setNicknameSyncPending(bool pending) async {}
  @override
  Future<int> getCoins({int defaultCoins = 100}) async => coins;
  @override
  Future<void> setCoins(int coins) async {
    this.coins = coins;
  }

  @override
  Future<String> getEquippedFrame({String defaultFrame = 'classic'}) async =>
      defaultFrame;
  @override
  Future<void> setEquippedFrame(String frameId) async {}
  @override
  Future<UserStats> getStats({String? uid}) async => const UserStats();
  @override
  Future<void> setStats(String uid, UserStats stats) async {}
  @override
  Future<void> clear({String? uid}) async {}
}

class _FakeProfileNotifier extends ProfileNotifier {
  final ProfileState _initial;
  _FakeProfileNotifier(this._initial);

  @override
  ProfileState build() => _initial;
}

class _FakeAdRewardsApiClient implements AdRewardsApiClient {
  final List<({String type, String claimId})> calls = [];
  AdRewardClaimResult nextResult;

  _FakeAdRewardsApiClient(this.nextResult);

  @override
  Future<AdRewardClaimResult> claimReward({
    required String type,
    required String claimId,
  }) async {
    calls.add((type: type, claimId: claimId));
    return nextResult;
  }
}

class _InMemoryPendingStore implements PendingAdClaimStore {
  PendingAdClaim? saved;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    saved = null;
  }

  @override
  Future<PendingAdClaim?> load() async => saved;

  @override
  Future<void> save(PendingAdClaim claim) async {
    saved = claim;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdRewardsInfo & UserProfileModel parse', () {
    test('adRewards alanı yoksa varsayılan enabled=false döner', () {
      final profile = UserProfileModel.fromJson({
        'uid': 'u1',
        'nickname': 'Ali',
        'coins': 100,
      });
      expect(profile.adRewards.enabled, isFalse);
      expect(profile.adRewards.energy.cap, 0);
    });

    test('adRewards alanı varsa miktarlar ve kotalar doğru parse edilir', () {
      final profile = UserProfileModel.fromJson({
        'uid': 'u1',
        'nickname': 'Ali',
        'coins': 100,
        'adRewards': {
          'enabled': true,
          'energy': {'remaining': 2, 'cap': 3},
          'coins': {'remaining': 1, 'cap': 3},
          'nextClaimAtMs': 1700000060000,
          'energyAmount': 1,
          'coinsAmount': 15,
        },
      });
      expect(profile.adRewards.enabled, isTrue);
      expect(profile.adRewards.energy.remaining, 2);
      expect(profile.adRewards.energy.cap, 3);
      expect(profile.adRewards.coinsAmount, 15);
      expect(profile.adRewards.nextClaimAtMs, 1700000060000);
    });
  });

  group('AdBannerSlot görünürlük & maç rotası izolasyonu', () {
    Widget buildBannerHost({
      required FakeAdService adService,
      bool adsEnabled = true,
      bool isVisibleForTab = true,
      NetworkStatus network = NetworkStatus.online,
      AdConsentState consent = const AdConsentState(
        isConsentChecked: true,
        canRequestAds: true,
        isSdkInitialized: true,
      ),
    }) {
      return ProviderScope(
        key: UniqueKey(),
        overrides: [
          adServiceProvider.overrideWithValue(adService),
          networkStatusProvider.overrideWith(() => _FakeNetworkNotifier(network)),
          adConsentProvider.overrideWith(() => _TestAdConsentNotifier(consent)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const Center(child: Text('Ana Ekran')),
            bottomNavigationBar: AdBannerSlot(
              isVisibleForTab: isVisibleForTab,
              isAdsEnabledOverride: adsEnabled,
            ),
          ),
        ),
      );
    }

    testWidgets('banner yüklü ve çevrimiçiyken görünür', (tester) async {
      final fakeAd = FakeAdService(initialBannerLoaded: true);
      await tester.pumpWidget(buildBannerHost(adService: fakeAd));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ad_banner_slot_container')), findsOneWidget);
      expect(find.byKey(const Key('fake_banner_ad_widget')), findsOneWidget);
    });

    testWidgets('kill-switch kapalı, yüklenmedi veya çevrimdışı iken gizlidir',
        (tester) async {
      final fakeAd = FakeAdService(
        initialBannerLoaded: false,
        simulateBannerLoadSuccess: false,
      );
      await tester.pumpWidget(buildBannerHost(adService: fakeAd));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ad_banner_slot_container')), findsNothing);

      final loadedFakeAd = FakeAdService(initialBannerLoaded: true);
      await tester.pumpWidget(
        buildBannerHost(adService: loadedFakeAd, adsEnabled: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ad_banner_slot_container')), findsNothing);

      await tester.pumpWidget(
        buildBannerHost(adService: loadedFakeAd, network: NetworkStatus.offline),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ad_banner_slot_container')), findsNothing);
    });

    testWidgets('maç rotası Navigator ile açıldığında banner ağaçta görünmez',
        (tester) async {
      final fakeAd = FakeAdService(initialBannerLoaded: true);
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adServiceProvider.overrideWithValue(fakeAd),
            networkStatusProvider
                .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
            adConsentProvider.overrideWith(
              () => _TestAdConsentNotifier(
                const AdConsentState(
                  isConsentChecked: true,
                  canRequestAds: true,
                  isSdkInitialized: true,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(
              body: Center(child: Text('Ana Ekran')),
              bottomNavigationBar: AdBannerSlot(
                isVisibleForTab: true,
                isAdsEnabledOverride: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake_banner_ad_widget')), findsOneWidget);

      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            key: Key('mock_match_route'),
            body: Center(child: Text('Maç Ekranı')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mock_match_route')), findsOneWidget);
      expect(find.byKey(const Key('fake_banner_ad_widget')), findsNothing);
    });
  });

  group('AdRewardController & bekleyen talep akışı', () {
    test('ödül kazanıldığında claim gönderilir ve profil güncellenir', () async {
      final fakeAd = FakeAdService(
        rewardEarnedOnShow: true,
        initialRewardedStatus: AdRewardedLoadStatus.ready,
      );
      const updatedEnergy = EnergyState(enabled: true, current: 1, max: 5);
      final api = _FakeAdRewardsApiClient(
        const AdRewardClaimSuccess(
          type: 'energy',
          granted: true,
          alreadyProcessed: false,
          coins: 120,
          energy: updatedEnergy,
          remainingEnergy: 2,
          remainingCoins: 3,
          nextClaimAtMs: 9999999999999,
        ),
      );
      final pendingStore = _InMemoryPendingStore();
      final repo = _FakeProfileRepository();

      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeAd),
          adRewardsApiClientProvider.overrideWithValue(api),
          pendingAdClaimStoreProvider.overrideWithValue(pendingStore),
          profileRepositoryProvider.overrideWithValue(repo),
          networkStatusProvider
              .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(
              const ProfileState(
                nickname: 'Ali',
                coins: 120,
                isLoaded: true,
                energy: EnergyState(enabled: true, current: 0, max: 5),
                adRewards: AdRewardsInfo(
                  enabled: true,
                  energy: AdRewardQuota(remaining: 3, cap: 3),
                  coins: AdRewardQuota(remaining: 3, cap: 3),
                ),
              ),
            ),
          ),
          adRewardControllerProvider.overrideWith(
            () => AdRewardController(isAdsEnabledOverride: () => true),
          ),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('energy');

      expect(outcome.status, RewardedClaimOutcomeStatus.granted);
      expect(api.calls.length, 1);
      expect(api.calls.first.claimId.length, 24);
      expect(pendingStore.saved, isNull);
      expect(container.read(profileProvider).energy?.current, 1);
      expect(container.read(profileProvider).adRewards.energy.remaining, 2);
    });

    test('erken kapatmada claim gönderilmez', () async {
      final fakeAd = FakeAdService(
        rewardEarnedOnShow: false,
        initialRewardedStatus: AdRewardedLoadStatus.ready,
      );
      final api = _FakeAdRewardsApiClient(const AdRewardClaimAdsDisabled());
      final pendingStore = _InMemoryPendingStore();

      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeAd),
          adRewardsApiClientProvider.overrideWithValue(api),
          pendingAdClaimStoreProvider.overrideWithValue(pendingStore),
          networkStatusProvider
              .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
          adRewardControllerProvider.overrideWith(
            () => AdRewardController(isAdsEnabledOverride: () => true),
          ),
        ],
      );
      addTearDown(container.dispose);

      final outcome = await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('coins');

      expect(outcome.status, RewardedClaimOutcomeStatus.dismissed);
      expect(api.calls, isEmpty);
      expect(pendingStore.saved, isNull);
    });

    test('geçici ağ hatasında talep kalıcı saklanır ve açılışta aynı claimId ile yeniden denenir',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAd = FakeAdService(
        rewardEarnedOnShow: true,
        initialRewardedStatus: AdRewardedLoadStatus.ready,
      );
      final api = _FakeAdRewardsApiClient(const AdRewardClaimRetryableError());
      const store = SharedPreferencesPendingAdClaimStore();
      final repo = _FakeProfileRepository();

      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeAd),
          adRewardsApiClientProvider.overrideWithValue(api),
          pendingAdClaimStoreProvider.overrideWithValue(store),
          profileRepositoryProvider.overrideWithValue(repo),
          networkStatusProvider
              .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(
              const ProfileState(
                nickname: 'Ali',
                coins: 100,
                isLoaded: true,
                adRewards: AdRewardsInfo(
                  enabled: true,
                  energy: AdRewardQuota(remaining: 3, cap: 3),
                  coins: AdRewardQuota(remaining: 3, cap: 3),
                ),
              ),
            ),
          ),
          adRewardControllerProvider.overrideWith(
            () => AdRewardController(isAdsEnabledOverride: () => true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('coins');

      final savedClaim = await store.load();
      expect(savedClaim, isNotNull);
      final firstClaimId = savedClaim!.claimId;

      api.nextResult = const AdRewardClaimSuccess(
        type: 'coins',
        granted: true,
        alreadyProcessed: false,
        coins: 115,
        energy: EnergyState(enabled: true, current: 5, max: 5),
        remainingEnergy: 3,
        remainingCoins: 2,
      );

      await container
          .read(adRewardControllerProvider.notifier)
          .retryPendingClaim();

      expect(api.calls.length, 2);
      expect(api.calls[1].claimId, firstClaimId);
      expect(await store.load(), isNull);
      expect(container.read(profileProvider).coins, 115);
    });

    test('429/409/410 yanıtları doğru mesaj ve kalıcı temizlik üretir', () async {
      final fakeAd = FakeAdService(
        rewardEarnedOnShow: true,
        initialRewardedStatus: AdRewardedLoadStatus.ready,
      );
      final pendingStore = _InMemoryPendingStore();
      final api = _FakeAdRewardsApiClient(
        const AdRewardClaimTooSoon(retryAfterSeconds: 30),
      );
      final repo = _FakeProfileRepository();

      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeAd),
          adRewardsApiClientProvider.overrideWithValue(api),
          pendingAdClaimStoreProvider.overrideWithValue(pendingStore),
          profileRepositoryProvider.overrideWithValue(repo),
          networkStatusProvider
              .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(const ProfileState(isLoaded: true)),
          ),
          adRewardControllerProvider.overrideWith(
            () => AdRewardController(isAdsEnabledOverride: () => true),
          ),
        ],
      );
      addTearDown(container.dispose);

      var outcome = await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('coins');
      expect(outcome.message, AppStrings.adRewardTooSoon(30));
      expect(pendingStore.saved, isNull);

      api.nextResult = const AdRewardClaimEnergyFull();
      outcome = await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('energy');
      expect(outcome.message, AppStrings.adRewardEnergyFullError);

      api.nextResult = const AdRewardClaimAccountDeleted();
      outcome = await container
          .read(adRewardControllerProvider.notifier)
          .watchAndClaim('coins');
      expect(outcome.message, AppStrings.adRewardGenericError);
    });
  });

  group('Ödüllü Buton ve Ekran Widget Testleri', () {
    testWidgets('RewardedAdActionButton tüm durumları doğru gösterir',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RewardedAdActionButton(
                  label: AppStrings.adWatchForEnergy(1),
                  remaining: 2,
                  cap: 3,
                  isOnline: true,
                  loadStatus: AdRewardedLoadStatus.ready,
                ),
                RewardedAdActionButton(
                  label: AppStrings.adWatchForCoins(15),
                  remaining: 0,
                  cap: 3,
                  isOnline: true,
                  loadStatus: AdRewardedLoadStatus.ready,
                ),
                RewardedAdActionButton(
                  label: AppStrings.adWatchForCoins(15),
                  remaining: 3,
                  cap: 3,
                  isOnline: true,
                  loadStatus: AdRewardedLoadStatus.loading,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Reklam İzle · +1 Enerji'), findsOneWidget);
      expect(find.text('Bugün kalan: 2/3'), findsOneWidget);
      expect(find.text(AppStrings.adRewardLimitReached), findsOneWidget);
      expect(find.text(AppStrings.adRewardLoading), findsOneWidget);
    });

    testWidgets(
        'EnergyDepletedBottomSheet ve CoinsTabView adRewards.enabled=false iken reklam butonunu gizler',
        (tester) async {
      final fakeAd = FakeAdService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adServiceProvider.overrideWithValue(fakeAd),
            networkStatusProvider
                .overrideWith(() => _FakeNetworkNotifier(NetworkStatus.online)),
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(
                const ProfileState(
                  isLoaded: true,
                  adRewards: AdRewardsInfo.disabled(),
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: CoinsTabView()),
                  EnergyDepletedBottomSheet(
                    energy: EnergyState(enabled: true, current: 0, max: 5),
                    userCoins: 100,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('coins_tab_ad_reward_card')), findsNothing);
      expect(find.byKey(const Key('energy_sheet_watch_ad_button')), findsNothing);
    });
  });
}
