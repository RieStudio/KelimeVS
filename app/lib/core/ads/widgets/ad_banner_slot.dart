import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../config/ad_config.dart';
import '../../network/network_status_provider.dart';
import '../ad_providers.dart';

/// MainShell alt gezinme çubuğunun üzerinde yer alan paylaşımlı adaptive banner alanı.
///
/// Reklam kapalıysa, çevrimdışıysa, izin yoksa veya henüz yüklenmediyse `SizedBox.shrink()` döner.
/// Yüklendiğinde `AppBottomNavBar` ile arasına `10 px` boşluk bırakarak yanlışlıkla tıklamayı önler.
class AdBannerSlot extends ConsumerStatefulWidget {
  final bool isVisibleForTab;
  final bool? isAdsEnabledOverride;

  const AdBannerSlot({
    super.key,
    required this.isVisibleForTab,
    this.isAdsEnabledOverride,
  });

  @override
  ConsumerState<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends ConsumerState<AdBannerSlot> {
  int? _lastRequestedWidth;

  bool get _isAdsEnabled =>
      widget.isAdsEnabledOverride ?? AdConfig.isAdsEnabled;

  void _maybeLoadBanner(int widthPx) {
    if (widthPx <= 0) return;
    if (_lastRequestedWidth == widthPx) return;
    _lastRequestedWidth = widthPx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(adServiceProvider).loadBanner(
              adUnitId: AdConfig.bannerAdUnitId,
              width: widthPx,
            ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdsEnabled || !widget.isVisibleForTab) {
      return const SizedBox.shrink();
    }

    final networkStatus = ref.watch(networkStatusProvider).status;
    final consent = ref.watch(adConsentProvider);
    if (networkStatus == NetworkStatus.offline ||
        !consent.isSdkInitialized ||
        !consent.canRequestAds) {
      return const SizedBox.shrink();
    }

    final widthPx = MediaQuery.sizeOf(context).width.truncate();
    _maybeLoadBanner(widthPx);

    final adService = ref.watch(adServiceProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: adService.isBannerLoadedListenable,
      builder: (context, isLoaded, _) {
        if (!isLoaded) {
          return const SizedBox.shrink();
        }
        final bannerWidget = adService.buildBannerWidget();
        if (bannerWidget == null) {
          return const SizedBox.shrink();
        }
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            key: const Key('ad_banner_slot_container'),
            width: double.infinity,
            color: AppColors.surface,
            padding: const EdgeInsets.only(
              top: AppDimens.space4,
              bottom: AppDimens.space10,
            ),
            child: Center(child: bannerWidget),
          ),
        );
      },
    );
  }
}
