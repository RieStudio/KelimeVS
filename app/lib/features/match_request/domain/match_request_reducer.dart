import 'match_request_models.dart';
import '../data/match_request_messages.dart';

/// Maç istekleri Riverpod durum modeli.
class MatchRequestsState {
  final IncomingMatchRequest? incoming;
  final OutgoingMatchRequest? outgoing;
  final MatchRequestEndStatusInfo? lastEndStatus;
  final MatchRequestErrorInfo? lastError;
  final UserInboxConnectionState connectionState;

  const MatchRequestsState({
    this.incoming,
    this.outgoing,
    this.lastEndStatus,
    this.lastError,
    this.connectionState = UserInboxConnectionState.disconnected,
  });

  bool get hasActiveIncoming => incoming != null;
  bool get hasActiveOutgoing => outgoing != null;
  bool get isConnected => connectionState == UserInboxConnectionState.connected;

  MatchRequestsState copyWith({
    IncomingMatchRequest? incoming,
    bool clearIncoming = false,
    OutgoingMatchRequest? outgoing,
    bool clearOutgoing = false,
    MatchRequestEndStatusInfo? lastEndStatus,
    bool clearLastEndStatus = false,
    MatchRequestErrorInfo? lastError,
    bool clearLastError = false,
    UserInboxConnectionState? connectionState,
  }) {
    return MatchRequestsState(
      incoming: clearIncoming ? null : (incoming ?? this.incoming),
      outgoing: clearOutgoing ? null : (outgoing ?? this.outgoing),
      lastEndStatus: clearLastEndStatus
          ? null
          : (lastEndStatus ?? this.lastEndStatus),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      connectionState: connectionState ?? this.connectionState,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRequestsState &&
          runtimeType == other.runtimeType &&
          incoming == other.incoming &&
          outgoing == other.outgoing &&
          lastEndStatus == other.lastEndStatus &&
          lastError == other.lastError &&
          connectionState == other.connectionState;

  @override
  int get hashCode =>
      incoming.hashCode ^
      outgoing.hashCode ^
      lastEndStatus.hashCode ^
      lastError.hashCode ^
      connectionState.hashCode;
}

/// Saf durum indirgeyici (Pure Reducer).
/// Gelen sunucu mesajını alarak yeni durumu üretir.
MatchRequestsState reduceMatchRequestMessage(
  MatchRequestsState current,
  UserInboxServerMessage message, {
  bool? isSnapshot,
  int? nowMs,
  Stopwatch? stopwatch,
  int Function()? elapsedMsProvider,
  int? localNowMs,
}) {
  switch (message) {
    case UserInboxRequestReceivedMessage msg:
      final snapshot = isSnapshot ?? msg.isSnapshot;
      final newIncoming = snapshot
          ? IncomingMatchRequest.snapshot(
              id: msg.id,
              fromUid: msg.fromUid,
              fromNickname: msg.fromNickname,
              fromFrame: msg.fromFrame,
              type: msg.type,
              origin: msg.origin,
              expiresAtMs: msg.expiresAtMs,
              nowMs: nowMs ?? localNowMs,
              stopwatch: stopwatch,
              elapsedMsProvider: elapsedMsProvider,
            )
          : IncomingMatchRequest.live(
              id: msg.id,
              fromUid: msg.fromUid,
              fromNickname: msg.fromNickname,
              fromFrame: msg.fromFrame,
              type: msg.type,
              origin: msg.origin,
              expiresAtMs: msg.expiresAtMs,
              stopwatch: stopwatch,
              elapsedMsProvider: elapsedMsProvider,
            );
      return current.copyWith(
        incoming: newIncoming,
        clearLastError: true,
      );

    case UserInboxRequestSentMessage msg:
      final snapshot = isSnapshot ?? msg.isSnapshot;
      final newOutgoing = snapshot
          ? OutgoingMatchRequest.snapshot(
              id: msg.id,
              toUid: msg.toUid,
              toNickname: msg.toNickname,
              type: msg.type,
              origin: msg.origin,
              expiresAtMs: msg.expiresAtMs,
              nowMs: nowMs ?? localNowMs,
              stopwatch: stopwatch,
              elapsedMsProvider: elapsedMsProvider,
            )
          : OutgoingMatchRequest.live(
              id: msg.id,
              toUid: msg.toUid,
              toNickname: msg.toNickname,
              type: msg.type,
              origin: msg.origin,
              expiresAtMs: msg.expiresAtMs,
              stopwatch: stopwatch,
              elapsedMsProvider: elapsedMsProvider,
            );
      return current.copyWith(
        outgoing: newOutgoing,
        clearLastError: true,
      );

    case UserInboxRequestStatusMessage msg:
      final isIncoming = current.incoming?.id == msg.id;
      final isOutgoing = current.outgoing?.id == msg.id;

      if (!isIncoming && !isOutgoing) {
        // İlgili istek mevcut değilse son durum olarak kaydet
        return current.copyWith(
          lastEndStatus: MatchRequestEndStatusInfo(
            id: msg.id,
            status: msg.status,
            isOutgoing: false,
          ),
        );
      }

      return current.copyWith(
        clearIncoming: isIncoming,
        clearOutgoing: isOutgoing,
        lastEndStatus: MatchRequestEndStatusInfo(
          id: msg.id,
          status: msg.status,
          isOutgoing: isOutgoing,
        ),
      );

    case UserInboxRequestErrorMessage msg:
      return current.copyWith(
        lastError: MatchRequestErrorInfo(
          code: msg.code,
          retryAfterSec: msg.retryAfterSec,
        ),
      );

    case UserInboxMatchedMessage _:
      // Eşleşme kurulduğunda her iki bekleyen istek de sonlanmış olur
      return current.copyWith(
        clearIncoming: true,
        clearOutgoing: true,
        clearLastError: true,
      );

    case UserInboxPongMessage _:
      return current;
  }
}
