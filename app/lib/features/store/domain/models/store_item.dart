import 'package:flutter/foundation.dart';

/// Mağaza kataloğundaki bir avatar çerçevesi öğesi.
@immutable
class StoreItem {
  final String id;
  final String name;
  final int price;
  final bool owned;
  final bool isEquipped;

  const StoreItem({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
    required this.isEquipped,
  });

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    return StoreItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      price: ((json['cost'] ?? json['price']) as num?)?.toInt() ?? 0,
      owned: ((json['isOwned'] ?? json['owned']) as bool?) ?? false,
      isEquipped: json['isEquipped'] as bool? ?? false,
    );
  }

  StoreItem copyWith({
    String? id,
    String? name,
    int? price,
    bool? owned,
    bool? isEquipped,
  }) {
    return StoreItem(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      owned: owned ?? this.owned,
      isEquipped: isEquipped ?? this.isEquipped,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          price == other.price &&
          owned == other.owned &&
          isEquipped == other.isEquipped;

  @override
  int get hashCode => Object.hash(id, name, price, owned, isEquipped);
}

/// Mağaza ekranı durum modeli.
@immutable
class StoreState {
  final int coins;
  final String equippedFrame;
  final List<StoreItem> items;
  final bool isLoading;
  final String? errorMessage;
  final String? actionInProgressItemId;

  const StoreState({
    this.coins = 0,
    this.equippedFrame = 'classic',
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
    this.actionInProgressItemId,
  });

  StoreState copyWith({
    int? coins,
    String? equippedFrame,
    List<StoreItem>? items,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? actionInProgressItemId,
    bool clearActionInProgress = false,
  }) {
    return StoreState(
      coins: coins ?? this.coins,
      equippedFrame: equippedFrame ?? this.equippedFrame,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionInProgressItemId: clearActionInProgress
          ? null
          : (actionInProgressItemId ?? this.actionInProgressItemId),
    );
  }
}

