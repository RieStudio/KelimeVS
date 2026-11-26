import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Güvenli 24 karakterli `[A-Za-z0-9_-]` reklam talep kimliği üretir.
String generateSecureAdClaimId({Random? random}) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final rng = random ?? Random.secure();
  return List<String>.generate(
    24,
    (_) => alphabet[rng.nextInt(alphabet.length)],
  ).join();
}

@immutable
class PendingAdClaim {
  final String type;
  final String claimId;
  final int createdAtMs;

  const PendingAdClaim({
    required this.type,
    required this.claimId,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'claimId': claimId,
        'createdAtMs': createdAtMs,
      };

  factory PendingAdClaim.fromJson(Map<String, dynamic> json) {
    return PendingAdClaim(
      type: json['type'] as String? ?? '',
      claimId: json['claimId'] as String? ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract interface class PendingAdClaimStore {
  Future<PendingAdClaim?> load();
  Future<void> save(PendingAdClaim claim);
  Future<void> clear();
}

/// En fazla 1 bekleyen reklam ödülü talebini `SharedPreferences` içinde saklar.
class SharedPreferencesPendingAdClaimStore implements PendingAdClaimStore {
  static const String storageKey = 'pending_ad_reward_claim_v1';

  const SharedPreferencesPendingAdClaimStore();

  @override
  Future<PendingAdClaim?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final claim = PendingAdClaim.fromJson(Map<String, dynamic>.from(decoded));
      if ((claim.type != 'energy' && claim.type != 'coins') ||
          claim.claimId.length < 8) {
        return null;
      }
      return claim;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PendingAdClaim claim) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(claim.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
  }
}
