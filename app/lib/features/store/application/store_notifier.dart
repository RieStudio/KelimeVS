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

    // Profil değişirse (maçtan sonra jeton artışı, enerji değişimi vb.) mağaza durumunu güncelle
    ref.listen(profileProvider, (prev, next) {
      if (state.coins != next.coins ||
          state.equippedFrame != next.equippedFrame ||
          state.energy != next.energy ||
          state.serverNowMs != next.serverNowMs) {
        state = state.copyWith(
          coins: next.coins,
          equippedFrame: next.equippedFrame,
          energy: next.energy,
          serverNowMs: next.serverNowMs,
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
      state = state.copyWith(
        coins: remoteState.coins,
        equippedFrame: remoteState.equippedFrame,
        items: remoteState.items,
        energy: remoteState.energy,
        serverNowMs: remoteState.serverNowMs,
        isLoading: false,
      );
      // Profil bakiyesini, kuşanılan çerçeveyi ve enerjiyi senkronize et
      unawaited(
        ref.read(profileProvider.notifier).updateCoins(remoteState.coins),
      );
      unawaited(
        ref
            .read(profileProvider.notifier)
            .setEquippedFrame(remoteState.equippedFrame),
      );
      if (remoteState.energy != null) {
        ref
            .read(profileProvider.notifier)
            .updateEnergy(remoteState.energy!, remoteState.serverNowMs);
      }
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    await _loadStore();
  }

  /// Aktif sekmeyi değiştirir (Jeton · Enerji · Çerçeve)
  void setTab(StoreTab tab) {
    if (state.selectedTab != tab) {
      state = state.copyWith(selectedTab: tab);
    }
  }

  /// Enerji paketi satın alma işlemi ('one' veya 'full')
  Future<StorePurchaseEnergyResult?> purchaseEnergy(String pack) async {
    if (state.actionInProgressItemId != null) return null;

    state = state.copyWith(
      actionInProgressItemId: 'energy_$pack',
      clearError: true,
    );

    try {
      final result = await _client.purchaseEnergy(pack);

      if (result is StorePurchaseEnergySuccess) {
        unawaited(ref.read(profileProvider.notifier).updateCoins(result.coins));
        final newEnergy = state.energy?.copyWith(
          current: result.energy,
          max: result.max,
          nextEnergyAtMs: result.nextEnergyAtMs,
          clearNextEnergyAtMs: result.nextEnergyAtMs == null,
        );
        if (newEnergy != null) {
          ref
              .read(profileProvider.notifier)
              .updateEnergy(newEnergy, result.serverNowMs);
        }

        state = state.copyWith(
          coins: result.coins,
          energy: newEnergy,
          serverNowMs: result.serverNowMs,
          clearActionInProgress: true,
        );
      } else if (result is StorePurchaseEnergyNotEnoughCoins) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else if (result is StorePurchaseEnergyFull) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else if (result is StorePurchaseEnergyDisabled) {
        state = state.copyWith(
          errorMessage: result.message,
          clearActionInProgress: true,
        );
      } else if (result is StorePurchaseEnergyNetworkError) {
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
      return StorePurchaseEnergyNetworkError(AppStrings.storeGenericError, e);
    }
  }

  /// Çerçeve satın alma işlemi.
  /// Çift dokunma koruması: [actionInProgressItemId] ile korunur.
  Future<StorePurchaseResult?> purchase(String itemId) async {
    if (state.actionInProgressItemId != null) return null;

    state = state.copyWith(actionInProgressItemId: itemId, clearError: true);

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

    state = state.copyWith(actionInProgressItemId: frameId, clearError: true);

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
    NotifierProvider.autoDispose<StoreNotifier, StoreState>(StoreNotifier.new);
