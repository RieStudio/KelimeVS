import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
import '../../../core/strings/app_strings.dart';
import '../../auth/application/auth_notifier.dart';
import '../../online/data/auth_token_provider.dart';
import '../domain/blocked_user_model.dart';

sealed class BlockUserResult {
  const BlockUserResult();
}

class BlockUserSuccess extends BlockUserResult {
  final String id;
  const BlockUserSuccess(this.id);
}

class BlockUserError extends BlockUserResult {
  final String message;
  final bool isLimitReached;
  final bool isExpired;
  const BlockUserError(
    this.message, {
    this.isLimitReached = false,
    this.isExpired = false,
  });
}

sealed class ReportUserResult {
  const ReportUserResult();
}

class ReportUserSuccess extends ReportUserResult {
  const ReportUserSuccess();
}

class ReportUserError extends ReportUserResult {
  final String message;
  final bool isAlreadyReported;
  final bool isDailyLimit;
  final bool isExpired;
  const ReportUserError(
    this.message, {
    this.isAlreadyReported = false,
    this.isDailyLimit = false,
    this.isExpired = false,
  });
}

abstract interface class BlockedUsersApiClient {
  Future<List<BlockedUser>> getBlockedUsers();
  Future<bool> unblockUser(String id);
  Future<BlockUserResult> blockUser(String matchId);
  Future<ReportUserResult> reportUser({
    required String matchId,
    required String reason,
  });
}

class HttpBlockedUsersApiClient implements BlockedUsersApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  HttpBlockedUsersApiClient({
    AuthTokenProvider? authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  }) : authTokenProvider = authTokenProvider ?? const FirebaseAuthTokenProvider();

  @override
  Future<List<BlockedUser>> getBlockedUsers() async {
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/me/blocks'));

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'GET',
        clientFactory: clientFactory,
      );

      if (response == null) return const [];

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonList();
        return decoded
            .map((e) => BlockedUser.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const [];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> unblockUser(String id) async {
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/me/blocks/$id'));

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'DELETE',
        clientFactory: clientFactory,
      );

      if (response == null) return false;

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BlockUserResult> blockUser(String matchId) async {
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/matches/$matchId/block'));

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
      );

      if (response == null) {
        return const BlockUserError(AppStrings.blockGenericError);
      }

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        return BlockUserSuccess(decoded['id'] as String? ?? '');
      } else if (response.statusCode == 400) {
        return const BlockUserError(AppStrings.blockLimitReached, isLimitReached: true);
      } else if (response.statusCode == 410) {
        try {
          final decoded = response.decodeJsonMap();
          if (decoded['error'] == 'account_deleted') {
            onAccountDeleted?.call();
            return const BlockUserError(AppStrings.blockGenericError);
          }
        } catch (_) {}
        return const BlockUserError(AppStrings.blockMatchExpired, isExpired: true);
      }
      return const BlockUserError(AppStrings.blockGenericError);
    } catch (_) {
      return const BlockUserError(AppStrings.blockGenericError);
    }
  }

  @override
  Future<ReportUserResult> reportUser({
    required String matchId,
    required String reason,
  }) async {
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/matches/$matchId/report'));

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
        jsonBody: {'reason': reason},
      );

      if (response == null) {
        return const ReportUserError(AppStrings.reportGenericError);
      }

      if (response.statusCode == 200) {
        return const ReportUserSuccess();
      } else if (response.statusCode == 409) {
        return const ReportUserError(AppStrings.reportAlreadyReported, isAlreadyReported: true);
      } else if (response.statusCode == 429) {
        return const ReportUserError(AppStrings.reportDailyLimit, isDailyLimit: true);
      } else if (response.statusCode == 410) {
        try {
          final decoded = response.decodeJsonMap();
          if (decoded['error'] == 'account_deleted') {
            onAccountDeleted?.call();
            return const ReportUserError(AppStrings.reportGenericError);
          }
        } catch (_) {}
        return const ReportUserError(AppStrings.reportMatchExpired, isExpired: true);
      }
      return const ReportUserError(AppStrings.reportGenericError);
    } catch (_) {
      return const ReportUserError(AppStrings.reportGenericError);
    }
  }
}

final blockedUsersApiClientProvider = Provider<BlockedUsersApiClient>((ref) {
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpBlockedUsersApiClient(onAccountDeleted: onDeleted);
});
