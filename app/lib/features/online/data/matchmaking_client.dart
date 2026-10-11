import 'dart:async';

import '../../../core/config/server_config.dart';
import '../domain/models/online_messages.dart';
import 'auth_token_provider.dart';
import 'websocket_connector.dart';

/// Eşleştirme sürecinde oluşan olayların temel sınıfı.
sealed class MatchmakingEvent {
  const MatchmakingEvent();
}

/// Eşleştirme sunucusuna bağlanılıyor.
class MatchmakingConnecting extends MatchmakingEvent {
  const MatchmakingConnecting();

  @override
  String toString() => 'MatchmakingConnecting()';
}

/// Sunucu kuyruğuna başarıyla girildi (`queued`).
class MatchmakingQueued extends MatchmakingEvent {
  const MatchmakingQueued();

  @override
  String toString() => 'MatchmakingQueued()';
}

/// Rakip bulundu ve maç oluşturuldu (`matched`).
class MatchmakingMatched extends MatchmakingEvent {
  final String matchId;
  final String opponentName;

  const MatchmakingMatched({
    required this.matchId,
    required this.opponentName,
  });

  @override
  String toString() =>
      'MatchmakingMatched(matchId: $matchId, opponentName: $opponentName)';
}

/// Kullanıcı veya sistem tarafından eşleştirme iptal edildi.
class MatchmakingCancelled extends MatchmakingEvent {
  const MatchmakingCancelled();

  @override
  String toString() => 'MatchmakingCancelled()';
}

/// Eşleştirme penceresi içinde (10 sn) rakip bulunamadı.
class MatchmakingNoOpponent extends MatchmakingEvent {
  const MatchmakingNoOpponent();

  @override
  String toString() => 'MatchmakingNoOpponent()';
}

/// Sunucu veya içerik kullanılamıyor (botlu maça yönlendirilir).
class MatchmakingUnavailable extends MatchmakingEvent {
  final String reason;

  const MatchmakingUnavailable(this.reason);

  @override
  String toString() => 'MatchmakingUnavailable(reason: $reason)';
}

/// Eşleştirme işlemi hata nedeniyle başarısız oldu.
class MatchmakingFailed extends MatchmakingEvent {
  final String reason;

  const MatchmakingFailed(this.reason);

  @override
  String toString() => 'MatchmakingFailed(reason: $reason)';
}

/// Sunucu eşleştirme havuzuyla (`/ws/matchmaking`) iletişimi yöneten istemci.
class MatchmakingClient {
  final WebSocketConnector _connector;
  final AuthTokenProvider _tokenProvider;
  final String? _customServerWsUrl;
  final Duration _connectTimeout;
  final Duration _matchWindowDuration;
  final Timer Function(Duration duration, void Function() callback)?
      _timerFactory;

  final StreamController<MatchmakingEvent> _controller =
      StreamController<MatchmakingEvent>.broadcast(sync: true);

  bool _started = false;
  bool _isCancelled = false;
  bool _isFinished = false;

  WebSocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _matchTimer;

  MatchmakingClient({
    WebSocketConnector? connector,
    AuthTokenProvider? tokenProvider,
    String? serverWsUrl,
    this._connectTimeout = const Duration(seconds: 8),
    this._matchWindowDuration = const Duration(seconds: 10),
    this._timerFactory,
  })  : _connector = connector ?? const IoWebSocketConnector(),
        _tokenProvider = tokenProvider ?? FirebaseAuthTokenProvider(),
        _customServerWsUrl = serverWsUrl;

  /// Eşleştirme olay akışı.
  Stream<MatchmakingEvent> get events => _controller.stream;

  /// Eşleştirme sürecini başlatır.
  ///
  /// Aynı istemci örneğinde ikinci kez çağrılırsa [StateError] fırlatır.
  Future<void> start(String name) async {
    if (_started) {
      throw StateError('MatchmakingClient zaten başlatıldı.');
    }
    _started = true;
    _emit(const MatchmakingConnecting());

    // 1. Firebase kimlik jetonunu al
    final String? token;
    try {
      token = await _tokenProvider
          .getIdToken()
          .timeout(_connectTimeout);
    } catch (e) {
      if (!_isCancelled) {
        _finishWith(MatchmakingUnavailable('token_error: $e'));
      }
      return;
    }

    if (_isCancelled) return;

    if (token == null || token.isEmpty) {
      _finishWith(const MatchmakingUnavailable('no_auth_token'));
      return;
    }

    // 2. WebSocket bağlantısı kur
    final url = _customServerWsUrl ?? ServerConfig.matchmakingWsUrl;
    final headers = {'Authorization': 'Bearer $token'};

    try {
      _connection = await _connector.connect(
        url,
        headers: headers,
        timeout: _connectTimeout,
      );
    } catch (e) {
      if (!_isCancelled) {
        _finishWith(MatchmakingUnavailable('connection_failed: $e'));
      }
      return;
    }

    if (_isCancelled) {
      await _cleanupConnection();
      return;
    }

    // 3. Mesaj dinleyicisini bağla
    _subscription = _connection!.stream.listen(
      _handleIncomingMessage,
      onError: (error) {
        if (!_isFinished && !_isCancelled) {
          _finishWith(MatchmakingFailed('stream_error: $error'));
        }
      },
      onDone: () {
        if (!_isFinished && !_isCancelled) {
          _finishWith(
            const MatchmakingFailed('connection_closed_unexpectedly'),
          );
        }
      },
    );

    // 4. Kuyruğa girme mesajını ilet
    try {
      _connection!.send(createQueueMessage(name));
    } catch (e) {
      _finishWith(MatchmakingFailed('send_failed: $e'));
    }
  }

  void _handleIncomingMessage(dynamic raw) {
    if (_isFinished || _isCancelled) return;

    final msg = parseServerMessage(raw);
    if (msg is QueuedServerMessage) {
      _emit(const MatchmakingQueued());

      // "queued" alındıktan sonra 10 sn eşleşme penceresi başlar (bağlantı süresini saymaz)
      _matchTimer?.cancel();
      Future<void> timerCallback() async {
        if (_isFinished || _isCancelled) return;
        try {
          _connection?.send(createCancelMessage());
        } catch (_) {}
        await _cleanupConnection();
        _finishWith(const MatchmakingNoOpponent());
      }

      if (_timerFactory != null) {
        _matchTimer = _timerFactory(_matchWindowDuration, timerCallback);
      } else {
        _matchTimer = Timer(_matchWindowDuration, timerCallback);
      }
    } else if (msg is MatchedServerMessage) {
      _matchTimer?.cancel();
      _matchTimer = null;
      _emit(MatchmakingMatched(
        matchId: msg.matchId,
        opponentName: msg.opponentName,
      ));
      _finishAndClose();
    } else if (msg is ErrorServerMessage) {
      _matchTimer?.cancel();
      _matchTimer = null;
      if (msg.code == 'content_unavailable') {
        _finishWith(const MatchmakingUnavailable('content_unavailable'));
      } else {
        _finishWith(MatchmakingFailed(msg.code));
      }
    } else if (msg is CancelledServerMessage) {
      _finishWith(const MatchmakingCancelled());
    }
  }

  /// Eşleştirmeyi iptal eder; tüm zamanlayıcıları ve bağlantıyı kapatır.
  Future<void> cancel() async {
    if (_isCancelled || _isFinished) return;
    _isCancelled = true;
    _isFinished = true;

    _matchTimer?.cancel();
    _matchTimer = null;

    if (_connection != null) {
      try {
        _connection!.send(createCancelMessage());
      } catch (_) {}
    }

    _emit(const MatchmakingCancelled());
    await _cleanupConnection();
  }

  void _emit(MatchmakingEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void _finishWith(MatchmakingEvent event) {
    if (_isFinished) return;
    _isFinished = true;
    _matchTimer?.cancel();
    _matchTimer = null;
    _emit(event);
    unawaited(_cleanupConnection());
  }

  Future<void> _finishAndClose() async {
    _isFinished = true;
    _matchTimer?.cancel();
    _matchTimer = null;
    await _cleanupConnection();
  }

  Future<void> _cleanupConnection() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
  }

  /// İstemci kaynaklarını serbest bırakır.
  Future<void> dispose() async {
    await cancel();
    await _controller.close();
  }
}
