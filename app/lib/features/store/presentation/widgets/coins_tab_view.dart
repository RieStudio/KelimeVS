import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ads/ad_providers.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/ads/widgets/rewarded_ad_button.dart';
import '../../../../core/config/ad_config.dart';
import '../../../../core/network/network_guard.dart';
import '../../../../core/network/network_status_provider.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/coin_icon.dart';
import '../../../profile/application/profile_notifier.dart';

/// DESIGN.md 9a: Jeton Sekmesi Görünümü
/// Ücretsiz jeton ödüllü reklam kartı (etkinken) ve altında "Jeton Paketleri Çok Yakında" kartı.
class CoinsTabView extends StatelessWidget {
  const CoinsTabView({super.key});

  Future<void> _handleWatchCoinsAd(BuildContext context, WidgetRef ref) async {
    if (!ensureNetworkConnected(context, ref)) return;
    final outcome = await ref
        .read(adRewardControllerProvider.notifier)
        .watchAndClaim('coins');
    if (!context.mounted) return;
    if (outcome.status == RewardedClaimOutcomeStatus.granted) {
      HapticFeedback.lightImpact();
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            outcome.message,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontNunito,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.ink,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final hasProviderScope =
        context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() !=
                null ||
            context.findAncestorWidgetOfExactType<ProviderScope>() != null;

    if (!hasProviderScope) {
      return _buildBody(context, null);
    }

    return Consumer(
      builder: (context, ref, _) => _buildBody(context, ref),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef? ref) {
    final profile = ref?.watch(profileProvider);
    final adRewards = profile?.adRewards;
    final showAdCard =
        ref != null && AdConfig.isAdsEnabled && (adRewards?.enabled ?? false);
    final isOnline = ref != null &&
        ref.watch(networkStatusProvider).status != NetworkStatus.offline;
    final adService = ref?.watch(adServiceProvider);
    final isClaiming =
        ref != null && ref.watch(adRewardControllerProvider).isClaiming;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showAdCard && adRewards != null && adService != null && profile != null) ...[
            Container(
              key: const Key('coins_tab_ad_reward_card'),
              padding: const EdgeInsets.all(AppDimens.space20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusListCard,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const CoinIcon(size: 36),
                      const SizedBox(width: AppDimens.space12),
                      Expanded(
                        child: Text(
                          AppStrings.adCoinsCardTitle,
                          style: AppTextStyles.cardTitle.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space16),
                  ValueListenableBuilder<AdRewardedLoadStatus>(
                    valueListenable: adService.rewardedStatusListenable,
                    builder: (context, loadStatus, _) {
                      return RewardedAdActionButton(
                        buttonKey: const Key('coins_tab_watch_ad_button'),
                        label: AppStrings.adWatchForCoins(adRewards.coinsAmount),
                        remaining: adRewards.coins.remaining,
                        cap: adRewards.coins.cap,
                        nextClaimAtMs: adRewards.nextClaimAtMs,
                        serverNowMs: profile.serverNowMs,
                        isOnline: isOnline,
                        loadStatus: loadStatus,
                        isClaiming: isClaiming,
                        onPressed: () => _handleWatchCoinsAd(context, ref!),
                        onNotReadyTap: () {
                          unawaited(
                            ref!
                                .read(adRewardControllerProvider.notifier)
                                .preloadIfReady(),
                          );
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                  AppStrings.adRewardNotReady,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontNunito,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                backgroundColor: AppColors.ink,
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space16),
          ],
          Container(
            padding: const EdgeInsets.all(AppDimens.space24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppDimens.borderRadiusListCard,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinIcon(size: 72),
                const SizedBox(height: AppDimens.space16),
                const Text(
                  AppStrings.coinsTabTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                const Text(
                  AppStrings.coinsTabDescription,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
