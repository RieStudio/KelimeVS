import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/ad_config.dart';
import 'ad_service.dart';

/// Testlerde override edilebilen reklam servisi sağlayıcısı.
final adServiceProvider = Provider<AdService>((ref) {
  return GoogleMobileAdsService();
});

/// Reklam onay ve başlatma durumunu yöneten Riverpod Notifier.
class AdConsentNotifier extends Notifier<AdConsentState> {
  final bool Function()? isAdsEnabledOverride;
  bool _isInitializing = false;

  AdConsentNotifier({this.isAdsEnabledOverride});

  bool get _isAdsEnabled =>
      isAdsEnabledOverride != null ? isAdsEnabledOverride!() : AdConfig.isAdsEnabled;

  @override
  AdConsentState build() => const AdConsentState();

  /// Kill-switch kapalıysa (devre dışıysa) UMP veya SDK'yı hiç çağırmaz.
  Future<void> initialize() async {
    if (!_isAdsEnabled) return;
    if (_isInitializing || state.isSdkInitialized) return;

    _isInitializing = true;
    try {
      final result = await ref.read(adServiceProvider).initialize();
      state = result;
    } finally {
      _isInitializing = false;
    }
  }

  /// Ayarlar ekranından gizlilik seçenekleri formunu açar ve durumu günceller.
  Future<void> showPrivacyOptionsForm() async {
    if (!_isAdsEnabled) return;
    final nextStatus =
        await ref.read(adServiceProvider).showPrivacyOptionsForm();
    if (nextStatus != AdConsentPrivacyStatus.unknown) {
      state = state.copyWith(privacyOptionsStatus: nextStatus);
    }
  }
}

final adConsentProvider = NotifierProvider<AdConsentNotifier, AdConsentState>(
  AdConsentNotifier.new,
);
