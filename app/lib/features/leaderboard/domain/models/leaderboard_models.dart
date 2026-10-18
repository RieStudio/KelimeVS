import 'package:flutter/foundation.dart';
import '../../../../core/strings/app_strings.dart';

@immutable
class LeaderboardEntry {
  final int rank;
  final String nickname;
  final int wins;
  final bool isMe;

  const LeaderboardEntry({
    required this.rank,
    required this.nickname,
    required this.wins,
    required this.isMe,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num).toInt(),
      nickname: (json['nickname'] as String?)?.trim() ?? '',
      wins: (json['wins'] as num).toInt(),
      isMe: json['isMe'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaderboardEntry &&
          runtimeType == other.runtimeType &&
          rank == other.rank &&
          nickname == other.nickname &&
          wins == other.wins &&
          isMe == other.isMe;

  @override
  int get hashCode => Object.hash(rank, nickname, wins, isMe);
}

@immutable
class LeaderboardMe {
  final int rank;
  final int wins;

  const LeaderboardMe({
    required this.rank,
    required this.wins,
  });

  factory LeaderboardMe.fromJson(Map<String, dynamic> json) {
    return LeaderboardMe(
      rank: (json['rank'] as num).toInt(),
      wins: (json['wins'] as num).toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaderboardMe &&
          runtimeType == other.runtimeType &&
          rank == other.rank &&
          wins == other.wins;

  @override
  int get hashCode => Object.hash(rank, wins);
}

@immutable
class LeaderboardData {
  final String weekKey;
  final int endsAt;
  final List<LeaderboardEntry> top;
  final LeaderboardMe? me;

  const LeaderboardData({
    required this.weekKey,
    required this.endsAt,
    required this.top,
    this.me,
  });

  factory LeaderboardData.fromJson(Map<String, dynamic> json) {
    final topList = (json['top'] as List<dynamic>?)
            ?.map((item) => LeaderboardEntry.fromJson(item as Map<String, dynamic>))
            .toList() ??
        const [];

    final meJson = json['me'] as Map<String, dynamic>?;
    final me = meJson != null ? LeaderboardMe.fromJson(meJson) : null;

    return LeaderboardData(
      weekKey: (json['weekKey'] as String?) ?? '',
      endsAt: (json['endsAt'] as num?)?.toInt() ?? 0,
      top: topList,
      me: me,
    );
  }

  /// Kalan süreyi formatlar (örn. "4g 12s" veya "2s 15d" veya "Süre doldu")
  String formatRemainingTime([DateTime? now]) {
    final currentMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final diffMs = endsAt - currentMs;
    if (diffMs <= 0) return AppStrings.timeExpired;

    final duration = Duration(milliseconds: diffMs);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    if (days > 0) {
      return '$days${AppStrings.daysUnit} $hours${AppStrings.hoursUnit}';
    } else if (hours > 0) {
      return '$hours${AppStrings.hoursUnit} $minutes${AppStrings.minutesUnit}';
    } else {
      final safeMinutes = minutes > 0 ? minutes : 1;
      return '$safeMinutes${AppStrings.minutesUnit}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaderboardData &&
          runtimeType == other.runtimeType &&
          weekKey == other.weekKey &&
          endsAt == other.endsAt &&
          listEquals(top, other.top) &&
          me == other.me;

  @override
  int get hashCode => Object.hash(weekKey, endsAt, Object.hashAll(top), me);
}

