import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/app_build_info.dart';
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

  HttpClient _createClient() => clientFactory != null ? clientFactory!() : HttpClient();

  @override
  Future<List<BlockedUser>> getBlockedUsers() async {
    final token = await authTokenProvider.getIdToken();
    if (token == null || token.isEmpty) return const [];

    final client = _createClient();
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/me/blocks'));

    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);

      final response = await request.close().timeout(const Duration(seconds: 8));
      final responseBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as List<dynamic>;
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
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> unblockUser(String id) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null || token.isEmpty) return false;

    final client = _createClient();
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/me/blocks/$id'));

    try {
      final request = await client.deleteUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return false;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Future<BlockUserResult> blockUser(String matchId) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null || token.isEmpty) {
      return const BlockUserError(AppStrings.blockGenericError);
    }

    final client = _createClient();
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/matches/$matchId/block'));

    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);

      final response = await request.close().timeout(const Duration(seconds: 8));
      final responseBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        return BlockUserSuccess(decoded['id'] as String? ?? '');
      } else if (response.statusCode == 400) {
        return const BlockUserError(AppStrings.blockLimitReached, isLimitReached: true);
      } else if (response.statusCode == 410) {
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
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
    } finally {
      client.close();
    }
  }

  @override
  Future<ReportUserResult> reportUser({
    required String matchId,
    required String reason,
  }) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null || token.isEmpty) {
      return const ReportUserError(AppStrings.reportGenericError);
    }

    final client = _createClient();
    final uri = Uri.parse(ServerConfig.joinUrl(ServerConfig.serverUrl, '/matches/$matchId/report'));

    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      AppBuildInfo.applyHeaders(request.headers);
      request.add(utf8.encode(jsonEncode({'reason': reason})));

      final response = await request.close().timeout(const Duration(seconds: 8));
      final responseBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return const ReportUserSuccess();
      } else if (response.statusCode == 409) {
        return const ReportUserError(AppStrings.reportAlreadyReported, isAlreadyReported: true);
      } else if (response.statusCode == 429) {
        return const ReportUserError(AppStrings.reportDailyLimit, isDailyLimit: true);
      } else if (response.statusCode == 410) {
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
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
    } finally {
      client.close();
    }
  }
}

final blockedUsersApiClientProvider = Provider<BlockedUsersApiClient>((ref) {
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpBlockedUsersApiClient(onAccountDeleted: onDeleted);
});
