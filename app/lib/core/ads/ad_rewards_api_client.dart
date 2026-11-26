import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../features/online/data/auth_token_provider.dart';
import '../../features/profile/domain/energy_state.dart';
import '../config/server_config.dart';
import '../network/auth_http_executor.dart';
import '../strings/app_strings.dart';

sealed class AdRewardClaimResult {
  const AdRewardClaimResult();
}

class AdRewardClaimSuccess extends AdRewardClaimResult {
  final String type;
  final bool granted;
  final bool alreadyProcessed;
  final int coins;
  final EnergyState energy;
  final int remainingEnergy;
  final int remainingCoins;
  final int? nextClaimAtMs;

  const AdRewardClaimSuccess({
    required this.type,
    required this.granted,
    required this.alreadyProcessed,
    required this.coins,
    required this.energy,
    required this.remainingEnergy,
    required this.remainingCoins,
    this.nextClaimAtMs,
  });
}

class AdRewardClaimTooSoon extends AdRewardClaimResult {
  final int retryAfterSeconds;
  final int? nextClaimAtMs;
  const AdRewardClaimTooSoon({
    required this.retryAfterSeconds,
    this.nextClaimAtMs,
  });
}

class AdRewardClaimDailyLimitReached extends AdRewardClaimResult {
  final int remainingEnergy;
  final int remainingCoins;
  const AdRewardClaimDailyLimitReached({
    required this.remainingEnergy,
    required this.remainingCoins,
  });
}

class AdRewardClaimEnergyFull extends AdRewardClaimResult {
  const AdRewardClaimEnergyFull();
}

class AdRewardClaimAdsDisabled extends AdRewardClaimResult {
  const AdRewardClaimAdsDisabled();
}

class AdRewardClaimAccountDeleted extends AdRewardClaimResult {
  const AdRewardClaimAccountDeleted();
}

class AdRewardClaimPermanentError extends AdRewardClaimResult {
  final String code;
  final String message;
  const AdRewardClaimPermanentError(this.code, this.message);
}

class AdRewardClaimRetryableError extends AdRewardClaimResult {
  final String message;
  const AdRewardClaimRetryableError([this.message = AppStrings.networkError]);
}

abstract interface class AdRewardsApiClient {
  Future<AdRewardClaimResult> claimReward({
    required String type,
    required String claimId,
  });
}

class HttpAdRewardsApiClient implements AdRewardsApiClient {
  final AuthTokenProvider _authTokenProvider;
  final String _baseUrl;
  final HttpClient Function()? _clientFactory;
  final VoidCallback? _onAccountDeleted;

  HttpAdRewardsApiClient({
    required AuthTokenProvider authTokenProvider,
    String? baseUrl,
    HttpClient Function()? clientFactory,
    VoidCallback? onAccountDeleted,
  })  : _authTokenProvider = authTokenProvider,
        _baseUrl = baseUrl ?? ServerConfig.serverUrl,
        _clientFactory = clientFactory,
        _onAccountDeleted = onAccountDeleted;

  @override
  Future<AdRewardClaimResult> claimReward({
    required String type,
    required String claimId,
  }) async {
    try {
      final uri = Uri.parse(
        ServerConfig.joinUrl(_baseUrl, ServerConfig.adsRewardPath),
      );
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: _authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: _clientFactory,
        jsonBody: {'type': type, 'claimId': claimId},
        timeout: const Duration(seconds: 8),
      );

      if (response == null) {
        return const AdRewardClaimRetryableError(AppStrings.networkError);
      }

      if (response.statusCode == 200) {
        final data = response.decodeJsonMap();
        final energyMap = data['energy'] is Map
            ? Map<String, dynamic>.from(data['energy'] as Map)
            : const <String, dynamic>{};
        final remaining = data['remainingToday'] is Map
            ? Map<String, dynamic>.from(data['remainingToday'] as Map)
            : const <String, dynamic>{};

        return AdRewardClaimSuccess(
          type: data['type'] as String? ?? type,
          granted: data['granted'] == true,
          alreadyProcessed: data['alreadyProcessed'] == true,
          coins: (data['coins'] as num?)?.toInt() ?? 0,
          energy: EnergyState.fromJson(energyMap),
          remainingEnergy: (remaining['energy'] as num?)?.toInt() ?? 0,
          remainingCoins: (remaining['coins'] as num?)?.toInt() ?? 0,
          nextClaimAtMs: (data['nextClaimAtMs'] as num?)?.toInt(),
        );
      }

      if (response.statusCode == 401 || response.statusCode >= 500) {
        if (response.statusCode == 503) {
          return const AdRewardClaimAdsDisabled();
        }
        return const AdRewardClaimRetryableError(AppStrings.networkError);
      }

      Map<String, dynamic> errMap = const {};
      try {
        errMap = response.decodeJsonMap();
      } catch (_) {}

      final errorCode = errMap['error'] as String? ?? '';
      if (response.statusCode == 410 || errorCode == 'account_deleted') {
        _onAccountDeleted?.call();
        return const AdRewardClaimAccountDeleted();
      }
      if (response.statusCode == 409 || errorCode == 'energy_full') {
        return const AdRewardClaimEnergyFull();
      }
      if (errorCode == 'ads_disabled') {
        return const AdRewardClaimAdsDisabled();
      }
      if (errorCode == 'too_soon') {
        return AdRewardClaimTooSoon(
          retryAfterSeconds: (errMap['retryAfterSeconds'] as num?)?.toInt() ?? 60,
          nextClaimAtMs: (errMap['nextClaimAtMs'] as num?)?.toInt(),
        );
      }
      if (errorCode == 'daily_limit_reached') {
        final remaining = errMap['remainingToday'] is Map
            ? Map<String, dynamic>.from(errMap['remainingToday'] as Map)
            : const <String, dynamic>{};
        return AdRewardClaimDailyLimitReached(
          remainingEnergy: (remaining['energy'] as num?)?.toInt() ?? 0,
          remainingCoins: (remaining['coins'] as num?)?.toInt() ?? 0,
        );
      }

      return AdRewardClaimPermanentError(
        errorCode,
        errMap['message'] as String? ?? AppStrings.adRewardGenericError,
      );
    } on TimeoutException {
      return const AdRewardClaimRetryableError(AppStrings.networkError);
    } on SocketException {
      return const AdRewardClaimRetryableError(AppStrings.networkError);
    } catch (_) {
      return const AdRewardClaimRetryableError(AppStrings.networkError);
    }
  }
}

