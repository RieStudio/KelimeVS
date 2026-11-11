import 'package:flutter/foundation.dart';

@immutable
class PublicProfileStats {
  final int played;
  final int won;
  final int lost;
  final int winRate;

  const PublicProfileStats({
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.winRate = 0,
  });

  String get winRateDisplay {
    if (played <= 0) return '—';
    return '%$winRate';
  }

  factory PublicProfileStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PublicProfileStats();
    final played = (json['played'] as num?)?.toInt() ?? 0;
    final won = (json['won'] as num?)?.toInt() ?? 0;
    final lost = (json['lost'] as num?)?.toInt() ?? 0;
    final winRate = (json['winRate'] as num?)?.toInt() ??
        (played > 0 ? ((won / played) * 100).round() : 0);
    return PublicProfileStats(
      played: played,
      won: won,
      lost: lost,
      winRate: winRate,
    );
  }

  Map<String, dynamic> toJson() => {
        'played': played,
        'won': won,
        'lost': lost,
        'winRate': winRate,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileStats &&
          runtimeType == other.runtimeType &&
          played == other.played &&
          won == other.won &&
          lost == other.lost &&
          winRate == other.winRate;

  @override
  int get hashCode => Object.hash(played, won, lost, winRate);

  @override
  String toString() =>
      'PublicProfileStats(played: $played, won: $won, lost: $lost, winRate: $winRate)';
}

@immutable
class PublicProfile {
  final String uid;
  final String nickname;
  final String equippedFrame;
  final PublicProfileStats stats;
  final bool isGuest;
  final bool isBlocked;
  final String? blockId;

  const PublicProfile({
    required this.uid,
    required this.nickname,
    this.equippedFrame = 'classic',
    this.stats = const PublicProfileStats(),
    this.isGuest = false,
    this.isBlocked = false,
    this.blockId,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final statsRaw = json['stats'];
    final stats = statsRaw is Map<String, dynamic>
        ? PublicProfileStats.fromJson(statsRaw)
        : const PublicProfileStats();

    final rawFrame = json['equippedFrame'] as String?;
    final frame = (rawFrame != null && rawFrame.trim().isNotEmpty)
        ? rawFrame.trim()
        : 'classic';

    return PublicProfile(
      uid: (json['uid'] as String?)?.trim() ?? '',
      nickname: (json['nickname'] as String?)?.trim() ?? '',
      equippedFrame: frame,
      stats: stats,
      isGuest: json['isGuest'] == true,
      isBlocked: json['isBlocked'] == true,
      blockId: json['blockId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'equippedFrame': equippedFrame,
        'stats': stats.toJson(),
        'isGuest': isGuest,
        'isBlocked': isBlocked,
        if (blockId != null) 'blockId': blockId,
      };

  PublicProfile copyWith({
    String? uid,
    String? nickname,
    String? equippedFrame,
    PublicProfileStats? stats,
    bool? isGuest,
    bool? isBlocked,
    String? blockId,
    bool clearBlockId = false,
  }) {
    return PublicProfile(
      uid: uid ?? this.uid,
      nickname: nickname ?? this.nickname,
      equippedFrame: equippedFrame ?? this.equippedFrame,
      stats: stats ?? this.stats,
      isGuest: isGuest ?? this.isGuest,
      isBlocked: isBlocked ?? this.isBlocked,
      blockId: clearBlockId ? null : (blockId ?? this.blockId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfile &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          nickname == other.nickname &&
          equippedFrame == other.equippedFrame &&
          stats == other.stats &&
          isGuest == other.isGuest &&
          isBlocked == other.isBlocked &&
          blockId == other.blockId;

  @override
  int get hashCode => Object.hash(
        uid,
        nickname,
        equippedFrame,
        stats,
        isGuest,
        isBlocked,
        blockId,
      );

  @override
  String toString() =>
      'PublicProfile(uid: $uid, nickname: $nickname, equippedFrame: $equippedFrame, stats: $stats, isGuest: $isGuest, isBlocked: $isBlocked, blockId: $blockId)';
}

enum PublicProfileErrorKind {
  notFound,
  deleted,
  alreadyReported,
  dailyLimit,
  blockLimit,
  cannotBlockSelf,
  cannotReportSelf,
  invalidReason,
  invalidUid,
  unauthorized,
  networkOrTimeout,
  unknown,
}

class PublicProfileException implements Exception {
  final PublicProfileErrorKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  const PublicProfileException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.cause,
  });

  bool get isNotFound => kind == PublicProfileErrorKind.notFound;
  bool get isDeleted => kind == PublicProfileErrorKind.deleted;
  bool get isAlreadyReported => kind == PublicProfileErrorKind.alreadyReported;
  bool get isDailyLimit => kind == PublicProfileErrorKind.dailyLimit;
  bool get isBlockLimit => kind == PublicProfileErrorKind.blockLimit;
  bool get isCannotBlockSelf => kind == PublicProfileErrorKind.cannotBlockSelf;
  bool get isCannotReportSelf => kind == PublicProfileErrorKind.cannotReportSelf;
  bool get isUnauthorized => kind == PublicProfileErrorKind.unauthorized;
  bool get isNetworkOrTimeout => kind == PublicProfileErrorKind.networkOrTimeout;

  @override
  String toString() =>
      'PublicProfileException($kind, "$message", statusCode: $statusCode)';
}
