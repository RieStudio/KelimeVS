// Saf Dart - Flutter veya harici paket bağımlılığı yoktur.

import 'dart:convert';
import 'online_match_state.dart';

/// Maç sonundaki tur dökümü (final mesajında gelir).
class OnlineRoundRecord {
  final String questionId;
  final List<OnlineAttempt> attempts;
  final bool? winnerIsMe;
  final String reason;

  const OnlineRoundRecord({
    required this.questionId,
    required this.attempts,
    required this.winnerIsMe,
    required this.reason,
  });

  factory OnlineRoundRecord.fromJson(Map<String, dynamic> json) {
    return OnlineRoundRecord(
      questionId: json['questionId'] as String? ?? '',
      attempts: (json['attempts'] as List<dynamic>?)
              ?.map((e) => OnlineAttempt.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      winnerIsMe: json['winnerIsMe'] as bool?,
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'attempts': attempts.map((e) => e.toJson()).toList(),
        'winnerIsMe': winnerIsMe,
        'reason': reason,
      };
}

/// Sunucudan istemciye gelen tüm mesajların temel sealed sınıfı.
sealed class ServerMessage {
  const ServerMessage();
}

/// Bilinmeyen, bozuk veya protokol dışı sunucu mesajı.
class UnknownServerMessage extends ServerMessage {
  final dynamic raw;
  const UnknownServerMessage([this.raw]);

  @override
  String toString() => 'UnknownServerMessage(raw: $raw)';
}

/// Eşleştirme kuyruğuna başarıyla girildi bildirimi (`queued`).
class QueuedServerMessage extends ServerMessage {
  const QueuedServerMessage();

  @override
  String toString() => 'QueuedServerMessage()';
}

/// Eşleştirme kuyruğundan çıkıldı bildirimi (`cancelled`).
class CancelledServerMessage extends ServerMessage {
  const CancelledServerMessage();

  @override
  String toString() => 'CancelledServerMessage()';
}

/// Eşleşme bulundu bildirimi (`matched`).
class MatchedServerMessage extends ServerMessage {
  final String matchId;
  final String opponentName;
  final bool isFriendly;
  final String opponentFrame;

  const MatchedServerMessage({
    required this.matchId,
    required this.opponentName,
    this.isFriendly = false,
    this.opponentFrame = 'classic',
  });

  @override
  String toString() =>
      'MatchedServerMessage(matchId: $matchId, opponentName: $opponentName, isFriendly: $isFriendly)';
}

/// Arkadaş odası kuruldu bildirimi (`room_created`).
class RoomCreatedServerMessage extends ServerMessage {
  final String code;
  final int expiresAt;

  const RoomCreatedServerMessage({
    required this.code,
    required this.expiresAt,
  });

  @override
  String toString() =>
      'RoomCreatedServerMessage(code: $code, expiresAt: $expiresAt)';
}

/// Askıdaki arkadaş odasına devam edildi bildirimi (`room_resumed`).
class RoomResumedServerMessage extends ServerMessage {
  final String code;
  final int expiresAt;

  const RoomResumedServerMessage({
    required this.code,
    required this.expiresAt,
  });

  @override
  String toString() =>
      'RoomResumedServerMessage(code: $code, expiresAt: $expiresAt)';
}

/// Arkadaş odası süresi doldu bildirimi (`room_expired`).
class RoomExpiredServerMessage extends ServerMessage {
  const RoomExpiredServerMessage();

  @override
  String toString() => 'RoomExpiredServerMessage()';
}

/// Sunucu hata bildirimi (`error`).
class ErrorServerMessage extends ServerMessage {
  final String code;

  const ErrorServerMessage({required this.code});

  @override
  String toString() => 'ErrorServerMessage(code: $code)';
}

/// Canlı maç durumu güncellemesi (`state`).
class StateServerMessage extends ServerMessage {
  final OnlineMatchState state;

  const StateServerMessage(this.state);

  @override
  String toString() => 'StateServerMessage(phase: ${state.phase})';
}

/// Hamle geribildirimi (`feedback`).
class FeedbackServerMessage extends ServerMessage {
  final String kind; // 'wrong', 'nearMiss', 'alreadySaid', 'ignored'
  final String? reason; // 'cooldown', 'not_your_turn', 'empty', 'limit_exceeded', 'round_not_active'

  const FeedbackServerMessage({required this.kind, this.reason});

  @override
  String toString() => 'FeedbackServerMessage(kind: $kind, reason: $reason)';
}

/// Maç sonucu ve özet bildirimi (`final`).
class FinalServerMessage extends ServerMessage {
  final List<OnlineRoundRecord> rounds;
  final int myScore;
  final int opponentScore;
  final bool winnerIsMe;
  final String endedBy; // 'normal', 'forfeit'
  final String? opponentName;
  final String opponentFrame;
  final int? coinsAwarded;
  final int? coins;

  const FinalServerMessage({
    required this.rounds,
    required this.myScore,
    required this.opponentScore,
    required this.winnerIsMe,
    required this.endedBy,
    this.opponentName,
    this.opponentFrame = 'classic',
    this.coinsAwarded,
    this.coins,
  });

  @override
  String toString() =>
      'FinalServerMessage(winnerIsMe: $winnerIsMe, scores: $myScore-$opponentScore, endedBy: $endedBy, opponentName: $opponentName, coinsAwarded: $coinsAwarded, coins: $coins)';
}

/// İptal edilen maç bildirimi (`voided`).
class VoidedServerMessage extends ServerMessage {
  final String reason; // 'opponent_absent'

  const VoidedServerMessage({required this.reason});

  @override
  String toString() => 'VoidedServerMessage(reason: $reason)';
}

/// Güçlendirici onay / yanıt bildirimi (`powerup_ack`).
class PowerupAckServerMessage extends ServerMessage {
  final String powerupType;
  final bool success;
  final int? deadlineMs;
  final int? coins;
  final int? remainingUses;
  final String? code;
  final String? message;

  const PowerupAckServerMessage({
    required this.powerupType,
    required this.success,
    this.deadlineMs,
    this.coins,
    this.remainingUses,
    this.code,
    this.message,
  });

  @override
  String toString() =>
      'PowerupAckServerMessage(powerupType: $powerupType, success: $success, deadlineMs: $deadlineMs, coins: $coins, remainingUses: $remainingUses, code: $code)';
}

/// Rakip oyuncunun güçlendirici kullandığı bildirimi (`opponent_powerup`).
class OpponentPowerupServerMessage extends ServerMessage {
  final String powerupType;
  final int seconds;

  const OpponentPowerupServerMessage({
    required this.powerupType,
    required this.seconds,
  });

  @override
  String toString() =>
      'OpponentPowerupServerMessage(powerupType: $powerupType, seconds: $seconds)';
}

/// Sunucudan gelen ham metin veya JSON nesnesini güçlü tipli [ServerMessage] sınıfına dönüştürür.
///
/// Hata fırlatmaz; bozuk veya beklenmeyen verilerde [UnknownServerMessage] döndürür.
ServerMessage parseServerMessage(dynamic raw, {int? receivedLocalMs}) {
  if (raw == null) return const UnknownServerMessage(null);
  try {
    final Map<String, dynamic> json;
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return UnknownServerMessage(raw);
      }
      json = decoded;
    } else if (raw is Map<String, dynamic>) {
      json = raw;
    } else {
      return UnknownServerMessage(raw);
    }

    final type = json['t'];
    switch (type) {
      case 'queued':
        return const QueuedServerMessage();
      case 'cancelled':
        return const CancelledServerMessage();
      case 'matched':
        final matchId = json['matchId'];
        final opponentName = json['opponentName'];
        final isFriendly = json['isFriendly'] as bool? ?? false;
        final opponentFrame = json['opponentFrame'] as String? ?? 'classic';
        if (matchId is! String || opponentName is! String) {
          return UnknownServerMessage(raw);
        }
        return MatchedServerMessage(
          matchId: matchId,
          opponentName: opponentName,
          isFriendly: isFriendly,
          opponentFrame: opponentFrame,
        );
      case 'room_created':
        final code = json['code'] as String?;
        final expiresAt = (json['expiresAt'] as num?)?.toInt() ?? 0;
        if (code == null) return UnknownServerMessage(raw);
        return RoomCreatedServerMessage(code: code, expiresAt: expiresAt);
      case 'room_resumed':
        final code = json['code'] as String?;
        final expiresAt = (json['expiresAt'] as num?)?.toInt() ?? 0;
        if (code == null) return UnknownServerMessage(raw);
        return RoomResumedServerMessage(code: code, expiresAt: expiresAt);
      case 'room_expired':
        return const RoomExpiredServerMessage();
      case 'error':
        final code = json['code'];
        if (code is! String) return UnknownServerMessage(raw);
        return ErrorServerMessage(code: code);
      case 'state':
        final state = OnlineMatchState.fromJson(
          json,
          receivedLocalMs: receivedLocalMs,
        );
        return StateServerMessage(state);
      case 'feedback':
        final kind = json['kind'];
        if (kind is! String) return UnknownServerMessage(raw);
        return FeedbackServerMessage(
          kind: kind,
          reason: json['reason'] as String?,
        );
      case 'final':
        final roundsList = (json['rounds'] as List<dynamic>?)
                ?.map((e) =>
                    OnlineRoundRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [];
        final scores = json['scores'] as Map<String, dynamic>?;
        final myScore = (scores?['me'] as num?)?.toInt() ?? 0;
        final opponentScore = (scores?['opponent'] as num?)?.toInt() ?? 0;
        final winnerIsMe = json['winnerIsMe'] as bool? ?? false;
        final endedBy = json['endedBy'] as String? ?? 'normal';
        final opponentName = json['opponentName'] as String?;
        final opponentFrame = json['opponentFrame'] as String? ?? 'classic';
        final coinsAwarded = (json['coinsAwarded'] as num?)?.toInt();
        final coins = (json['coins'] as num?)?.toInt();
        return FinalServerMessage(
          rounds: roundsList,
          myScore: myScore,
          opponentScore: opponentScore,
          winnerIsMe: winnerIsMe,
          endedBy: endedBy,
          opponentName: opponentName,
          opponentFrame: opponentFrame,
          coinsAwarded: coinsAwarded,
          coins: coins,
        );
      case 'voided':
        final reason = json['reason'] as String? ?? 'opponent_absent';
        return VoidedServerMessage(reason: reason);
      case 'powerup_ack':
        return PowerupAckServerMessage(
          powerupType: json['powerupType'] as String? ?? 'extra_time',
          success: json['success'] as bool? ?? false,
          deadlineMs: (json['deadlineMs'] as num?)?.toInt(),
          coins: (json['coins'] as num?)?.toInt(),
          remainingUses: (json['remainingUses'] as num?)?.toInt(),
          code: json['code'] as String?,
          message: json['message'] as String?,
        );
      case 'opponent_powerup':
        return OpponentPowerupServerMessage(
          powerupType: json['powerupType'] as String? ?? 'extra_time',
          seconds: (json['seconds'] as num?)?.toInt() ?? 5,
        );
      default:
        return UnknownServerMessage(raw);
    }
  } catch (_) {
    return UnknownServerMessage(raw);
  }
}

/// Oyuncu adını sanitize eder: boşlukları kırpar, ardışık boşlukları tek boşluğa indirir,
/// en fazla 20 karakterle sınırlar. Boşsa 'Oyuncu' döner.
String sanitizePlayerName(String? raw) {
  if (raw == null) return 'Oyuncu';
  final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return 'Oyuncu';
  return trimmed.length <= 20 ? trimmed : trimmed.substring(0, 20);
}

/// Deneme metnini sanitize eder: boşlukları kırpar, ardışık boşlukları tek boşluğa indirir,
/// en fazla 40 karakterle sınırlar.
String sanitizeSubmitText(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.length <= 40 ? trimmed : trimmed.substring(0, 40);
}

/// Kuyruğa girme istemci mesajı oluşturur (JSON string).
String createQueueMessage(String name) {
  final cleanName = sanitizePlayerName(name);
  return jsonEncode({
    't': 'queue',
    'name': cleanName,
  });
}

/// Kuyruktan çıkma istemci mesajı oluşturur (JSON string).
String createCancelMessage() {
  return jsonEncode({
    't': 'cancel',
  });
}

/// Cevap denemesi gönderme istemci mesajı oluşturur (JSON string).
String createSubmitMessage(String text) {
  final cleanText = sanitizeSubmitText(text);
  return jsonEncode({
    't': 'submit',
    'text': cleanText,
  });
}

/// Maçı terk etme istemci mesajı oluşturur (JSON string).
String createLeaveMessage() {
  return jsonEncode({
    't': 'leave',
  });
}

/// Durum senkronizasyonu isteme istemci mesajı oluşturur (JSON string).
String createSyncMessage() {
  return jsonEncode({
    't': 'sync',
  });
}

/// Arkadaş odası oluşturma istemci mesajı (`create_room`).
String createRoomMessage({String? name}) {
  return jsonEncode({
    't': 'create_room',
    if (name != null && name.trim().isNotEmpty) 'name': sanitizePlayerName(name),
  });
}

/// Askıdaki arkadaş odasına yeniden bağlanma istemci mesajı (`resume_room`).
String createResumeRoomMessage(String code) {
  return jsonEncode({
    't': 'resume_room',
    'code': code.trim().toUpperCase(),
  });
}

/// Arkadaş odasına katılma istemci mesajı (`join_room`).
String createJoinRoomMessage(String code, {String? name}) {
  return jsonEncode({
    't': 'join_room',
    'code': code.trim().toUpperCase(),
    if (name != null && name.trim().isNotEmpty) 'name': sanitizePlayerName(name),
  });
}

/// Arkadaş odasını iptal etme / kapatma istemci mesajı (`cancel_room`).
String createCancelRoomMessage({String? code}) {
  return jsonEncode({
    't': 'cancel_room',
    if (code != null && code.trim().isNotEmpty) 'code': code.trim().toUpperCase(),
  });
}

/// Güçlendirici kullanma istemci mesajı (`use_powerup`).
String createUsePowerupMessage(String type) {
  return jsonEncode({
    't': 'use_powerup',
    'type': type,
  });
}

