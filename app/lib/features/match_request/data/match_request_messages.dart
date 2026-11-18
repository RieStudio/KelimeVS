import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/utils/display_name_resolver.dart';
import '../domain/match_request_models.dart';

/// İstemciden /ws/user kanalına gönderilen temel mesaj sınıfı.
sealed class UserInboxClientMessage {
  const UserInboxClientMessage();
  Map<String, dynamic> toJson();
  String toWireJson() => jsonEncode(toJson());
}

class UserInboxPingMessage extends UserInboxClientMessage {
  const UserInboxPingMessage();

  @override
  Map<String, dynamic> toJson() => {'t': 'ping'};
}

class UserInboxPresenceMessage extends UserInboxClientMessage {
  final String state; // 'idle' | 'busy'

  const UserInboxPresenceMessage(this.state);

  @override
  Map<String, dynamic> toJson() => {
        't': 'presence',
        'state': state,
      };
}

class UserInboxSendRequestMessage extends UserInboxClientMessage {
  final MatchRequestOrigin origin;
  final String toUid;
  final String? matchId;

  UserInboxSendRequestMessage({
    required this.origin,
    required this.toUid,
    this.matchId,
  }) {
    if (toUid.trim().isEmpty) {
      throw ArgumentError.value(toUid, 'toUid', 'toUid cannot be empty');
    }
    if (origin == MatchRequestOrigin.rematch) {
      if (matchId == null || matchId!.trim().isEmpty) {
        throw ArgumentError('matchId is required when origin is rematch');
      }
    } else if (origin == MatchRequestOrigin.profile) {
      if (matchId != null && matchId!.trim().isNotEmpty) {
        throw ArgumentError('matchId must not be provided when origin is profile');
      }
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        't': 'send_match_request',
        'origin': origin.toWireString(),
        'toUid': toUid,
        if (matchId != null && matchId!.isNotEmpty) 'matchId': matchId,
      };
}

class UserInboxAcceptRequestMessage extends UserInboxClientMessage {
  final String id;

  const UserInboxAcceptRequestMessage(this.id);

  @override
  Map<String, dynamic> toJson() => {
        't': 'accept_match_request',
        'id': id,
      };
}

class UserInboxDeclineRequestMessage extends UserInboxClientMessage {
  final String id;

  const UserInboxDeclineRequestMessage(this.id);

  @override
  Map<String, dynamic> toJson() => {
        't': 'decline_match_request',
        'id': id,
      };
}

class UserInboxCancelRequestMessage extends UserInboxClientMessage {
  final String id;

  const UserInboxCancelRequestMessage(this.id);

  @override
  Map<String, dynamic> toJson() => {
        't': 'cancel_match_request',
        'id': id,
      };
}

/// Sunucudan /ws/user kanalı üzerinden alınan mesajların temel sınıfı.
sealed class UserInboxServerMessage {
  const UserInboxServerMessage();
}

class UserInboxPongMessage extends UserInboxServerMessage {
  const UserInboxPongMessage();

  @override
  String toString() => 'UserInboxPongMessage()';
}

class UserInboxRequestReceivedMessage extends UserInboxServerMessage {
  final String id;
  final String fromUid;
  final String fromNickname;
  final String fromFrame;
  final MatchRequestType type;
  final MatchRequestOrigin origin;
  final int expiresAtMs;
  final bool isSnapshot;

  const UserInboxRequestReceivedMessage({
    required this.id,
    required this.fromUid,
    required this.fromNickname,
    required this.fromFrame,
    required this.type,
    required this.origin,
    required this.expiresAtMs,
    this.isSnapshot = false,
  });

  @override
  String toString() =>
      'UserInboxRequestReceivedMessage(id: $id, fromUid: $fromUid, fromNickname: $fromNickname, type: $type, origin: $origin, isSnapshot: $isSnapshot)';
}

class UserInboxRequestSentMessage extends UserInboxServerMessage {
  final String id;
  final String toUid;
  final String toNickname;
  final MatchRequestType type;
  final MatchRequestOrigin origin;
  final int expiresAtMs;
  final bool isSnapshot;

  const UserInboxRequestSentMessage({
    required this.id,
    required this.toUid,
    required this.toNickname,
    required this.type,
    required this.origin,
    required this.expiresAtMs,
    this.isSnapshot = false,
  });

  @override
  String toString() =>
      'UserInboxRequestSentMessage(id: $id, toUid: $toUid, toNickname: $toNickname, type: $type, origin: $origin, isSnapshot: $isSnapshot)';
}

class UserInboxRequestStatusMessage extends UserInboxServerMessage {
  final String id;
  final MatchRequestEndStatus status;

  const UserInboxRequestStatusMessage({
    required this.id,
    required this.status,
  });

  @override
  String toString() =>
      'UserInboxRequestStatusMessage(id: $id, status: $status)';
}

class UserInboxRequestErrorMessage extends UserInboxServerMessage {
  final MatchRequestErrorCode code;
  final int? retryAfterSec;

  const UserInboxRequestErrorMessage({
    required this.code,
    this.retryAfterSec,
  });

  @override
  String toString() =>
      'UserInboxRequestErrorMessage(code: $code, retryAfterSec: $retryAfterSec)';
}

class UserInboxMatchedMessage extends UserInboxServerMessage {
  final String matchId;
  final String opponentName;
  final String opponentFrame;
  final String? opponentUid;
  final bool isFriendly;

  const UserInboxMatchedMessage({
    required this.matchId,
    required this.opponentName,
    required this.opponentFrame,
    this.opponentUid,
    required this.isFriendly,
  });

  @override
  String toString() =>
      'UserInboxMatchedMessage(matchId: $matchId, opponentName: $opponentName, opponentUid: $opponentUid, isFriendly: $isFriendly)';
}

/// Gelen ham mesajı güvenli ve toleranslı şekilde ayrıştırır.
/// Bozuk JSON veya bilinmeyen `t` durumunda bağlantıyı kesmez, null döner.
UserInboxServerMessage? parseUserInboxServerMessage(
  dynamic raw, {
  bool isSnapshot = false,
}) {
  if (raw == null) return null;

  Map<String, dynamic>? data;
  if (raw is Map<String, dynamic>) {
    data = raw;
  } else if (raw is Map) {
    data = Map<String, dynamic>.from(raw);
  } else if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[parseUserInboxServerMessage] JSON decode error: $e');
      }
      return null;
    }
  }

  if (data == null) return null;

  final t = data['t'];
  if (t is! String) return null;

  switch (t) {
    case 'pong':
      return const UserInboxPongMessage();

    case 'match_request_received':
      final id = data['id'];
      final fromUid = data['fromUid'];
      final fromNickname = data['fromNickname'];
      final fromFrame = data['fromFrame'];
      final typeRaw = data['type'];
      final originRaw = data['origin'];
      final expiresAt = data['expiresAtMs'];

      if (id is! String || fromUid is! String || expiresAt is! num) {
        return null;
      }

      final resolvedFrom = DisplayNameResolver.resolve(
        nickname: fromNickname is String ? fromNickname : null,
        uid: fromUid,
      );

      return UserInboxRequestReceivedMessage(
        id: id,
        fromUid: fromUid,
        fromNickname: resolvedFrom,
        fromFrame: fromFrame is String ? fromFrame : 'classic',
        type: MatchRequestType.fromString(typeRaw?.toString() ?? 'friendly'),
        origin: MatchRequestOrigin.fromString(originRaw?.toString() ?? 'profile'),
        expiresAtMs: expiresAt.toInt(),
        isSnapshot: isSnapshot,
      );

    case 'match_request_sent':
      final id = data['id'];
      final toUid = data['toUid'];
      final toNickname = data['toNickname'];
      final typeRaw = data['type'];
      final originRaw = data['origin'];
      final expiresAt = data['expiresAtMs'];

      if (id is! String || toUid is! String || expiresAt is! num) {
        return null;
      }

      final resolvedTo = DisplayNameResolver.resolve(
        nickname: toNickname is String ? toNickname : null,
        uid: toUid,
      );

      return UserInboxRequestSentMessage(
        id: id,
        toUid: toUid,
        toNickname: resolvedTo,
        type: MatchRequestType.fromString(typeRaw?.toString() ?? 'friendly'),
        origin: MatchRequestOrigin.fromString(originRaw?.toString() ?? 'profile'),
        expiresAtMs: expiresAt.toInt(),
        isSnapshot: isSnapshot,
      );

    case 'match_request_status':
      final id = data['id'];
      final statusRaw = data['status'];
      if (id is! String || statusRaw is! String) return null;

      return UserInboxRequestStatusMessage(
        id: id,
        status: MatchRequestEndStatus.fromString(statusRaw),
      );

    case 'match_request_error':
      final codeRaw = data['code'];
      final retryAfter = data['retryAfterSec'];
      final code = MatchRequestErrorCode.fromString(codeRaw?.toString() ?? 'invalid');

      return UserInboxRequestErrorMessage(
        code: code,
        retryAfterSec: (retryAfter is num) ? retryAfter.toInt() : null,
      );

    case 'matched':
      final matchId = data['matchId'];
      final opponentName = data['opponentName'];
      final opponentFrame = data['opponentFrame'];
      final opponentUid = data['opponentUid'];
      final isFriendly = data['isFriendly'];

      if (matchId is! String || opponentName is! String) return null;

      return UserInboxMatchedMessage(
        matchId: matchId,
        opponentName: opponentName,
        opponentFrame: opponentFrame is String ? opponentFrame : 'classic',
        opponentUid: opponentUid is String ? opponentUid : null,
        isFriendly: isFriendly is bool ? isFriendly : false,
      );

    default:
      if (kDebugMode) {
        debugPrint('[parseUserInboxServerMessage] Unknown message type: $t');
      }
      return null;
  }
}
