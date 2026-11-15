import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_request_messages.dart';
import '../data/user_inbox_client.dart';
import '../domain/match_request_models.dart';
import '../domain/match_request_reducer.dart';

/// Maç istekleri Riverpod yöneticisi.
class MatchRequestsNotifier extends Notifier<MatchRequestsState> {
  final StreamController<MatchedEvent> _matchedEventsController =
      StreamController<MatchedEvent>.broadcast(sync: true);

  StreamSubscription<UserInboxServerMessage>? _messagesSub;
  StreamSubscription<bool>? _connectionStatusSub;
  UserInboxClient? _client;
  int Function() _clock = () => DateTime.now().millisecondsSinceEpoch;
  bool _isDisposed = false;

  @visibleForTesting
  void setClockForTesting(int Function() clock) {
    _clock = clock;
  }

  /// Eşleşme tamamlandı olay akışı (FAZ 3 navigasyon için).
  Stream<MatchedEvent> get matchedEvents => _matchedEventsController.stream;

  @override
  MatchRequestsState build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _messagesSub?.cancel();
      _connectionStatusSub?.cancel();
      _matchedEventsController.close();
    });

    return const MatchRequestsState();
  }

  /// İstemciyi bağlar ve olayları dinlemeye başlar.
  void attachClient(UserInboxClient client) {
    if (_client == client) return;

    _messagesSub?.cancel();
    _connectionStatusSub?.cancel();

    _client = client;

    _connectionStatusSub = client.connectionStatus.listen((isConnected) {
      if (_isDisposed) return;
      state = state.copyWith(
        connectionState: isConnected
            ? UserInboxConnectionState.connected
            : (client.isReconnecting
                ? UserInboxConnectionState.connecting
                : UserInboxConnectionState.disconnected),
      );
    });

    _messagesSub = client.messages.listen(_handleServerMessage);

    state = state.copyWith(
      connectionState: client.isConnected
          ? UserInboxConnectionState.connected
          : UserInboxConnectionState.disconnected,
    );
  }

  void _handleServerMessage(UserInboxServerMessage message) {
    if (_isDisposed) return;
    state = reduceMatchRequestMessage(state, message, nowMs: _clock());

    if (message is UserInboxMatchedMessage) {
      _matchedEventsController.add(
        MatchedEvent(
          matchId: message.matchId,
          opponentName: message.opponentName,
          opponentFrame: message.opponentFrame,
          opponentUid: message.opponentUid,
          isFriendly: message.isFriendly,
        ),
      );
    }
  }

  /// Başka bir kullanıcıya maç isteği gönderir.
  Future<bool> sendRequest({
    required MatchRequestOrigin origin,
    required String toUid,
    String? matchId,
  }) async {
    if (toUid.trim().isEmpty) {
      throw ArgumentError.value(toUid, 'toUid', 'toUid cannot be empty');
    }
    if (origin == MatchRequestOrigin.rematch) {
      if (matchId == null || matchId.trim().isEmpty) {
        throw ArgumentError('matchId is required when origin is rematch');
      }
    } else if (origin == MatchRequestOrigin.profile) {
      if (matchId != null && matchId.trim().isNotEmpty) {
        throw ArgumentError('matchId must not be provided when origin is profile');
      }
    }

    // 1. Zaten bekleyen bir giden istek varsa yerelde engelle
    if (state.outgoing != null) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    // 2. Bağlantı kontrolü
    final client = _client;
    if (client == null || !client.isConnected) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    final sent = client.send(
      UserInboxSendRequestMessage(
        origin: origin,
        toUid: toUid,
        matchId: matchId,
      ),
    );

    if (!sent) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    return true;
  }

  /// Profil ekranından kullanıcıya dostluk maçı isteği gönderir.
  Future<bool> sendProfileRequest({required String toUid}) {
    return sendRequest(
      origin: MatchRequestOrigin.profile,
      toUid: toUid,
    );
  }

  /// Gelen bir maç isteğini kabul eder.
  Future<bool> accept(String id) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    return client.send(UserInboxAcceptRequestMessage(id));
  }

  /// Gelen bir maç isteğini reddeder.
  Future<bool> decline(String id) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    return client.send(UserInboxDeclineRequestMessage(id));
  }

  /// Gönderilen bir maç isteğini iptal eder.
  Future<bool> cancel(String id) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      state = state.copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
        ),
      );
      return false;
    }

    return client.send(UserInboxCancelRequestMessage(id));
  }

  /// Arka plana geçildiğinde yerel bekleyen istekleri temizler.
  /// Yeniden bağlanınca sunucudan gelen snapshot yetkili kabul edilir.
  void clearLocalRequests() {
    state = state.copyWith(
      clearIncoming: true,
      clearOutgoing: true,
    );
  }

  /// Son hatayı temizler.
  void clearLastError() {
    if (state.lastError != null) {
      state = state.copyWith(clearLastError: true);
    }
  }

  /// Son sonuç durumunu temizler.
  void clearLastEndStatus() {
    if (state.lastEndStatus != null) {
      state = state.copyWith(clearLastEndStatus: true);
    }
  }

  /// Tüm durumu sıfırlar (sign-out veya account deletion sonrası).
  void reset() {
    state = const MatchRequestsState();
  }
}

final matchRequestsProvider =
    NotifierProvider<MatchRequestsNotifier, MatchRequestsState>(
  MatchRequestsNotifier.new,
);
