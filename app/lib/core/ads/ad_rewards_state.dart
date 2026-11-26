import 'package:flutter/foundation.dart';

@immutable
class AdRewardQuota {
  final int remaining;
  final int cap;

  const AdRewardQuota({
    required this.remaining,
    required this.cap,
  });

  factory AdRewardQuota.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdRewardQuota(remaining: 0, cap: 0);
    return AdRewardQuota(
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      cap: (json['cap'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdRewardQuota &&
          runtimeType == other.runtimeType &&
          remaining == other.remaining &&
          cap == other.cap;

  @override
  int get hashCode => Object.hash(remaining, cap);
}

/// `GET /me` yanıtındaki `adRewards` alanı.
@immutable
class AdRewardsInfo {
  final bool enabled;
  final AdRewardQuota energy;
  final AdRewardQuota coins;
  final int? nextClaimAtMs;
  final int energyAmount;
  final int coinsAmount;

  const AdRewardsInfo({
    required this.enabled,
    required this.energy,
    required this.coins,
    this.nextClaimAtMs,
    this.energyAmount = 1,
    this.coinsAmount = 15,
  });

  const AdRewardsInfo.disabled()
      : enabled = false,
        energy = const AdRewardQuota(remaining: 0, cap: 0),
        coins = const AdRewardQuota(remaining: 0, cap: 0),
        nextClaimAtMs = null,
        energyAmount = 1,
        coinsAmount = 15;

  factory AdRewardsInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdRewardsInfo.disabled();
    final enabledRaw = json['enabled'];
    final enabled = enabledRaw is bool ? enabledRaw : false;
    final energyMap = json['energy'] is Map
        ? Map<String, dynamic>.from(json['energy'] as Map)
        : null;
    final coinsMap = json['coins'] is Map
        ? Map<String, dynamic>.from(json['coins'] as Map)
        : null;

    return AdRewardsInfo(
      enabled: enabled,
      energy: AdRewardQuota.fromJson(energyMap),
      coins: AdRewardQuota.fromJson(coinsMap),
      nextClaimAtMs: (json['nextClaimAtMs'] as num?)?.toInt(),
      energyAmount: (json['energyAmount'] as num?)?.toInt() ?? 1,
      coinsAmount: (json['coinsAmount'] as num?)?.toInt() ?? 15,
    );
  }

  AdRewardsInfo copyWith({
    bool? enabled,
    AdRewardQuota? energy,
    AdRewardQuota? coins,
    int? nextClaimAtMs,
    bool clearNextClaimAtMs = false,
    int? energyAmount,
    int? coinsAmount,
  }) {
    return AdRewardsInfo(
      enabled: enabled ?? this.enabled,
      energy: energy ?? this.energy,
      coins: coins ?? this.coins,
      nextClaimAtMs:
          clearNextClaimAtMs ? null : (nextClaimAtMs ?? this.nextClaimAtMs),
      energyAmount: energyAmount ?? this.energyAmount,
      coinsAmount: coinsAmount ?? this.coinsAmount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdRewardsInfo &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          energy == other.energy &&
          coins == other.coins &&
          nextClaimAtMs == other.nextClaimAtMs &&
          energyAmount == other.energyAmount &&
          coinsAmount == other.coinsAmount;

  @override
  int get hashCode => Object.hash(
        enabled,
        energy,
        coins,
        nextClaimAtMs,
        energyAmount,
        coinsAmount,
      );
}
