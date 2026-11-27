import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';

/// UMP gizlilik seçenekleri gereksinim durumu.
enum AdConsentPrivacyStatus {
  unknown,
  notRequired,
  required,
}

/// Ödüllü reklam yükleme durumu.
enum AdRewardedLoadStatus {
  idle,
  loading,
  ready,
  failed,
}

/// Reklam onayı ve SDK başlatma durumu.
@immutable
class AdConsentState {
  final bool isConsentChecked;
  final bool canRequestAds;
  final bool isSdkInitialized;
  final AdConsentPrivacyStatus privacyOptionsStatus;

  const AdConsentState({
    this.isConsentChecked = false,
    this.canRequestAds = false,
    this.isSdkInitialized = false,
    this.privacyOptionsStatus = AdConsentPrivacyStatus.unknown,
  });

  AdConsentState copyWith({
    bool? isConsentChecked,
    bool? canRequestAds,
    bool? isSdkInitialized,
    AdConsentPrivacyStatus? privacyOptionsStatus,
  }) {
    return AdConsentState(
      isConsentChecked: isConsentChecked ?? this.isConsentChecked,
      canRequestAds: canRequestAds ?? this.canRequestAds,
      isSdkInitialized: isSdkInitialized ?? this.isSdkInitialized,
      privacyOptionsStatus: privacyOptionsStatus ?? this.privacyOptionsStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdConsentState &&
          runtimeType == other.runtimeType &&
          isConsentChecked == other.isConsentChecked &&
          canRequestAds == other.canRequestAds &&
          isSdkInitialized == other.isSdkInitialized &&
          privacyOptionsStatus == other.privacyOptionsStatus;

  @override
  int get hashCode => Object.hash(
        isConsentChecked,
        canRequestAds,
        isSdkInitialized,
        privacyOptionsStatus,
      );
}

/// Reklam SDK ve UMP onay yaşam döngüsü soyutlaması.
abstract interface class AdService {
  ValueListenable<bool> get isBannerLoadedListenable;
  ValueListenable<bool> get isInMatchBannerLoadedListenable;
  ValueListenable<AdRewardedLoadStatus> get rewardedStatusListenable;

  /// UMP onay akışını çalıştırır ve izin varsa MobileAds SDK'yı başlatır.
  Future<AdConsentState> initialize();

  /// Ayarlar ekranından gizlilik seçenekleri formunu yeniden açar.
  Future<AdConsentPrivacyStatus> showPrivacyOptionsForm();

  /// Paylaşımlı adaptive banner'ı yükler/önbellekler (MainShell).
  Future<void> loadBanner({required String adUnitId, required int width});

  /// Banner widget'ını döndürür (yüklü değilse null).
  Widget? buildBannerWidget();

  /// Banner kaynağını serbest bırakır.
  Future<void> disposeBanner();

  /// Maç içi sabit `AdSize.banner` (320x50) reklamını ön yükler (MainShell'den bağımsız).
  Future<void> loadInMatchBanner({required String adUnitId});

  /// Maç içi banner widget'ını döndürür (yüklü değilse null).
  Widget? buildInMatchBannerWidget();

  /// Maç içi banner kaynağını serbest bırakır.
  Future<void> disposeInMatchBanner();

  /// Ödüllü reklamı ön yükler (10 sn zaman aşımı + üstel geri çekilme).
  Future<void> preloadRewarded({required String adUnitId});

  /// Ödüllü reklamı gösterir; yalnızca ödül kazanılırsa `true` döner.
  Future<bool> showRewarded();
}

void _adLog(String message) {
  debugPrint('[ADS] $message');
}

String _maskAdId(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) return 'empty';
  final tail =
      trimmed.length >= 4 ? trimmed.substring(trimmed.length - 4) : trimmed;
  return 'len=${trimmed.length},tail=***$tail';
}

/// Gerçek `google_mobile_ads` ve UMP implementasyonu.
class GoogleMobileAdsService implements AdService {
  static const Duration _umpTimeout = Duration(seconds: 8);
  static const Duration _rewardedLoadTimeout = Duration(seconds: 30);
  static const int _maxBackoffSeconds = 32;

  final bool Function() _isAdsEnabled;
  final Future<void> Function(RequestConfiguration config) _updateRequestConfig;
  final Future<void> Function(ConsentRequestParameters params)
      _requestConsentInfoUpdate;
  final Future<void> Function() _loadAndShowConsentFormIfRequired;
  final Future<bool> Function() _canRequestAds;
  final Future<PrivacyOptionsRequirementStatus> Function()
      _getPrivacyOptionsStatus;
  final Future<void> Function() _initializeMobileAds;
  final Future<void> Function() _showPrivacyOptionsForm;

  final ValueNotifier<bool> _isBannerLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isInMatchBannerLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<AdRewardedLoadStatus> _rewardedStatus =
      ValueNotifier<AdRewardedLoadStatus>(AdRewardedLoadStatus.idle);

  BannerAd? _bannerAd;
  int? _bannerWidth;
  bool _isBannerLoading = false;
  BannerAd? _inMatchBannerAd;
  bool _isInMatchBannerLoading = false;
  bool _sdkReady = false;

  RewardedAd? _rewardedAd;
  bool _isRewardedLoading = false;
  String? _lastRewardedAdUnitId;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  GoogleMobileAdsService({
    bool Function()? isAdsEnabled,
    Future<void> Function(RequestConfiguration config)? updateRequestConfig,
    Future<void> Function(ConsentRequestParameters params)?
        requestConsentInfoUpdate,
    Future<void> Function()? loadAndShowConsentFormIfRequired,
    Future<bool> Function()? canRequestAds,
    Future<PrivacyOptionsRequirementStatus> Function()? getPrivacyOptionsStatus,
    Future<void> Function()? initializeMobileAds,
    Future<void> Function()? showPrivacyOptionsForm,
  })  : _isAdsEnabled = isAdsEnabled ?? (() => AdConfig.isAdsEnabled),
        _updateRequestConfig =
            updateRequestConfig ?? MobileAds.instance.updateRequestConfiguration,
        _requestConsentInfoUpdate =
            requestConsentInfoUpdate ?? _defaultRequestConsentInfoUpdate,
        _loadAndShowConsentFormIfRequired =
            loadAndShowConsentFormIfRequired ??
                _defaultLoadAndShowConsentFormIfRequired,
        _canRequestAds = canRequestAds ?? ConsentInformation.instance.canRequestAds,
        _getPrivacyOptionsStatus = getPrivacyOptionsStatus ??
            ConsentInformation.instance.getPrivacyOptionsRequirementStatus,
        _initializeMobileAds =
            initializeMobileAds ?? _defaultInitializeMobileAds,
        _showPrivacyOptionsForm =
            showPrivacyOptionsForm ?? _defaultShowPrivacyOptionsForm;

  static Future<void> _defaultInitializeMobileAds() async {
    final status = await MobileAds.instance.initialize();
    final adapters = status.adapterStatuses.entries
        .map((e) => '${e.key}:${e.value.state.name}')
        .join(', ');
    _adLog('MobileAds.initialize done adapters=[$adapters]');
  }

  @override
  ValueListenable<bool> get isBannerLoadedListenable => _isBannerLoaded;

  @override
  ValueListenable<bool> get isInMatchBannerLoadedListenable =>
      _isInMatchBannerLoaded;

  @override
  ValueListenable<AdRewardedLoadStatus> get rewardedStatusListenable =>
      _rewardedStatus;

  static Future<void> _defaultRequestConsentInfoUpdate(
    ConsentRequestParameters params,
  ) {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        if (!completer.isCompleted) completer.complete();
      },
      (FormError error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    return completer.future;
  }

  static Future<void> _defaultLoadAndShowConsentFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
      if (!completer.isCompleted) {
        if (error != null) {
          completer.completeError(error);
        } else {
          completer.complete();
        }
      }
    });
    return completer.future;
  }

  static Future<void> _defaultShowPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (!completer.isCompleted) {
        if (error != null) {
          completer.completeError(error);
        } else {
          completer.complete();
        }
      }
    });
    return completer.future;
  }

  @override
  Future<AdConsentState> initialize() async {
    final enabled = _isAdsEnabled();
    _adLog(
      'initialize start isRelease=$kReleaseMode isAdsEnabled=$enabled '
      'bannerId=(${_maskAdId(AdConfig.bannerAdUnitId)}) '
      'rewardedId=(${_maskAdId(AdConfig.rewardedAdUnitId)})',
    );
    if (!enabled) {
      _adLog('initialize skipped: isAdsEnabled=false');
      return const AdConsentState();
    }

    var canRequest = false;
    var privacyStatus = AdConsentPrivacyStatus.unknown;
    var sdkInitialized = false;

    // 1. İstek yapılandırması
    try {
      await _updateRequestConfig(
        RequestConfiguration(
          maxAdContentRating: MaxAdContentRating.t,
          // ignore: deprecated_member_use
          tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
          // ignore: deprecated_member_use
          tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.no,
          testDeviceIds: !kReleaseMode && AdConfig.testDeviceIds.isNotEmpty
              ? AdConfig.testDeviceIds
              : null,
        ),
      );
    } catch (e) {
      _adLog('RequestConfiguration update warning: $e');
    }

    // 2. UMP Onay akışı (Hata/timeout durumunda canRequestAds ASLA true zorlanmaz;
    //    yalnızca önceki oturumdan önbellekteki gerçek canRequestAds() değerine bakılır.)
    try {
      await _requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      ).timeout(_umpTimeout);

      await _loadAndShowConsentFormIfRequired().timeout(_umpTimeout);
    } catch (e) {
      _adLog('UMP update/form warning (checking cached canRequestAds): $e');
    }

    try {
      canRequest = await _canRequestAds().timeout(_umpTimeout);
      final rawPrivacyStatus =
          await _getPrivacyOptionsStatus().timeout(_umpTimeout);
      privacyStatus = _mapPrivacyStatus(rawPrivacyStatus);
      _adLog('UMP done canRequestAds=$canRequest privacyStatus=$privacyStatus');
    } catch (e) {
      _adLog('UMP status query failed (canRequestAds=false): $e');
      canRequest = false;
    }

    // 3. MobileAds SDK Başlatma (Yalnızca canRequestAds == true ise)
    if (canRequest) {
      try {
        await _initializeMobileAds();
        sdkInitialized = true;
        _sdkReady = true;
      } catch (e) {
        _adLog('MobileAds.initialize failed: $e');
      }
    } else {
      _adLog('MobileAds.initialize skipped: canRequestAds=false');
    }

    _adLog(
      'initialize end isConsentChecked=true canRequestAds=$canRequest '
      'isSdkInitialized=$sdkInitialized privacyStatus=$privacyStatus',
    );
    return AdConsentState(
      isConsentChecked: true,
      canRequestAds: canRequest,
      isSdkInitialized: sdkInitialized,
      privacyOptionsStatus: privacyStatus,
    );
  }

  @override
  Future<AdConsentPrivacyStatus> showPrivacyOptionsForm() async {
    if (!_isAdsEnabled()) {
      return AdConsentPrivacyStatus.unknown;
    }

    try {
      await _showPrivacyOptionsForm().timeout(_umpTimeout);
      final rawStatus = await _getPrivacyOptionsStatus().timeout(_umpTimeout);
      return _mapPrivacyStatus(rawStatus);
    } catch (_) {
      return AdConsentPrivacyStatus.unknown;
    }
  }

  @override
  Future<void> loadBanner({required String adUnitId, required int width}) async {
    if (!_isAdsEnabled() || !_sdkReady || adUnitId.isEmpty || width <= 0) {
      _adLog(
        'loadBanner skipped: enabled=${_isAdsEnabled()} sdkReady=$_sdkReady '
        'id=(${_maskAdId(adUnitId)}) width=$width',
      );
      return;
    }
    if (_bannerAd != null && _bannerWidth == width && _isBannerLoaded.value) {
      return;
    }
    if (_isBannerLoading && _bannerWidth == width) {
      return;
    }

    _isBannerLoading = true;
    _bannerWidth = width;

    try {
      final size =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (size == null) {
        _isBannerLoading = false;
        return;
      }

      await _bannerAd?.dispose();
      _bannerAd = null;
      _isBannerLoaded.value = false;

      final banner = BannerAd(
        adUnitId: adUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            final loaded = ad as BannerAd;
            _adLog(
              'banner onAdLoaded (${loaded.size.width}x${loaded.size.height})',
            );
            _isBannerLoading = false;
            _bannerAd = loaded;
            _isBannerLoaded.value = true;
          },
          onAdFailedToLoad: (ad, error) {
            _adLog(
              'banner onAdFailedToLoad code=${error.code} '
              'domain=${error.domain} msg=${error.message}',
            );
            ad.dispose();
            _isBannerLoading = false;
            _bannerAd = null;
            _isBannerLoaded.value = false;
          },
        ),
      );
      _bannerAd = banner;
      await banner.load();
    } catch (e) {
      _adLog('banner load exception: $e');
      _isBannerLoading = false;
      _bannerAd = null;
      _isBannerLoaded.value = false;
    }
  }

  @override
  Widget? buildBannerWidget() {
    final ad = _bannerAd;
    if (ad == null || !_isBannerLoaded.value) return null;
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }

  @override
  Future<void> disposeBanner() async {
    _isBannerLoading = false;
    _bannerWidth = null;
    _isBannerLoaded.value = false;
    final ad = _bannerAd;
    _bannerAd = null;
    await ad?.dispose();
  }

  @override
  Future<void> loadInMatchBanner({required String adUnitId}) async {
    if (!_isAdsEnabled() || !_sdkReady || adUnitId.isEmpty) {
      _adLog(
        'loadInMatchBanner skipped: enabled=${_isAdsEnabled()} '
        'sdkReady=$_sdkReady id=(${_maskAdId(adUnitId)})',
      );
      return;
    }
    if ((_inMatchBannerAd != null && _isInMatchBannerLoaded.value) ||
        _isInMatchBannerLoading) {
      return;
    }

    _isInMatchBannerLoading = true;
    try {
      await _inMatchBannerAd?.dispose();
      _inMatchBannerAd = null;
      _isInMatchBannerLoaded.value = false;

      final banner = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _adLog('inMatchBanner onAdLoaded');
            _isInMatchBannerLoading = false;
            _inMatchBannerAd = ad as BannerAd;
            _isInMatchBannerLoaded.value = true;
          },
          onAdFailedToLoad: (ad, error) {
            _adLog(
              'inMatchBanner onAdFailedToLoad code=${error.code} '
              'domain=${error.domain} msg=${error.message}',
            );
            ad.dispose();
            _isInMatchBannerLoading = false;
            _inMatchBannerAd = null;
            _isInMatchBannerLoaded.value = false;
          },
        ),
      );
      _inMatchBannerAd = banner;
      await banner.load();
    } catch (e) {
      _adLog('inMatchBanner load exception: $e');
      _isInMatchBannerLoading = false;
      _inMatchBannerAd = null;
      _isInMatchBannerLoaded.value = false;
    }
  }

  @override
  Widget? buildInMatchBannerWidget() {
    final ad = _inMatchBannerAd;
    if (ad == null || !_isInMatchBannerLoaded.value) return null;
    return SizedBox(
      width: AdSize.banner.width.toDouble(),
      height: AdSize.banner.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }

  @override
  Future<void> disposeInMatchBanner() async {
    _isInMatchBannerLoading = false;
    _isInMatchBannerLoaded.value = false;
    final ad = _inMatchBannerAd;
    _inMatchBannerAd = null;
    await ad?.dispose();
  }

  @override
  Future<void> preloadRewarded({required String adUnitId}) async {
    if (!_isAdsEnabled() || !_sdkReady || adUnitId.isEmpty) {
      _adLog(
        'preloadRewarded skipped: enabled=${_isAdsEnabled()} '
        'sdkReady=$_sdkReady id=(${_maskAdId(adUnitId)})',
      );
      return;
    }
    _lastRewardedAdUnitId = adUnitId;
    if (_rewardedAd != null) {
      _rewardedStatus.value = AdRewardedLoadStatus.ready;
      return;
    }
    if (_isRewardedLoading) {
      _adLog('preloadRewarded skipped: alreadyLoading');
      return;
    }

    _adLog('preloadRewarded start id=(${_maskAdId(adUnitId)})');
    _retryTimer?.cancel();
    _isRewardedLoading = true;
    _rewardedStatus.value = AdRewardedLoadStatus.loading;

    final completer = Completer<void>();
    Timer? timeoutTimer;
    timeoutTimer = Timer(_rewardedLoadTimeout, () {
      if (!completer.isCompleted) {
        _adLog('rewarded load timeout (10s)');
        _isRewardedLoading = false;
        _rewardedStatus.value = AdRewardedLoadStatus.failed;
        _scheduleRewardedRetry();
        completer.complete();
      }
    });

    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _adLog('rewarded onAdLoaded');
            timeoutTimer?.cancel();
            _isRewardedLoading = false;
            _retryAttempt = 0;
            _rewardedAd = ad;
            _rewardedStatus.value = AdRewardedLoadStatus.ready;
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            _adLog(
              'rewarded onAdFailedToLoad code=${error.code} '
              'domain=${error.domain} msg=${error.message}',
            );
            timeoutTimer?.cancel();
            _isRewardedLoading = false;
            _rewardedAd = null;
            _rewardedStatus.value = AdRewardedLoadStatus.failed;
            _scheduleRewardedRetry();
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
    } catch (e) {
      _adLog('rewarded load exception: $e');
      timeoutTimer.cancel();
      _isRewardedLoading = false;
      _rewardedAd = null;
      _rewardedStatus.value = AdRewardedLoadStatus.failed;
      _scheduleRewardedRetry();
      if (!completer.isCompleted) completer.complete();
    }

    return completer.future;
  }

  void _scheduleRewardedRetry() {
    final unitId = _lastRewardedAdUnitId;
    if (unitId == null || unitId.isEmpty || !_isAdsEnabled() || !_sdkReady) {
      return;
    }
    _retryTimer?.cancel();
    final delaySec = (2 << _retryAttempt).clamp(2, _maxBackoffSeconds);
    _retryAttempt = (_retryAttempt + 1).clamp(0, 5);
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      unawaited(preloadRewarded(adUnitId: unitId));
    });
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewardedAd;
    if (ad == null) {
      return false;
    }

    _rewardedAd = null;
    _rewardedStatus.value = AdRewardedLoadStatus.idle;

    final completer = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
        final unitId = _lastRewardedAdUnitId;
        if (unitId != null && unitId.isNotEmpty) {
          unawaited(preloadRewarded(adUnitId: unitId));
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
        final unitId = _lastRewardedAdUnitId;
        if (unitId != null && unitId.isNotEmpty) {
          unawaited(preloadRewarded(adUnitId: unitId));
        }
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
        },
      );
    } catch (_) {
      ad.dispose();
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future;
  }

  static AdConsentPrivacyStatus _mapPrivacyStatus(
    PrivacyOptionsRequirementStatus status,
  ) {
    switch (status) {
      case PrivacyOptionsRequirementStatus.required:
        return AdConsentPrivacyStatus.required;
      case PrivacyOptionsRequirementStatus.notRequired:
        return AdConsentPrivacyStatus.notRequired;
      case PrivacyOptionsRequirementStatus.unknown:
        return AdConsentPrivacyStatus.unknown;
    }
  }
}

/// Testler ve geliştirici galerisi için sahte [AdService].
class FakeAdService implements AdService {
  final AdConsentState initialConsentState;
  final AdConsentPrivacyStatus privacyStatusAfterForm;
  bool rewardEarnedOnShow;
  bool simulateBannerLoadSuccess;

  final ValueNotifier<bool> _isBannerLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isInMatchBannerLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<AdRewardedLoadStatus> _rewardedStatus =
      ValueNotifier<AdRewardedLoadStatus>(AdRewardedLoadStatus.idle);

  int initializeCallCount = 0;
  int showPrivacyOptionsCallCount = 0;
  int loadBannerCallCount = 0;
  int loadInMatchBannerCallCount = 0;
  int disposeInMatchBannerCallCount = 0;
  int preloadRewardedCallCount = 0;
  int showRewardedCallCount = 0;
  final List<String> callLog = <String>[];

  FakeAdService({
    this.initialConsentState = const AdConsentState(
      isConsentChecked: true,
      canRequestAds: true,
      isSdkInitialized: true,
      privacyOptionsStatus: AdConsentPrivacyStatus.notRequired,
    ),
    this.privacyStatusAfterForm = AdConsentPrivacyStatus.required,
    this.rewardEarnedOnShow = true,
    this.simulateBannerLoadSuccess = true,
    bool initialBannerLoaded = false,
    bool initialInMatchBannerLoaded = false,
    AdRewardedLoadStatus initialRewardedStatus = AdRewardedLoadStatus.ready,
  }) {
    _isBannerLoaded.value = initialBannerLoaded;
    _isInMatchBannerLoaded.value = initialInMatchBannerLoaded;
    _rewardedStatus.value = initialRewardedStatus;
  }

  @override
  ValueListenable<bool> get isBannerLoadedListenable => _isBannerLoaded;

  @override
  ValueListenable<bool> get isInMatchBannerLoadedListenable =>
      _isInMatchBannerLoaded;

  @override
  ValueListenable<AdRewardedLoadStatus> get rewardedStatusListenable =>
      _rewardedStatus;

  void setBannerLoaded(bool value) {
    _isBannerLoaded.value = value;
  }

  void setInMatchBannerLoaded(bool value) {
    _isInMatchBannerLoaded.value = value;
  }

  void setRewardedStatus(AdRewardedLoadStatus status) {
    _rewardedStatus.value = status;
  }

  @override
  Future<AdConsentState> initialize() async {
    initializeCallCount++;
    callLog.add('initialize');
    return initialConsentState;
  }

  @override
  Future<AdConsentPrivacyStatus> showPrivacyOptionsForm() async {
    showPrivacyOptionsCallCount++;
    callLog.add('showPrivacyOptionsForm');
    return privacyStatusAfterForm;
  }

  @override
  Future<void> loadBanner({required String adUnitId, required int width}) async {
    loadBannerCallCount++;
    callLog.add('loadBanner:$adUnitId:$width');
    _isBannerLoaded.value = simulateBannerLoadSuccess;
  }

  @override
  Widget? buildBannerWidget() {
    if (!_isBannerLoaded.value) return null;
    return Container(
      key: const Key('fake_banner_ad_widget'),
      height: 50,
      alignment: Alignment.center,
      child: const Text('TEST BANNER'),
    );
  }

  @override
  Future<void> disposeBanner() async {
    callLog.add('disposeBanner');
    _isBannerLoaded.value = false;
  }

  @override
  Future<void> loadInMatchBanner({required String adUnitId}) async {
    loadInMatchBannerCallCount++;
    callLog.add('loadInMatchBanner:$adUnitId');
    _isInMatchBannerLoaded.value = simulateBannerLoadSuccess;
  }

  @override
  Widget? buildInMatchBannerWidget() {
    if (!_isInMatchBannerLoaded.value) return null;
    return Container(
      key: const Key('fake_in_match_banner_ad_widget'),
      width: 320,
      height: 50,
      alignment: Alignment.center,
      child: const Text('TEST IN-MATCH BANNER'),
    );
  }

  @override
  Future<void> disposeInMatchBanner() async {
    disposeInMatchBannerCallCount++;
    callLog.add('disposeInMatchBanner');
    _isInMatchBannerLoaded.value = false;
  }

  @override
  Future<void> preloadRewarded({required String adUnitId}) async {
    preloadRewardedCallCount++;
    callLog.add('preloadRewarded:$adUnitId');
    _rewardedStatus.value = AdRewardedLoadStatus.ready;
  }

  @override
  Future<bool> showRewarded() async {
    showRewardedCallCount++;
    callLog.add('showRewarded');
    return rewardEarnedOnShow;
  }
}