import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';

/// UMP gizlilik seçenekleri gereksinim durumu.
enum AdConsentPrivacyStatus {
  unknown,
  notRequired,
  required,
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
  /// UMP onay akışını çalıştırır ve izin varsa MobileAds SDK'yı başlatır.
  Future<AdConsentState> initialize();

  /// Ayarlar ekranından gizlilik seçenekleri formunu yeniden açar.
  Future<AdConsentPrivacyStatus> showPrivacyOptionsForm();

  /// Banner yükleme iskeleti (Faz 3'te doldurulacak).
  Future<void> loadBanner({required String adUnitId, required int width});

  /// Banner temizleme iskeleti (Faz 3'te doldurulacak).
  Future<void> disposeBanner();

  /// Ödüllü reklam ön yükleme iskeleti (Faz 3'te doldurulacak).
  Future<void> preloadRewarded({required String adUnitId});

  /// Ödüllü reklam gösterim iskeleti (Faz 3'te doldurulacak).
  Future<bool> showRewarded();
}

/// Gerçek `google_mobile_ads` ve UMP implementasyonu.
class GoogleMobileAdsService implements AdService {
  static const Duration _umpTimeout = Duration(seconds: 8);

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
            initializeMobileAds ?? (() => MobileAds.instance.initialize()),
        _showPrivacyOptionsForm =
            showPrivacyOptionsForm ?? _defaultShowPrivacyOptionsForm;

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
    if (!_isAdsEnabled()) {
      return const AdConsentState();
    }

    var canRequest = false;
    var privacyStatus = AdConsentPrivacyStatus.unknown;
    var sdkInitialized = false;

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

      await _requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      ).timeout(_umpTimeout);

      await _loadAndShowConsentFormIfRequired().timeout(_umpTimeout);

      canRequest = await _canRequestAds().timeout(_umpTimeout);
      final rawPrivacyStatus =
          await _getPrivacyOptionsStatus().timeout(_umpTimeout);
      privacyStatus = _mapPrivacyStatus(rawPrivacyStatus);

      if (canRequest) {
        await _initializeMobileAds();
        sdkInitialized = true;
      }
    } catch (_) {
      // Hata veya zaman aşımı durumunda uygulama akışı bozulmaz.
    }

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
  Future<void> loadBanner({required String adUnitId, required int width}) async {}

  @override
  Future<void> disposeBanner() async {}

  @override
  Future<void> preloadRewarded({required String adUnitId}) async {}

  @override
  Future<bool> showRewarded() async => false;

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

  int initializeCallCount = 0;
  int showPrivacyOptionsCallCount = 0;
  final List<String> callLog = <String>[];

  FakeAdService({
    this.initialConsentState = const AdConsentState(
      isConsentChecked: true,
      canRequestAds: true,
      isSdkInitialized: true,
      privacyOptionsStatus: AdConsentPrivacyStatus.notRequired,
    ),
    this.privacyStatusAfterForm = AdConsentPrivacyStatus.required,
  });

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
    callLog.add('loadBanner:$adUnitId:$width');
  }

  @override
  Future<void> disposeBanner() async {
    callLog.add('disposeBanner');
  }

  @override
  Future<void> preloadRewarded({required String adUnitId}) async {
    callLog.add('preloadRewarded:$adUnitId');
  }

  @override
  Future<bool> showRewarded() async {
    callLog.add('showRewarded');
    return true;
  }
}
