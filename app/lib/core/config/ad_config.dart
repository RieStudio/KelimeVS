import 'package:flutter/foundation.dart';

/// Çözümlenmiş reklam çalışma zamanı yapılandırması.
@immutable
class AdRuntimeConfig {
  final bool isAdsEnabled;
  final String bannerAdUnitId;
  final String rewardedAdUnitId;

  const AdRuntimeConfig({
    required this.isAdsEnabled,
    required this.bannerAdUnitId,
    required this.rewardedAdUnitId,
  });
}

/// Google AdMob reklam birimi kimlikleri ve kill-switch yapılandırması.
///
/// - Debug/Profile (`!kReleaseMode`): Daima Google test kimliklerini kullanır.
/// - Release (`kReleaseMode`): `--dart-define` ile verilen gerçek kimlikleri kullanır.
///   Gerçek kimlikler tanımlı değilse, test kimliği içeriyorsa veya
///   `ADMOB_ENABLED=false` ise reklamlar güvenle devre dışı bırakılır.
abstract final class AdConfig {
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/9214589741';
  static const String testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _googleTestPublisherPrefix = 'ca-app-pub-3940256099942544';

  /// Debug derlemelerinde test cihazı kimliklerini eklemek için yapılandırma noktası.
  static const List<String> testDeviceIds = <String>[];

  /// Banner reklamın gösterileceği MainShell sekme indeksleri
  /// (0: Ana Sayfa, 1: Sıralama, 2: Mağaza, 3: Profil).
  static const Set<int> bannerTabIndices = <int>{0, 1, 2, 3};

  /// Maç içi sabit banner yüksekliği (`AdSize.banner` = 320x50).
  static const double inMatchBannerHeight = 50.0;

  /// Maç içi banner ile `AnswerInputBar` arasındaki en az dokunma güvenlik boşluğu (px).
  static const double inMatchBannerBottomGap = 24.0;

  /// Klavye açıkken üst çubuk + oyuncu kartları + soru kartı + giriş alanı + okunabilir
  /// cevap geçmişi alanı korunduktan sonra maç içi banner'ın (50 + 24 = 74 px)
  /// sığabilmesi için gereken en düşük mantıksal ekran yüksekliği (dp).
  /// Hesap: ~354 dp sabit oyun alanı + ~270 dp klavye tahmini + 74 dp banner/boşluk + ~62 dp okunabilir alan = 760 dp.
  static const double inMatchBannerMinScreenHeight = 760.0;

  static const bool _envAdsEnabled = bool.fromEnvironment(
    'ADMOB_ENABLED',
    defaultValue: true,
  );

  static const String _envReleaseBannerId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: '',
  );

  static const String _envReleaseRewardedId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
    defaultValue: '',
  );

  /// Mevcut derleme modu ve `--dart-define` bayraklarına göre çözümlenmiş yapılandırma.
  static AdRuntimeConfig get current => resolve(
        isRelease: kReleaseMode,
        enabled: _envAdsEnabled,
        releaseBannerId: _envReleaseBannerId,
        releaseRewardedId: _envReleaseRewardedId,
      );

  static bool get isAdsEnabled => current.isAdsEnabled;
  static String get bannerAdUnitId => current.bannerAdUnitId;
  static String get rewardedAdUnitId => current.rewardedAdUnitId;

  /// Test edilebilir saf çözümleyici.
  @visibleForTesting
  static AdRuntimeConfig resolve({
    required bool isRelease,
    required bool enabled,
    required String releaseBannerId,
    required String releaseRewardedId,
  }) {
    if (!isRelease) {
      return const AdRuntimeConfig(
        isAdsEnabled: true,
        bannerAdUnitId: testBannerAdUnitId,
        rewardedAdUnitId: testRewardedAdUnitId,
      );
    }

    final banner = releaseBannerId.trim();
    final rewarded = releaseRewardedId.trim();

    if (!enabled ||
        banner.isEmpty ||
        rewarded.isEmpty ||
        _isTestAdUnitId(banner) ||
        _isTestAdUnitId(rewarded)) {
      return const AdRuntimeConfig(
        isAdsEnabled: false,
        bannerAdUnitId: '',
        rewardedAdUnitId: '',
      );
    }

    return AdRuntimeConfig(
      isAdsEnabled: true,
      bannerAdUnitId: banner,
      rewardedAdUnitId: rewarded,
    );
  }

  static bool _isTestAdUnitId(String id) {
    return id.startsWith(_googleTestPublisherPrefix);
  }
}
