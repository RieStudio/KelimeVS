import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/online/data/auth_token_provider.dart';
import '../../features/profile/application/profile_notifier.dart';
import '../../features/store/application/store_notifier.dart';
import '../config/ad_config.dart';
import '../network/network_status_provider.dart';
import '../strings/app_strings.dart';
import 'ad_rewards_api_client.dart';
import 'ad_rewards_state.dart';
import 'ad_service.dart';
import 'pending_ad_claim_store.dart';

/// Testlerde override edilebilen reklam servisi sağlayıcısı.
final adServiceProvider = Provider<AdService>((ref) {
  return GoogleMobileAdsService();
});

final adRewardsApiClientProvider = Provider<AdRewardsApiClient>((ref) {
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpAdRewardsApiClient(
    authTokenProvider: const FirebaseAuthTokenProvider(),
    onAccountDeleted: onDeleted,
  );
});

final pendingAdClaimStoreProvider = Provider<PendingAdClaimStore>((ref) {
  return const SharedPreferencesPendingAdClaimStore();
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
      final service = ref.read(adServiceProvider);
      final result = await service.initialize();
      state = result;
      if (result.isSdkInitialized && AdConfig.rewardedAdUnitId.isNotEmpty) {
        unawaited(
          service.preloadRewarded(adUnitId: AdConfig.rewardedAdUnitId),
        );
      }
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

enum RewardedClaimOutcomeStatus {
  granted,
  dismissed,
  notReady,
  error,
}

@immutable
class RewardedClaimOutcome {
  final RewardedClaimOutcomeStatus status;
  final String message;

  const RewardedClaimOutcome({
    required this.status,
    required this.message,
  });
}

@immutable
class AdRewardControllerState {
  final bool isClaiming;
  const AdRewardControllerState({this.isClaiming = false});
}

class AdRewardController extends Notifier<AdRewardControllerState> {
  bool _isRetryingPending = false;
  final bool Function()? isAdsEnabledOverride;

  AdRewardController({this.isAdsEnabledOverride});

  bool get _isAdsEnabled =>
      isAdsEnabledOverride != null ? isAdsEnabledOverride!() : AdConfig.isAdsEnabled;

  @override
  AdRewardControllerState build() => const AdRewardControllerState();

  Future<void> preloadIfReady() async {
    if (!_isAdsEnabled) return;
    final network = ref.read(networkStatusProvider).status;
    if (network == NetworkStatus.offline) return;
    final consent = ref.read(adConsentProvider);
    if (!consent.isSdkInitialized || !consent.canRequestAds) return;

    final service = ref.read(adServiceProvider);
    final status = service.rewardedStatusListenable.value;
    if (status == AdRewardedLoadStatus.idle ||
        status == AdRewardedLoadStatus.failed) {
      await service.preloadRewarded(adUnitId: AdConfig.rewardedAdUnitId);
    }
  }

  Future<RewardedClaimOutcome> watchAndClaim(String type) async {
    if (state.isClaiming) {
      return const RewardedClaimOutcome(
        status: RewardedClaimOutcomeStatus.notReady,
        message: AppStrings.adRewardLoading,
      );
    }
    if (!_isAdsEnabled) {
      return const RewardedClaimOutcome(
        status: RewardedClaimOutcomeStatus.error,
        message: AppStrings.adRewardDisabledError,
      );
    }

    final service = ref.read(adServiceProvider);
    if (service.rewardedStatusListenable.value != AdRewardedLoadStatus.ready) {
      unawaited(preloadIfReady());
      return const RewardedClaimOutcome(
        status: RewardedClaimOutcomeStatus.notReady,
        message: AppStrings.adRewardNotReady,
      );
    }

    state = const AdRewardControllerState(isClaiming: true);
    try {
      final claimId = generateSecureAdClaimId();
      final earned = await service.showRewarded();
      if (!earned) {
        return const RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.dismissed,
          message: AppStrings.adRewardDismissed,
        );
      }

      final pendingStore = ref.read(pendingAdClaimStoreProvider);
      await pendingStore.save(
        PendingAdClaim(
          type: type,
          claimId: claimId,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final result = await ref
          .read(adRewardsApiClientProvider)
          .claimReward(type: type, claimId: claimId);
      return await _handleClaimResult(result, type, pendingStore);
    } finally {
      state = const AdRewardControllerState(isClaiming: false);
    }
  }

  Future<void> retryPendingClaim() async {
    if (_isRetryingPending || !_isAdsEnabled) return;
    if (ref.read(networkStatusProvider).status == NetworkStatus.offline) return;

    final pendingStore = ref.read(pendingAdClaimStoreProvider);
    final pending = await pendingStore.load();
    if (pending == null) return;

    _isRetryingPending = true;
    try {
      final result = await ref
          .read(adRewardsApiClientProvider)
          .claimReward(type: pending.type, claimId: pending.claimId);
      await _handleClaimResult(result, pending.type, pendingStore);
    } finally {
      _isRetryingPending = false;
    }
  }

  Future<RewardedClaimOutcome> _handleClaimResult(
    AdRewardClaimResult result,
    String type,
    PendingAdClaimStore pendingStore,
  ) async {
    switch (result) {
      case AdRewardClaimSuccess():
        await pendingStore.clear();
        await ref.read(profileProvider.notifier).updateCoins(result.coins);
        ref.read(profileProvider.notifier).updateEnergy(result.energy);
        final currentInfo = ref.read(profileProvider).adRewards;
        ref.read(profileProvider.notifier).updateAdRewards(
              currentInfo.copyWith(
                energy: AdRewardQuota(
                  remaining: result.remainingEnergy,
                  cap: currentInfo.energy.cap,
                ),
                coins: AdRewardQuota(
                  remaining: result.remainingCoins,
                  cap: currentInfo.coins.cap,
                ),
                nextClaimAtMs: result.nextClaimAtMs,
                clearNextClaimAtMs: result.nextClaimAtMs == null,
              ),
            );
        unawaited(ref.read(storeNotifierProvider.notifier).refresh());
        final amount = type == 'energy'
            ? currentInfo.energyAmount
            : currentInfo.coinsAmount;
        return RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.granted,
          message: type == 'energy'
              ? AppStrings.adRewardEnergyGranted(amount)
              : AppStrings.adRewardCoinsGranted(amount),
        );

      case AdRewardClaimTooSoon(:final retryAfterSeconds, :final nextClaimAtMs):
        await pendingStore.clear();
        if (nextClaimAtMs != null) {
          final currentInfo = ref.read(profileProvider).adRewards;
          ref.read(profileProvider.notifier).updateAdRewards(
                currentInfo.copyWith(nextClaimAtMs: nextClaimAtMs),
              );
        }
        return RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: AppStrings.adRewardTooSoon(retryAfterSeconds),
        );

      case AdRewardClaimDailyLimitReached(
          :final remainingEnergy,
          :final remainingCoins
        ):
        await pendingStore.clear();
        final currentInfo = ref.read(profileProvider).adRewards;
        ref.read(profileProvider.notifier).updateAdRewards(
              currentInfo.copyWith(
                energy: AdRewardQuota(
                  remaining: remainingEnergy,
                  cap: currentInfo.energy.cap,
                ),
                coins: AdRewardQuota(
                  remaining: remainingCoins,
                  cap: currentInfo.coins.cap,
                ),
              ),
            );
        return const RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: AppStrings.adRewardDailyLimitError,
        );

      case AdRewardClaimEnergyFull():
        await pendingStore.clear();
        return const RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: AppStrings.adRewardEnergyFullError,
        );

      case AdRewardClaimAdsDisabled():
        await pendingStore.clear();
        final currentInfo = ref.read(profileProvider).adRewards;
        ref.read(profileProvider.notifier).updateAdRewards(
              currentInfo.copyWith(enabled: false),
            );
        return const RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: AppStrings.adRewardDisabledError,
        );

      case AdRewardClaimAccountDeleted():
        await pendingStore.clear();
        return const RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: AppStrings.adRewardGenericError,
        );

      case AdRewardClaimPermanentError(:final message):
        await pendingStore.clear();
        return RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: message,
        );

      case AdRewardClaimRetryableError(:final message):
        return RewardedClaimOutcome(
          status: RewardedClaimOutcomeStatus.error,
          message: message,
        );
    }
  }
}

final adRewardControllerProvider =
    NotifierProvider<AdRewardController, AdRewardControllerState>(
  AdRewardController.new,
);
