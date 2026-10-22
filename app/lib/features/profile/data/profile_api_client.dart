import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../online/data/auth_token_provider.dart';
import '../domain/energy_state.dart';

class UserProfileModel {
  final String uid;
  final String? nickname;
  final int coins;
  final int played;
  final int won;
  final int lost;
  final int createdAt;
  final String equippedFrame;
  final EnergyState? energy;
  final int? serverNowMs;

  const UserProfileModel({
    required this.uid,
    required this.nickname,
    required this.coins,
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.createdAt = 0,
    this.equippedFrame = 'classic',
    this.energy,
    this.serverNowMs,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>?;
    final energyJson = json['energy'] as Map<String, dynamic>?;
    return UserProfileModel(
      uid: json['uid'] as String? ?? '',
      nickname: json['nickname'] as String?,
      coins: (json['coins'] as num?)?.toInt() ?? 100,
      played: (stats?['played'] as num?)?.toInt() ?? 0,
      won: (stats?['won'] as num?)?.toInt() ?? 0,
      lost: (stats?['lost'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      equippedFrame: json['equippedFrame'] as String? ?? 'classic',
      energy: energyJson != null ? EnergyState.fromJson(energyJson) : null,
      serverNowMs: (json['serverNowMs'] as num?)?.toInt(),
    );
  }
}

sealed class ProfileUpdateResult {
  const ProfileUpdateResult();
}

class ProfileUpdateSuccess extends ProfileUpdateResult {
  final String nickname;
  const ProfileUpdateSuccess(this.nickname);
}

class ProfileUpdateInvalidNickname extends ProfileUpdateResult {
  final String message;
  const ProfileUpdateInvalidNickname(this.message);
}

class ProfileUpdateNetworkError extends ProfileUpdateResult {
  final Object error;
  const ProfileUpdateNetworkError(this.error);
}

abstract interface class ProfileApiClient {
  Future<UserProfileModel?> getProfile();
  Future<ProfileUpdateResult> updateNickname(String nickname);
  Future<bool> deleteProfile();
}

class HttpProfileApiClient implements ProfileApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  const HttpProfileApiClient({
    required this.authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  });

  HttpClient _createClient(Duration timeout) {
    if (clientFactory != null) return clientFactory!();
    return HttpClient()..connectionTimeout = timeout;
  }

  @override
  Future<UserProfileModel?> getProfile() async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) return null;

    final uri = Uri.parse(ServerConfig.meUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        return UserProfileModel.fromJson(decoded);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return null;
      }
      return null;
    } catch (_) {
      // Ağ hatasında sessizce null döner (çevrimdışı dayanıklılık)
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      return const ProfileUpdateNetworkError('Auth token unavailable');
    }

    final uri = Uri.parse(ServerConfig.nicknameUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .putUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );

      final bodyBytes = utf8.encode(jsonEncode({'nickname': nickname}));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final normalized = decoded['nickname'] as String? ?? nickname.trim();
        return ProfileUpdateSuccess(normalized);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const ProfileUpdateNetworkError('account_deleted');
      } else if (response.statusCode == 400) {
        String msg = 'Geçersiz takma ad';
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
          msg = decoded['message'] as String? ?? msg;
        } catch (_) {}
        return ProfileUpdateInvalidNickname(msg);
      } else {
        return ProfileUpdateNetworkError(
          'HTTP ${response.statusCode}: $responseBody',
        );
      }
    } catch (e) {
      return ProfileUpdateNetworkError(e);
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> deleteProfile() async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      throw const SocketException('Yetkilendirme jetonu alınamadı');
    }

    final uri = Uri.parse(ServerConfig.meUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request = await client
          .deleteUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 410) {
        return true;
      }
      throw HttpException(
        'Hesap silinemedi (HTTP ${response.statusCode}: $responseBody)',
        uri: uri,
      );
    } finally {
      client.close();
    }
  }
}
