import 'dart:async';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
import '../../../core/strings/app_strings.dart';
import '../../online/data/auth_token_provider.dart';
import '../domain/public_profile_model.dart';

abstract interface class PublicProfileApiClient {
  Future<PublicProfile> getPublicProfile(String uid);
  Future<String> blockUser(String uid);
  Future<void> unblockUser(String uid);
  Future<String> reportUser(String uid, String reason);
}

class HttpPublicProfileApiClient implements PublicProfileApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  HttpPublicProfileApiClient({
    AuthTokenProvider? authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  }) : authTokenProvider =
            authTokenProvider ?? const FirebaseAuthTokenProvider();

  @override
  Future<PublicProfile> getPublicProfile(String uid) async {
    final uri = Uri.parse(
      ServerConfig.joinUrl(ServerConfig.serverUrl, '/users/$uid/public'),
    );

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'GET',
        clientFactory: clientFactory,
      );

      if (response == null) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.networkOrTimeout,
          message: AppStrings.profileConnectionError,
        );
      }

      if (response.statusCode == 200) {
        return PublicProfile.fromJson(response.decodeJsonMap());
      } else if (response.statusCode == 404) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.notFound,
          message: AppStrings.profileNotFound,
          statusCode: 404,
        );
      } else if (response.statusCode == 410) {
        final decoded = _tryDecodeJsonMap(response.body);
        if (decoded?['error'] == 'account_deleted') {
          onAccountDeleted?.call();
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.deleted,
          message: AppStrings.profileDeleted,
          statusCode: 410,
        );
      } else if (response.statusCode == 401) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unauthorized,
          message: AppStrings.authGenericError,
          statusCode: 401,
        );
      } else if (response.statusCode == 400) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.invalidUid,
          message: AppStrings.profileGenericError,
          statusCode: 400,
        );
      } else {
        throw PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.profileGenericError,
          statusCode: response.statusCode,
        );
      }
    } on PublicProfileException {
      rethrow;
    } catch (e) {
      throw PublicProfileException(
        kind: PublicProfileErrorKind.networkOrTimeout,
        message: AppStrings.profileConnectionError,
        cause: e,
      );
    }
  }

  @override
  Future<String> blockUser(String uid) async {
    final uri = Uri.parse(
      ServerConfig.joinUrl(ServerConfig.serverUrl, '/users/$uid/block'),
    );

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
      );

      if (response == null) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.networkOrTimeout,
          message: AppStrings.profileConnectionError,
        );
      }

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        return decoded['blockId'] as String? ?? '';
      } else if (response.statusCode == 400) {
        final decoded = _tryDecodeJsonMap(response.body);
        final err = decoded?['error'] as String?;
        if (err == 'cannot_block_self') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.cannotBlockSelf,
            message: AppStrings.profileCannotBlockSelf,
            statusCode: 400,
          );
        } else if (err == 'block_limit_reached') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.blockLimit,
            message: AppStrings.profileBlockLimit,
            statusCode: 400,
          );
        } else if (err == 'invalid_uid') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.invalidUid,
            message: AppStrings.profileGenericError,
            statusCode: 400,
          );
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.profileGenericError,
          statusCode: 400,
        );
      } else if (response.statusCode == 404) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.notFound,
          message: AppStrings.profileNotFound,
          statusCode: 404,
        );
      } else if (response.statusCode == 410) {
        final decoded = _tryDecodeJsonMap(response.body);
        if (decoded?['error'] == 'account_deleted') {
          onAccountDeleted?.call();
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.deleted,
          message: AppStrings.profileDeleted,
          statusCode: 410,
        );
      } else if (response.statusCode == 401) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unauthorized,
          message: AppStrings.authGenericError,
          statusCode: 401,
        );
      } else {
        throw PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.profileGenericError,
          statusCode: response.statusCode,
        );
      }
    } on PublicProfileException {
      rethrow;
    } catch (e) {
      throw PublicProfileException(
        kind: PublicProfileErrorKind.networkOrTimeout,
        message: AppStrings.profileConnectionError,
        cause: e,
      );
    }
  }

  @override
  Future<void> unblockUser(String uid) async {
    final uri = Uri.parse(
      ServerConfig.joinUrl(ServerConfig.serverUrl, '/users/$uid/block'),
    );

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'DELETE',
        clientFactory: clientFactory,
      );

      if (response == null) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.networkOrTimeout,
          message: AppStrings.profileConnectionError,
        );
      }

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unauthorized,
          message: AppStrings.authGenericError,
          statusCode: 401,
        );
      } else if (response.statusCode == 410) {
        final decoded = _tryDecodeJsonMap(response.body);
        if (decoded?['error'] == 'account_deleted') {
          onAccountDeleted?.call();
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.deleted,
          message: AppStrings.profileDeleted,
          statusCode: 410,
        );
      } else {
        throw PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.unblockGenericError,
          statusCode: response.statusCode,
        );
      }
    } on PublicProfileException {
      rethrow;
    } catch (e) {
      throw PublicProfileException(
        kind: PublicProfileErrorKind.networkOrTimeout,
        message: AppStrings.profileConnectionError,
        cause: e,
      );
    }
  }

  @override
  Future<String> reportUser(String uid, String reason) async {
    final uri = Uri.parse(
      ServerConfig.joinUrl(ServerConfig.serverUrl, '/users/$uid/report'),
    );

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
        jsonBody: {'reason': reason},
      );

      if (response == null) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.networkOrTimeout,
          message: AppStrings.profileConnectionError,
        );
      }

      if (response.statusCode == 200) {
        final decoded = _tryDecodeJsonMap(response.body);
        return decoded?['reportId'] as String? ?? '';
      } else if (response.statusCode == 400) {
        final decoded = _tryDecodeJsonMap(response.body);
        final err = decoded?['error'] as String?;
        if (err == 'cannot_report_self') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.cannotReportSelf,
            message: AppStrings.profileCannotReportSelf,
            statusCode: 400,
          );
        } else if (err == 'invalid_reason') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.invalidReason,
            message: AppStrings.profileGenericError,
            statusCode: 400,
          );
        } else if (err == 'invalid_uid') {
          throw const PublicProfileException(
            kind: PublicProfileErrorKind.invalidUid,
            message: AppStrings.profileGenericError,
            statusCode: 400,
          );
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.profileGenericError,
          statusCode: 400,
        );
      } else if (response.statusCode == 404) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.notFound,
          message: AppStrings.profileNotFound,
          statusCode: 404,
        );
      } else if (response.statusCode == 409) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.alreadyReported,
          message: AppStrings.profileAlreadyReported,
          statusCode: 409,
        );
      } else if (response.statusCode == 410) {
        final decoded = _tryDecodeJsonMap(response.body);
        if (decoded?['error'] == 'account_deleted') {
          onAccountDeleted?.call();
        }
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.deleted,
          message: AppStrings.profileDeleted,
          statusCode: 410,
        );
      } else if (response.statusCode == 429) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.dailyLimit,
          message: AppStrings.profileDailyReportLimit,
          statusCode: 429,
        );
      } else if (response.statusCode == 401) {
        throw const PublicProfileException(
          kind: PublicProfileErrorKind.unauthorized,
          message: AppStrings.authGenericError,
          statusCode: 401,
        );
      } else {
        throw PublicProfileException(
          kind: PublicProfileErrorKind.unknown,
          message: AppStrings.reportGenericError,
          statusCode: response.statusCode,
        );
      }
    } on PublicProfileException {
      rethrow;
    } catch (e) {
      throw PublicProfileException(
        kind: PublicProfileErrorKind.networkOrTimeout,
        message: AppStrings.profileConnectionError,
        cause: e,
      );
    }
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    try {
      final decoded = responseJsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}

dynamic responseJsonDecode(String body) {
  return AuthHttpResponse(statusCode: 200, body: body).decodeJsonMap();
}
