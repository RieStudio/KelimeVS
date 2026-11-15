/// Maç isteği türü (dostluk vs rankli).
enum MatchRequestType {
  friendly,
  ranked;

  static MatchRequestType fromString(String raw) {
    return raw == 'ranked' ? MatchRequestType.ranked : MatchRequestType.friendly;
  }

  String toWireString() => this == MatchRequestType.ranked ? 'ranked' : 'friendly';
}

/// Maç isteğinin nereden başlatıldığı.
enum MatchRequestOrigin {
  rematch,
  profile;

  static MatchRequestOrigin fromString(String raw) {
    return raw == 'rematch' ? MatchRequestOrigin.rematch : MatchRequestOrigin.profile;
  }

  String toWireString() => this == MatchRequestOrigin.rematch ? 'rematch' : 'profile';
}

/// Maç isteği hata kodları. Bilinmeyen kod gelirse [invalid] olarak ayrıştırılır.
enum MatchRequestErrorCode {
  unavailable,
  cooldownActive,
  rateLimited,
  invalid,
  noEnergy,
  opponentNoEnergy;

  static MatchRequestErrorCode fromString(String raw) {
    switch (raw) {
      case 'unavailable':
        return MatchRequestErrorCode.unavailable;
      case 'cooldown_active':
        return MatchRequestErrorCode.cooldownActive;
      case 'rate_limited':
        return MatchRequestErrorCode.rateLimited;
      case 'no_energy':
        return MatchRequestErrorCode.noEnergy;
      case 'opponent_no_energy':
        return MatchRequestErrorCode.opponentNoEnergy;
      case 'invalid':
      default:
        return MatchRequestErrorCode.invalid;
    }
  }

  String toWireString() {
    switch (this) {
      case MatchRequestErrorCode.unavailable:
        return 'unavailable';
      case MatchRequestErrorCode.cooldownActive:
        return 'cooldown_active';
      case MatchRequestErrorCode.rateLimited:
        return 'rate_limited';
      case MatchRequestErrorCode.noEnergy:
        return 'no_energy';
      case MatchRequestErrorCode.opponentNoEnergy:
        return 'opponent_no_energy';
      case MatchRequestErrorCode.invalid:
        return 'invalid';
    }
  }
}

/// Maç isteği sonuçlanma durumları.
enum MatchRequestEndStatus {
  declined,
  expired,
  cancelled;

  static MatchRequestEndStatus fromString(String raw) {
    switch (raw) {
      case 'declined':
        return MatchRequestEndStatus.declined;
      case 'expired':
        return MatchRequestEndStatus.expired;
      case 'cancelled':
      default:
        return MatchRequestEndStatus.cancelled;
    }
  }

  String toWireString() {
    switch (this) {
      case MatchRequestEndStatus.declined:
        return 'declined';
      case MatchRequestEndStatus.expired:
        return 'expired';
      case MatchRequestEndStatus.cancelled:
        return 'cancelled';
    }
  }
}

/// /ws/user WebSocket bağlantı durumu.
enum UserInboxConnectionState {
  disconnected,
  connecting,
  connected,
}

/// Kullanıcıya gelen bekleyen maç isteği.
class IncomingMatchRequest {
  final String id;
  final String fromUid;
  final String fromNickname;
  final String fromFrame;
  final MatchRequestType type;
  final MatchRequestOrigin origin;
  final int expiresAtMs;
  final bool isSnapshot;
  final int initialRemainingMs;
  final Stopwatch _stopwatch;
  final int Function()? _elapsedMsProvider;

  IncomingMatchRequest({
    required this.id,
    required this.fromUid,
    required this.fromNickname,
    required this.fromFrame,
    required this.type,
    required this.origin,
    required this.expiresAtMs,
    this.isSnapshot = false,
    int? initialRemainingMs,
    Stopwatch? stopwatch,
    this._elapsedMsProvider,
  })  : initialRemainingMs = initialRemainingMs ?? 45000,
        _stopwatch = stopwatch ?? (Stopwatch()..start());

  /// Canlı (live) alınan istek: Kalan süre doğrudan 45 sn'den başlar ve
  /// cihazın duvar saatinden bağımsız olarak monotonik saatle sayar.
  factory IncomingMatchRequest.live({
    required String id,
    required String fromUid,
    required String fromNickname,
    required String fromFrame,
    required MatchRequestType type,
    required MatchRequestOrigin origin,
    required int expiresAtMs,
    Stopwatch? stopwatch,
    int Function()? elapsedMsProvider,
  }) {
    return IncomingMatchRequest(
      id: id,
      fromUid: fromUid,
      fromNickname: fromNickname,
      fromFrame: fromFrame,
      type: type,
      origin: origin,
      expiresAtMs: expiresAtMs,
      isSnapshot: false,
      initialRemainingMs: 45000,
      stopwatch: stopwatch,
      elapsedMsProvider: elapsedMsProvider,
    );
  }

  /// Bağlantı anında snapshot ile gelen istek:
  /// Alım anında kalan süre = (expiresAtMs - nowWallClockMs).clamp(0, 45000) olarak bir kez hesaplanır,
  /// ardından monotonik saatle geri sayar.
  factory IncomingMatchRequest.snapshot({
    required String id,
    required String fromUid,
    required String fromNickname,
    required String fromFrame,
    required MatchRequestType type,
    required MatchRequestOrigin origin,
    required int expiresAtMs,
    int? nowMs,
    Stopwatch? stopwatch,
    int Function()? elapsedMsProvider,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final initialRemaining = (expiresAtMs - now).clamp(0, 45000);
    return IncomingMatchRequest(
      id: id,
      fromUid: fromUid,
      fromNickname: fromNickname,
      fromFrame: fromFrame,
      type: type,
      origin: origin,
      expiresAtMs: expiresAtMs,
      isSnapshot: true,
      initialRemainingMs: initialRemaining,
      stopwatch: stopwatch,
      elapsedMsProvider: elapsedMsProvider,
    );
  }

  /// Kalan süreyi saniye cinsinden [0, 45] aralığında döndürür.
  int calculateRemainingSeconds({int? elapsedMsOverride, int? localNowMs}) {
    final int elapsed;
    if (elapsedMsOverride != null) {
      elapsed = elapsedMsOverride;
    } else if (_elapsedMsProvider != null) {
      elapsed = _elapsedMsProvider();
    } else {
      elapsed = _stopwatch.elapsedMilliseconds;
    }

    final remainingMs = initialRemainingMs - elapsed;
    final sec = (remainingMs / 1000).ceil();
    return sec.clamp(0, 45);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IncomingMatchRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fromUid == other.fromUid &&
          fromNickname == other.fromNickname &&
          fromFrame == other.fromFrame &&
          type == other.type &&
          origin == other.origin &&
          expiresAtMs == other.expiresAtMs &&
          isSnapshot == other.isSnapshot;

  @override
  int get hashCode =>
      id.hashCode ^
      fromUid.hashCode ^
      fromNickname.hashCode ^
      fromFrame.hashCode ^
      type.hashCode ^
      origin.hashCode ^
      expiresAtMs.hashCode ^
      isSnapshot.hashCode;
}

/// Kullanıcının gönderdiği bekleyen giden maç isteği.
class OutgoingMatchRequest {
  final String id;
  final String toUid;
  final String toNickname;
  final MatchRequestType type;
  final MatchRequestOrigin origin;
  final int expiresAtMs;
  final bool isSnapshot;
  final int initialRemainingMs;
  final Stopwatch _stopwatch;
  final int Function()? _elapsedMsProvider;

  OutgoingMatchRequest({
    required this.id,
    required this.toUid,
    required this.toNickname,
    required this.type,
    required this.origin,
    required this.expiresAtMs,
    this.isSnapshot = false,
    int? initialRemainingMs,
    Stopwatch? stopwatch,
    this._elapsedMsProvider,
  })  : initialRemainingMs = initialRemainingMs ?? 45000,
        _stopwatch = stopwatch ?? (Stopwatch()..start());

  /// Canlı (live) gönderilen istek: Kalan süre doğrudan 45 sn'den başlar ve
  /// cihazın duvar saatinden bağımsız olarak monotonik saatle sayar.
  factory OutgoingMatchRequest.live({
    required String id,
    required String toUid,
    required String toNickname,
    required MatchRequestType type,
    required MatchRequestOrigin origin,
    required int expiresAtMs,
    Stopwatch? stopwatch,
    int Function()? elapsedMsProvider,
  }) {
    return OutgoingMatchRequest(
      id: id,
      toUid: toUid,
      toNickname: toNickname,
      type: type,
      origin: origin,
      expiresAtMs: expiresAtMs,
      isSnapshot: false,
      initialRemainingMs: 45000,
      stopwatch: stopwatch,
      elapsedMsProvider: elapsedMsProvider,
    );
  }

  /// Bağlantı anında snapshot ile gelen giden istek:
  /// Alım anında kalan süre = (expiresAtMs - nowWallClockMs).clamp(0, 45000) olarak bir kez hesaplanır,
  /// ardından monotonik saatle geri sayar.
  factory OutgoingMatchRequest.snapshot({
    required String id,
    required String toUid,
    required String toNickname,
    required MatchRequestType type,
    required MatchRequestOrigin origin,
    required int expiresAtMs,
    int? nowMs,
    Stopwatch? stopwatch,
    int Function()? elapsedMsProvider,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final initialRemaining = (expiresAtMs - now).clamp(0, 45000);
    return OutgoingMatchRequest(
      id: id,
      toUid: toUid,
      toNickname: toNickname,
      type: type,
      origin: origin,
      expiresAtMs: expiresAtMs,
      isSnapshot: true,
      initialRemainingMs: initialRemaining,
      stopwatch: stopwatch,
      elapsedMsProvider: elapsedMsProvider,
    );
  }

  /// Kalan süreyi saniye cinsinden [0, 45] aralığında döndürür.
  int calculateRemainingSeconds({int? elapsedMsOverride, int? localNowMs}) {
    final int elapsed;
    if (elapsedMsOverride != null) {
      elapsed = elapsedMsOverride;
    } else if (_elapsedMsProvider != null) {
      elapsed = _elapsedMsProvider();
    } else {
      elapsed = _stopwatch.elapsedMilliseconds;
    }

    final remainingMs = initialRemainingMs - elapsed;
    final sec = (remainingMs / 1000).ceil();
    return sec.clamp(0, 45);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutgoingMatchRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          toUid == other.toUid &&
          toNickname == other.toNickname &&
          type == other.type &&
          origin == other.origin &&
          expiresAtMs == other.expiresAtMs &&
          isSnapshot == other.isSnapshot;

  @override
  int get hashCode =>
      id.hashCode ^
      toUid.hashCode ^
      toNickname.hashCode ^
      type.hashCode ^
      origin.hashCode ^
      expiresAtMs.hashCode ^
      isSnapshot.hashCode;
}

/// İstek sonlanma bilgisi (UI bildirimleri için).
class MatchRequestEndStatusInfo {
  final String id;
  final MatchRequestEndStatus status;
  final bool isOutgoing;

  const MatchRequestEndStatusInfo({
    required this.id,
    required this.status,
    required this.isOutgoing,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRequestEndStatusInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          isOutgoing == other.isOutgoing;

  @override
  int get hashCode => id.hashCode ^ status.hashCode ^ isOutgoing.hashCode;
}

/// İstek hata bilgisi.
class MatchRequestErrorInfo {
  final MatchRequestErrorCode code;
  final int? retryAfterSec;

  const MatchRequestErrorInfo({
    required this.code,
    this.retryAfterSec,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRequestErrorInfo &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          retryAfterSec == other.retryAfterSec;

  @override
  int get hashCode => code.hashCode ^ retryAfterSec.hashCode;
}

/// Eşleşme tamamlandı olayı (FAZ 3 navigasyon dinleyicisi için).
class MatchedEvent {
  final String matchId;
  final String opponentName;
  final String opponentFrame;
  final String? opponentUid;
  final bool isFriendly;

  const MatchedEvent({
    required this.matchId,
    required this.opponentName,
    required this.opponentFrame,
    this.opponentUid,
    required this.isFriendly,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchedEvent &&
          runtimeType == other.runtimeType &&
          matchId == other.matchId &&
          opponentName == other.opponentName &&
          opponentFrame == other.opponentFrame &&
          opponentUid == other.opponentUid &&
          isFriendly == other.isFriendly;

  @override
  int get hashCode =>
      matchId.hashCode ^
      opponentName.hashCode ^
      opponentFrame.hashCode ^
      opponentUid.hashCode ^
      isFriendly.hashCode;
}
