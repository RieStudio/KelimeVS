import 'dart:async';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
import '../../../core/strings/app_strings.dart';
import '../../online/data/auth_token_provider.dart';
import '../domain/energy_state.dart';

class UserStats {
  final int played;
  final int won;
  final int lost;
  final int correctAnswers;

  const UserStats({
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.correctAnswers = 0,
  });

  /// Kazanma oranı (0.0 - 1.0 aralığında). Hiç maç yoksa (played == 0) null döner.
  double? get winRateRatio {
    if (played <= 0) return null;
    return won / played;
  }

  /// Tam sayı yüzde olarak biçimlendirilmiş kazanma oranı (örn. %67, %33, %100, %0).
  /// played == 0 ise "—" döner.
  String get winRateDisplay {
    if (played <= 0) return '—';
    final ratio = won / played;
    final percentage = (ratio * 100).round();
    return '%$percentage';
  }

  factory UserStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserStats();
    return UserStats(
      played: (json['played'] as num?)?.toInt() ?? 0,
      won: (json['won'] as num?)?.toInt() ?? 0,
      lost: (json['lost'] as num?)?.toInt() ?? 0,
      correctAnswers: (json['correctAnswers'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'played': played,
        'won': won,
        'lost': lost,
        'correctAnswers': correctAnswers,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserStats &&
          runtimeType == other.runtimeType &&
          played == other.played &&
          won == other.won &&
          lost == other.lost &&
          correctAnswers == other.correctAnswers;

  @override
  int get hashCode =>
      played.hashCode ^ won.hashCode ^ lost.hashCode ^ correctAnswers.hashCode;
}

class FrameMigrationInfo {
  final int refundedCoins;
  final List<String> removedFrames;

  const FrameMigrationInfo({
    required this.refundedCoins,
    required this.removedFrames,
  });

  factory FrameMigrationInfo.fromJson(Map<String, dynamic> json) {
    return FrameMigrationInfo(
      refundedCoins: (json['refundedCoins'] as num?)?.toInt() ?? 0,
      removedFrames: (json['removedFrames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

class UserProfileModel {
  final String uid;
  final String? nickname;
  final int coins;
  final UserStats stats;
  final int createdAt;
  final String equippedFrame;
  final EnergyState? energy;
  final int? serverNowMs;
  final FrameMigrationInfo? frameMigration;
  final bool isGuest;

  const UserProfileModel({
    required this.uid,
    required this.nickname,
    required this.coins,
    this.stats = const UserStats(),
    this.createdAt = 0,
    this.equippedFrame = 'classic',
    this.energy,
    this.serverNowMs,
    this.frameMigration,
    this.isGuest = false,
  });

  int get played => stats.played;
  int get won => stats.won;
  int get lost => stats.lost;
  int get correctAnswers => stats.correctAnswers;
  double? get winRateRatio => stats.winRateRatio;
  String get winRateDisplay => stats.winRateDisplay;

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    final statsJson = json['stats'] as Map<String, dynamic>?;
    final energyJson = json['energy'] as Map<String, dynamic>?;
    final migrationJson = json['frameMigration'] as Map<String, dynamic>?;
    return UserProfileModel(
      uid: json['uid'] as String? ?? '',
      nickname: json['nickname'] as String?,
      coins: (json['coins'] as num?)?.toInt() ?? 100,
      stats: UserStats.fromJson(statsJson),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      equippedFrame: json['equippedFrame'] as String? ?? 'classic',
      energy: energyJson != null ? EnergyState.fromJson(energyJson) : null,
      serverNowMs: (json['serverNowMs'] as num?)?.toInt(),
      frameMigration: migrationJson != null
          ? FrameMigrationInfo.fromJson(migrationJson)
          : null,
      isGuest: json['isGuest'] as bool? ?? false,
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

class ProfileUpdateCooldown extends ProfileUpdateResult {
  final int remainingSeconds;
  final String message;
  const ProfileUpdateCooldown({
    required this.remainingSeconds,
    required this.message,
  });
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

  @override
  Future<UserProfileModel?> getProfile() async {
    final uri = Uri.parse(ServerConfig.meUrl);

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'GET',
        clientFactory: clientFactory,
      );

      if (response == null) return null;

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        return UserProfileModel.fromJson(decoded);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return null;
      }
      return null;
    } catch (_) {
      // Ağ hatasında sessizce null döner (çevrimdışı dayanıklılık)
      return null;
    }
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async {
    final uri = Uri.parse(ServerConfig.nicknameUrl);

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'PUT',
        clientFactory: clientFactory,
        jsonBody: {'nickname': nickname},
      );

      if (response == null) {
        return const ProfileUpdateNetworkError('Auth token unavailable');
      }

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        final normalized = decoded['nickname'] as String? ?? nickname.trim();
        return ProfileUpdateSuccess(normalized);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const ProfileUpdateNetworkError('account_deleted');
      } else if (response.statusCode == 403) {
        String msg = AppStrings.guestNicknameLocked;
        try {
          final decoded = response.decodeJsonMap();
          msg = decoded['message'] as String? ?? msg;
        } catch (_) {}
        return ProfileUpdateInvalidNickname(msg);
      } else if (response.statusCode == 429) {
        int remainingSeconds = 86400;
        String msg = AppStrings.nicknameCooldownError;
        try {
          final decoded = response.decodeJsonMap();
          msg = decoded['message'] as String? ?? msg;
          if (decoded['remainingSeconds'] is num) {
            remainingSeconds = (decoded['remainingSeconds'] as num).toInt();
          }
        } catch (_) {}
        return ProfileUpdateCooldown(
          remainingSeconds: remainingSeconds,
          message: msg,
        );
      } else if (response.statusCode == 400) {
        String msg = 'Geçersiz takma ad';
        try {
          final decoded = response.decodeJsonMap();
          msg = decoded['message'] as String? ?? msg;
        } catch (_) {}
        return ProfileUpdateInvalidNickname(msg);
      } else {
        return ProfileUpdateNetworkError(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      return ProfileUpdateNetworkError(e);
    }
  }

  @override
  Future<bool> deleteProfile() async {
    final uri = Uri.parse(ServerConfig.meUrl);

    final response = await AuthHttpExecutor.execute(
      authTokenProvider: authTokenProvider,
      uri: uri,
      method: 'DELETE',
      clientFactory: clientFactory,
    );

    if (response == null) {
      throw const SocketException('Yetkilendirme jetonu alınamadı');
    }

    if (response.statusCode == 200 || response.statusCode == 410) {
      return true;
    }
    throw HttpException(
      'Hesap silinemedi (HTTP ${response.statusCode}: ${response.body})',
      uri: uri,
    );
  }
}
