import 'package:app/core/config/ad_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdConfig.resolve', () {
    test('debug modunda daima Google test kimliklerini döner', () {
      final config = AdConfig.resolve(
        isRelease: false,
        enabled: false,
        releaseBannerId: '',
        releaseRewardedId: '',
      );

      expect(config.isAdsEnabled, isTrue);
      expect(config.bannerAdUnitId, AdConfig.testBannerAdUnitId);
      expect(config.rewardedAdUnitId, AdConfig.testRewardedAdUnitId);
    });

    test('release modunda kimlikler boşsa kill-switch devreye girer', () {
      final config = AdConfig.resolve(
        isRelease: true,
        enabled: true,
        releaseBannerId: '',
        releaseRewardedId: 'ca-app-pub-1111111111111111/2222222222',
      );

      expect(config.isAdsEnabled, isFalse);
      expect(config.bannerAdUnitId, isEmpty);
      expect(config.rewardedAdUnitId, isEmpty);
    });

    test('release modunda test kimliği verilirse kill-switch devreye girer', () {
      final config = AdConfig.resolve(
        isRelease: true,
        enabled: true,
        releaseBannerId: AdConfig.testBannerAdUnitId,
        releaseRewardedId: 'ca-app-pub-1111111111111111/2222222222',
      );

      expect(config.isAdsEnabled, isFalse);
      expect(config.bannerAdUnitId, isEmpty);
      expect(config.rewardedAdUnitId, isEmpty);
    });

    test('release modunda ADMOB_ENABLED=false ise reklamlar kapalı kalır', () {
      final config = AdConfig.resolve(
        isRelease: true,
        enabled: false,
        releaseBannerId: 'ca-app-pub-1111111111111111/1111111111',
        releaseRewardedId: 'ca-app-pub-1111111111111111/2222222222',
      );

      expect(config.isAdsEnabled, isFalse);
      expect(config.bannerAdUnitId, isEmpty);
      expect(config.rewardedAdUnitId, isEmpty);
    });

    test('release modunda gerçek kimlikler ve enabled=true ile açılır', () {
      const realBanner = 'ca-app-pub-1111111111111111/1111111111';
      const realRewarded = 'ca-app-pub-1111111111111111/2222222222';

      final config = AdConfig.resolve(
        isRelease: true,
        enabled: true,
        releaseBannerId: realBanner,
        releaseRewardedId: realRewarded,
      );

      expect(config.isAdsEnabled, isTrue);
      expect(config.bannerAdUnitId, realBanner);
      expect(config.rewardedAdUnitId, realRewarded);
    });

    test('resolveEnabledFlag hem string hem boolean ADMOB_ENABLED değerlerini doğru okur', () {
      expect(
        AdConfig.resolveEnabledFlag(boolValue: true, stringValue: 'true'),
        isTrue,
      );
      expect(
        AdConfig.resolveEnabledFlag(boolValue: false, stringValue: 'true'),
        isTrue,
      );
      expect(
        AdConfig.resolveEnabledFlag(boolValue: true, stringValue: 'false'),
        isFalse,
      );
      expect(
        AdConfig.resolveEnabledFlag(boolValue: false, stringValue: ''),
        isFalse,
      );
    });

    test('release modunda ödüllü kimlik de test kimliği ise kilit devreye girer', () {
      final config = AdConfig.resolve(
        isRelease: true,
        enabled: true,
        releaseBannerId: 'ca-app-pub-1111111111111111/1111111111',
        releaseRewardedId: AdConfig.testRewardedAdUnitId,
      );

      expect(config.isAdsEnabled, isFalse);
      expect(config.bannerAdUnitId, isEmpty);
      expect(config.rewardedAdUnitId, isEmpty);
    });
  });
}
