import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/app_build_info.dart';
import '../../../core/strings/app_strings.dart';
import '../../auth/application/auth_notifier.dart';
import '../../online/data/auth_token_provider.dart';
import '../../profile/domain/energy_state.dart';
import '../domain/models/store_item.dart';

sealed class StorePurchaseResult {
  const StorePurchaseResult();
}

class StorePurchaseSuccess extends StorePurchaseResult {
  final int coins;
  final String itemId;
  const StorePurchaseSuccess({required this.coins, required this.itemId});
}

class StorePurchaseNotEnoughCoins extends StorePurchaseResult {
  final String message;
  const StorePurchaseNotEnoughCoins([
    this.message = AppStrings.insufficientCoins,
  ]);
}

class StorePurchaseAlreadyOwned extends StorePurchaseResult {
  final String message;
  const StorePurchaseAlreadyOwned([
    this.message = AppStrings.alreadyOwnedError,
  ]);
}

class StorePurchaseInvalidItem extends StorePurchaseResult {
  final String message;
  const StorePurchaseInvalidItem([this.message = AppStrings.storeGenericError]);
}

class StorePurchaseUnsupportedVersion extends StorePurchaseResult {
  final String message;
  const StorePurchaseUnsupportedVersion([
    this.message = AppStrings.storeUnsupportedClientVersion,
  ]);
}

class StorePurchaseNetworkError extends StorePurchaseResult {
  final String message;
  final Object? error;
  const StorePurchaseNetworkError([
    this.message = AppStrings.storeNetworkError,
    this.error,
  ]);
}

class StorePurchaseAccountDeleted extends StorePurchaseResult {
  const StorePurchaseAccountDeleted();
}

sealed class StoreEquipResult {
  const StoreEquipResult();
}

class StoreEquipSuccess extends StoreEquipResult {
  final String frameId;
  const StoreEquipSuccess(this.frameId);
}

class StoreEquipNotOwned extends StoreEquipResult {
  final String message;
  const StoreEquipNotOwned([this.message = AppStrings.itemNotOwnedError]);
}

class StoreEquipInvalidFrame extends StoreEquipResult {
  final String message;
  const StoreEquipInvalidFrame([
    this.message = AppStrings.storeInvalidFrameError,
  ]);
}

class StoreEquipNetworkError extends StoreEquipResult {
  final String message;
  final Object? error;
  const StoreEquipNetworkError([
    this.message = AppStrings.storeNetworkError,
    this.error,
  ]);
}

class StoreEquipAccountDeleted extends StoreEquipResult {
  const StoreEquipAccountDeleted();
}

sealed class StorePurchaseEnergyResult {
  const StorePurchaseEnergyResult();
}

class StorePurchaseEnergySuccess extends StorePurchaseEnergyResult {
  final int coins;
  final int energy;
  final int max;
  final int? nextEnergyAtMs;
  final int serverNowMs;
  final String pack;

  const StorePurchaseEnergySuccess({
    required this.coins,
    required this.energy,
    required this.max,
    required this.nextEnergyAtMs,
    required this.serverNowMs,
    required this.pack,
  });
}

class StorePurchaseEnergyNotEnoughCoins extends StorePurchaseEnergyResult {
  final String message;
  final int? coins;
  const StorePurchaseEnergyNotEnoughCoins([
    this.message = AppStrings.insufficientCoins,
    this.coins,
  ]);
}

class StorePurchaseEnergyFull extends StorePurchaseEnergyResult {
  final String message;
  const StorePurchaseEnergyFull([this.message = AppStrings.energyAlreadyFull]);
}

class StorePurchaseEnergyDisabled extends StorePurchaseEnergyResult {
  final String message;
  const StorePurchaseEnergyDisabled([this.message = AppStrings.energyDisabled]);
}

class StorePurchaseEnergyNetworkError extends StorePurchaseEnergyResult {
  final String message;
  final Object? error;
  const StorePurchaseEnergyNetworkError([
    this.message = AppStrings.storeNetworkError,
    this.error,
  ]);
}

abstract interface class StoreApiClient {
  Future<StoreState?> getStore();
  Future<StorePurchaseResult> purchaseItem(String itemId);
  Future<StoreEquipResult> equipFrame(String frameId);
  Future<StorePurchaseEnergyResult> purchaseEnergy(String pack);
}

class HttpStoreApiClient implements StoreApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  const HttpStoreApiClient({
    required this.authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  });

  HttpClient _createClient(Duration timeout) {
    if (clientFactory != null) return clientFactory!();
    return HttpClient()..connectionTimeout = timeout;
  }

  @override
  Future<StoreState?> getStore() async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) return null;

    final uri = Uri.parse(ServerConfig.storeUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final coins = (decoded['coins'] as num?)?.toInt() ?? 0;
        final equippedFrame = decoded['equippedFrame'] as String? ?? 'classic';
        final itemsList = (decoded['items'] as List<dynamic>? ?? [])
            .map((e) => StoreItem.fromJson(e as Map<String, dynamic>))
            .toList();
        final energyJson = decoded['energy'] as Map<String, dynamic>?;
        final energyState = energyJson != null
            ? EnergyState.fromJson(energyJson)
            : null;
        final serverNowMs = (decoded['serverNowMs'] as num?)?.toInt();
        return StoreState(
          coins: coins,
          equippedFrame: equippedFrame,
          items: itemsList,
          energy: energyState,
          serverNowMs: serverNowMs,
        );
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return null;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<StorePurchaseResult> purchaseItem(String itemId) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      return const StorePurchaseNetworkError();
    }

    final uri = Uri.parse(ServerConfig.purchaseUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);
      request.add(utf8.encode(jsonEncode({'itemId': itemId})));

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final coins = (decoded['coins'] as num?)?.toInt() ?? 0;
        return StorePurchaseSuccess(coins: coins, itemId: itemId);
      } else if (response.statusCode == 402) {
        return const StorePurchaseNotEnoughCoins();
      } else if (response.statusCode == 400) {
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
          final errCode = decoded['error'];
          if (errCode == 'already_owned') {
            return const StorePurchaseAlreadyOwned();
          }
          if (errCode == 'unsupported_client_version') {
            final msg = decoded['message'] as String?;
            return StorePurchaseUnsupportedVersion(
              msg ?? AppStrings.storeUnsupportedClientVersion,
            );
          }
        } catch (_) {}
        return const StorePurchaseInvalidItem();
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const StorePurchaseAccountDeleted();
      }
      return const StorePurchaseNetworkError();
    } catch (e) {
      return StorePurchaseNetworkError(AppStrings.storeNetworkError, e);
    } finally {
      client.close();
    }
  }

  @override
  Future<StoreEquipResult> equipFrame(String frameId) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      return const StoreEquipNetworkError();
    }

    final uri = Uri.parse(ServerConfig.frameUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .putUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);
      request.add(
        utf8.encode(jsonEncode({'frameId': frameId, 'frame': frameId})),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return StoreEquipSuccess(frameId);
      } else if (response.statusCode == 400) {
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
          final errCode = decoded['error'];
          if (errCode == 'item_not_owned') {
            return const StoreEquipNotOwned();
          }
          if (errCode == 'invalid_frame') {
            return const StoreEquipInvalidFrame(
              AppStrings.storeInvalidFrameError,
            );
          }
          if (decoded['message'] is String &&
              (decoded['message'] as String).trim().isNotEmpty) {
            return StoreEquipInvalidFrame(decoded['message'] as String);
          }
        } catch (_) {}
        return const StoreEquipInvalidFrame();
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const StoreEquipAccountDeleted();
      } else if (response.statusCode >= 500) {
        return const StoreEquipNetworkError(AppStrings.storeServerError);
      }
      return const StoreEquipNetworkError();
    } catch (e) {
      return StoreEquipNetworkError(AppStrings.storeNetworkError, e);
    } finally {
      client.close();
    }
  }

  @override
  Future<StorePurchaseEnergyResult> purchaseEnergy(String pack) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      return const StorePurchaseEnergyNetworkError();
    }

    final uri = Uri.parse(ServerConfig.energyUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);
      request.add(utf8.encode(jsonEncode({'pack': pack})));

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        return StorePurchaseEnergySuccess(
          coins: (decoded['coins'] as num?)?.toInt() ?? 0,
          energy: (decoded['energy'] as num?)?.toInt() ?? 0,
          max: (decoded['max'] as num?)?.toInt() ?? 5,
          nextEnergyAtMs: (decoded['nextEnergyAtMs'] as num?)?.toInt(),
          serverNowMs:
              (decoded['serverNowMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
          pack: decoded['pack'] as String? ?? pack,
        );
      } else if (response.statusCode == 402) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>?;
        final msg =
            decoded?['message'] as String? ?? AppStrings.insufficientCoins;
        final coins = (decoded?['coins'] as num?)?.toInt();
        return StorePurchaseEnergyNotEnoughCoins(msg, coins);
      } else if (response.statusCode == 400) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>?;
        final error = decoded?['error'] as String?;
        final msg = decoded?['message'] as String?;
        if (error == 'energy_full') {
          return StorePurchaseEnergyFull(msg ?? AppStrings.energyAlreadyFull);
        }
        if (error == 'energy_disabled') {
          return StorePurchaseEnergyDisabled(msg ?? AppStrings.energyDisabled);
        }
        return StorePurchaseEnergyNetworkError(
          msg ?? AppStrings.storeGenericError,
        );
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const StorePurchaseEnergyNetworkError(AppStrings.accountDeleted);
      }
      return const StorePurchaseEnergyNetworkError();
    } catch (e) {
      return StorePurchaseEnergyNetworkError(AppStrings.storeNetworkError, e);
    } finally {
      client.close();
    }
  }
}

final storeApiClientProvider = Provider<StoreApiClient>((ref) {
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpStoreApiClient(
    authTokenProvider: const FirebaseAuthTokenProvider(),
    onAccountDeleted: onDeleted,
  );
});
