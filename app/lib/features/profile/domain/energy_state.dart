import 'package:flutter/foundation.dart';

@immutable
class EnergyPack {
  final String id;
  final int cost;
  final int energy;

  const EnergyPack({
    required this.id,
    required this.cost,
    required this.energy,
  });

  factory EnergyPack.fromJson(Map<String, dynamic> json) {
    return EnergyPack(
      id: json['id'] as String? ?? '',
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      energy: (json['energy'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'cost': cost, 'energy': energy};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnergyPack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          cost == other.cost &&
          energy == other.energy;

  @override
  int get hashCode => Object.hash(id, cost, energy);
}

bool _parseBool(dynamic val, {bool defaultValue = false}) {
  if (val is bool) return val;
  if (val is num) return val != 0;
  if (val is String) {
    final s = val.toLowerCase().trim();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return defaultValue;
}

@immutable
class EnergyState {
  final bool enabled;
  final int current;
  final int max;
  final int? nextEnergyAtMs;
  final int regenSeconds;
  final List<EnergyPack> packs;

  const EnergyState({
    required this.enabled,
    required this.current,
    required this.max,
    this.nextEnergyAtMs,
    this.regenSeconds = 1200,
    this.packs = const [],
  });

  factory EnergyState.fromJson(Map<String, dynamic> json) {
    final rawPacks = json['packs'] is List ? (json['packs'] as List) : const [];
    final regenSec = (json['regenSeconds'] as num?)?.toInt() ??
        ((json['regenMinutes'] as num?) != null
            ? ((json['regenMinutes'] as num) * 60).toInt()
            : 1200);
    return EnergyState(
      enabled: _parseBool(json['enabled']),
      current: (json['current'] as num?)?.toInt() ?? 5,
      max: (json['max'] as num?)?.toInt() ?? 5,
      nextEnergyAtMs: (json['nextEnergyAtMs'] ?? json['next_energy_at_ms'] as num?)?.toInt(),
      regenSeconds: regenSec,
      packs: rawPacks.map((e) {
        if (e is Map<String, dynamic>) return EnergyPack.fromJson(e);
        if (e is Map) return EnergyPack.fromJson(Map<String, dynamic>.from(e));
        return const EnergyPack(id: '', cost: 0, energy: 0);
      }).toList(),
    );
  }

  bool get isFull => current >= max;

  EnergyState copyWith({
    bool? enabled,
    int? current,
    int? max,
    int? nextEnergyAtMs,
    bool clearNextEnergyAtMs = false,
    int? regenSeconds,
    List<EnergyPack>? packs,
  }) {
    return EnergyState(
      enabled: enabled ?? this.enabled,
      current: current ?? this.current,
      max: max ?? this.max,
      nextEnergyAtMs: clearNextEnergyAtMs
          ? null
          : (nextEnergyAtMs ?? this.nextEnergyAtMs),
      regenSeconds: regenSeconds ?? this.regenSeconds,
      packs: packs ?? this.packs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnergyState &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          current == other.current &&
          max == other.max &&
          nextEnergyAtMs == other.nextEnergyAtMs &&
          regenSeconds == other.regenSeconds &&
          listEquals(packs, other.packs);

  @override
  int get hashCode => Object.hash(
    enabled,
    current,
    max,
    nextEnergyAtMs,
    regenSeconds,
    Object.hashAll(packs),
  );
}
