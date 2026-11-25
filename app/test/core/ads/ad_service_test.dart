import 'package:app/core/ads/ad_providers.dart';
import 'package:app/core/ads/ad_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  group('AdService & AdConsentNotifier', () {
    test('kill-switch kapalıyken AdConsentNotifier initialize çağırmaz', () async {
      final fakeService = FakeAdService();
      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeService),
          adConsentProvider.overrideWith(
            () => AdConsentNotifier(isAdsEnabledOverride: () => false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(adConsentProvider.notifier).initialize();
      await container.read(adConsentProvider.notifier).showPrivacyOptionsForm();

      expect(fakeService.initializeCallCount, 0);
      expect(fakeService.showPrivacyOptionsCallCount, 0);
      expect(container.read(adConsentProvider).isSdkInitialized, isFalse);
    });

    test('reklamlar etkinken AdConsentNotifier tek sefer başlatır', () async {
      final fakeService = FakeAdService(
        initialConsentState: const AdConsentState(
          isConsentChecked: true,
          canRequestAds: true,
          isSdkInitialized: true,
          privacyOptionsStatus: AdConsentPrivacyStatus.required,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          adServiceProvider.overrideWithValue(fakeService),
          adConsentProvider.overrideWith(
            () => AdConsentNotifier(isAdsEnabledOverride: () => true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(adConsentProvider.notifier).initialize();
      await container.read(adConsentProvider.notifier).initialize();

      expect(fakeService.initializeCallCount, 1);
      final state = container.read(adConsentProvider);
      expect(state.isConsentChecked, isTrue);
      expect(state.canRequestAds, isTrue);
      expect(state.isSdkInitialized, isTrue);
      expect(state.privacyOptionsStatus, AdConsentPrivacyStatus.required);
    });

    test('GoogleMobileAdsService UMP sırasını ve RequestConfiguration değerlerini uygular', () async {
      final callOrder = <String>[];
      RequestConfiguration? capturedConfig;

      final service = GoogleMobileAdsService(
        isAdsEnabled: () => true,
        updateRequestConfig: (config) async {
          callOrder.add('updateRequestConfig');
          capturedConfig = config;
        },
        requestConsentInfoUpdate: (params) async {
          callOrder.add('requestConsentInfoUpdate');
        },
        loadAndShowConsentFormIfRequired: () async {
          callOrder.add('loadAndShowConsentFormIfRequired');
        },
        canRequestAds: () async {
          callOrder.add('canRequestAds');
          return true;
        },
        getPrivacyOptionsStatus: () async {
          callOrder.add('getPrivacyOptionsStatus');
          return PrivacyOptionsRequirementStatus.required;
        },
        initializeMobileAds: () async {
          callOrder.add('initializeMobileAds');
        },
      );

      final result = await service.initialize();

      expect(callOrder, [
        'updateRequestConfig',
        'requestConsentInfoUpdate',
        'loadAndShowConsentFormIfRequired',
        'canRequestAds',
        'getPrivacyOptionsStatus',
        'initializeMobileAds',
      ]);
      expect(capturedConfig?.maxAdContentRating, MaxAdContentRating.t);
      // ignore: deprecated_member_use
      expect(capturedConfig?.tagForChildDirectedTreatment, TagForChildDirectedTreatment.no);
      // ignore: deprecated_member_use
      expect(capturedConfig?.tagForUnderAgeOfConsent, TagForUnderAgeOfConsent.no);
      expect(result.isSdkInitialized, isTrue);
      expect(result.privacyOptionsStatus, AdConsentPrivacyStatus.required);
    });

    test('canRequestAds false ise MobileAds.initialize çağrılmaz', () async {
      var sdkInitCalled = false;
      final service = GoogleMobileAdsService(
        isAdsEnabled: () => true,
        updateRequestConfig: (_) async {},
        requestConsentInfoUpdate: (_) async {},
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => false,
        getPrivacyOptionsStatus: () async =>
            PrivacyOptionsRequirementStatus.notRequired,
        initializeMobileAds: () async {
          sdkInitCalled = true;
        },
      );

      final result = await service.initialize();

      expect(sdkInitCalled, isFalse);
      expect(result.isSdkInitialized, isFalse);
      expect(result.canRequestAds, isFalse);
      expect(result.privacyOptionsStatus, AdConsentPrivacyStatus.notRequired);
    });

    test('UMP hata verirse initialize sessizce tamamlanır', () async {
      var sdkInitCalled = false;
      final service = GoogleMobileAdsService(
        isAdsEnabled: () => true,
        updateRequestConfig: (_) async {},
        requestConsentInfoUpdate: (_) async => throw Exception('ump error'),
        loadAndShowConsentFormIfRequired: () async {},
        canRequestAds: () async => true,
        getPrivacyOptionsStatus: () async =>
            PrivacyOptionsRequirementStatus.unknown,
        initializeMobileAds: () async {
          sdkInitCalled = true;
        },
      );

      final result = await service.initialize();

      expect(sdkInitCalled, isFalse);
      expect(result.isConsentChecked, isTrue);
      expect(result.isSdkInitialized, isFalse);
    });
  });
}
