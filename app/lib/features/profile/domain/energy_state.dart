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
    final rawPacks = json['packs'] as List<dynamic>? ?? [];
    return EnergyState(
      enabled: json['enabled'] as bool? ?? false,
      current: (json['current'] as num?)?.toInt() ?? 5,
      max: (json['max'] as num?)?.toInt() ?? 5,
      nextEnergyAtMs: (json['nextEnergyAtMs'] as num?)?.toInt(),
      regenSeconds: (json['regenSeconds'] as num?)?.toInt() ?? 1200,
      packs: rawPacks
          .map((e) => EnergyPack.fromJson(e as Map<String, dynamic>))
          .toList(),
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
