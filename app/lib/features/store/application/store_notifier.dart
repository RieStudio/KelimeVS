import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../profile/application/profile_notifier.dart';
import '../data/store_api_client.dart';
import '../domain/models/store_item.dart';

class StoreNotifier extends Notifier<StoreState> {
  @override
  StoreState build() {
    // İlk açılışta profil bakiyesini ve kuşanılan çerçeveyi yerelden alarak başla
    final profile = ref.read(profileProvider);
    state = StoreState(
      coins: profile.coins,
      equippedFrame: profile.equippedFrame,
      isLoading: true,
    );

    // Profil değişirse (maçtan sonra jeton artışı vb.) mağaza bakiyesini güncelle
    ref.listen(profileProvider, (prev, next) {
      if (state.coins != next.coins || state.equippedFrame != next.equippedFrame) {
        state = state.copyWith(
          coins: next.coins,
          equippedFrame: next.equippedFrame,
        );
      }
    });

    unawaited(_loadStore());
    return state;
  }

  StoreApiClient get _client => ref.read(storeApiClientProvider);

  Future<void> _loadStore() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final remoteState = await _client.getStore();
    if (remoteState != null) {
      state = StoreState(
        coins: remoteState.coins,
        equippedFrame: remoteState.equippedFrame,
        items: remoteState.items,
        isLoading: false,
      );
      // Profil bakiyesini ve kuşanılan çerçeveyi senkronize et
      unawaited(ref.read(profileProvider.notifier).updateCoins(remoteState.coins));
      unawaited(
        ref.read(profileProvider.notifier).setEquippedFrame(remoteState.equippedFrame),
      );
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    await _loadStore();
  }

  /// Çerçeve satın alma işlemi.
  /// Çift dokunma koruması: [actionInProgressItemId] ile korunur.
  Future<StorePurchaseResult?> purchase(String itemId) async {
    if (state.actionInProgressItemId != null) return null;

    state = state.copyWith(
      actionInProgressItemId: itemId,
      clearError: true,
    );

    final result = await _client.purchaseItem(itemId);

    if (result is StorePurchaseSuccess) {
      // 1. Profil bakiyesini güncelle
      unawaited(ref.read(profileProvider.notifier).updateCoins(result.coins));

      // 2. Satın alınan çerçeveyi sahipliğe ekle (otomatik kuşanma YOK, docs/DESIGN.md)
      final updatedItems = state.items.map((item) {
        if (item.id == itemId) {
          return item.copyWith(owned: true, isEquipped: false);
        }
        return item;
      }).toList();

      state = state.copyWith(
        coins: result.coins,
        items: updatedItems,
        clearActionInProgress: true,
      );
    } else if (result is StorePurchaseNotEnoughCoins) {
      state = state.copyWith(
        errorMessage: result.message,
        clearActionInProgress: true,
      );
    } else if (result is StorePurchaseAlreadyOwned) {
      state = state.copyWith(
        errorMessage: result.message,
        clearActionInProgress: true,
      );
    } else if (result is StorePurchaseNetworkError) {
      state = state.copyWith(
        errorMessage: result.message,
        clearActionInProgress: true,
      );
    } else if (result is StorePurchaseInvalidItem) {
      state = state.copyWith(
        errorMessage: result.message,
        clearActionInProgress: true,
      );
    } else {
      state = state.copyWith(clearActionInProgress: true);
    }

    return result;
  }

  /// Sahip olunan çerçeveyi kuşanma işlemi.
  /// Çift dokunma koruması: [actionInProgressItemId] ile korunur.
  Future<StoreEquipResult?> equip(String frameId) async {
    if (state.actionInProgressItemId != null) return null;
    if (state.equippedFrame == frameId) return StoreEquipSuccess(frameId);

    state = state.copyWith(
      actionInProgressItemId: frameId,
      clearError: true,
    );

    try {
      final result = await _client.equipFrame(frameId);

      if (result is StoreEquipSuccess) {
        unawaited(ref.read(profileProvider.notifier).setEquippedFrame(frameId));

        final updatedItems = state.items.map((item) {
          return item.copyWith(isEquipped: item.id == frameId);
        }).toList();

        state = state.copyWith(
          equippedFrame: frameId,
          items: updatedItems,
          clearActionInProgress: true,
        );
      } else if (result is StoreEquipNotOwned) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else if (result is StoreEquipNetworkError) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else if (result is StoreEquipInvalidFrame) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else {
        state = state.copyWith(clearActionInProgress: true);
      }

      return result;
    } catch (e) {
      state = state.copyWith(
        errorMessage: AppStrings.storeGenericError,
        clearActionInProgress: true,
      );
      return StoreEquipNetworkError(AppStrings.storeGenericError, e);
    }
  }
}

final storeNotifierProvider =
    NotifierProvider.autoDispose<StoreNotifier, StoreState>(
  StoreNotifier.new,
);

