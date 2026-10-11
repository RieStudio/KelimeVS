import 'dart:async';
import 'dart:math';

import '../../../core/config/server_config.dart';
import '../domain/models/online_match_state.dart';
import '../domain/models/online_messages.dart';
import 'auth_token_provider.dart';
import 'websocket_connector.dart';

/// Maç bağlantısının kopma nedenleri.
enum DisconnectReason {
  /// 25 saniyelik yeniden bağlanma penceresi doldu.
  permanent,

  /// Aynı hesap başka bir cihazdan/sekmeden bağlandı (kod 4000).
  replaced,

  /// İstemci tarafından kasıtlı olarak kapatıldı (close/leave).
  closed,

  /// Beklenmeyen bir ağ hatası.
  error,
}

/// Canlı maç odası olaylarının temel sınıfı.
sealed class OnlineMatchEvent {
  const OnlineMatchEvent();
}

/// Maç odasına başarıyla bağlanıldı.
class OnlineMatchConnected extends OnlineMatchEvent {
  const OnlineMatchConnected();

  @override
  String toString() => 'OnlineMatchConnected()';
}

/// Canlı maç durumu güncellendi (`state`).
class OnlineMatchStateUpdate extends OnlineMatchEvent {
  final OnlineMatchState state;

  const OnlineMatchStateUpdate(this.state);

  @override
  String toString() =>
      'OnlineMatchStateUpdate(phase: ${state.phase}, round: ${state.roundNumber})';
}

/// Hamle geribildirimi alındı (`feedback`).
class OnlineMatchFeedback extends OnlineMatchEvent {
  final String kind;
  final String? reason;

  const OnlineMatchFeedback({required this.kind, this.reason});

  @override
  String toString() => 'OnlineMatchFeedback(kind: $kind, reason: $reason)';
}

/// Maç bitti ve özet raporu geldi (`final`).
class OnlineMatchFinal extends OnlineMatchEvent {
  final FinalServerMessage result;

  const OnlineMatchFinal(this.result);

  @override
  String toString() =>
      'OnlineMatchFinal(winnerIsMe: ${result.winnerIsMe}, endedBy: ${result.endedBy})';
}

/// Maç iptal edildi (`voided`).
class OnlineMatchVoided extends OnlineMatchEvent {
  final String reason;

  const OnlineMatchVoided({required this.reason});

  @override
  String toString() => 'OnlineMatchVoided(reason: $reason)';
}

/// Bağlantı koptu.
class OnlineMatchDisconnected extends OnlineMatchEvent {
  final DisconnectReason reason;

  const OnlineMatchDisconnected(this.reason);

  @override
  String toString() => 'OnlineMatchDisconnected(reason: $reason)';
}

/// Sunucudan hata mesajı geldi.
class OnlineMatchError extends OnlineMatchEvent {
  final String message;

  const OnlineMatchError(this.message);

  @override
  String toString() => 'OnlineMatchError(message: $message)';
}

/// Canlı maç odası (`/ws/match/:matchId`) protokolünü yürüten istemci.
class OnlineMatchClient {
  final WebSocketConnector _connector;
  final AuthTokenProvider _tokenProvider;
  final String? _customServerWsUrl;
  final Duration _connectTimeout;
  final Duration _cooldownDuration;
  final Duration _maxReconnectDuration;
  final List<Duration>? _reconnectDelays;
  final int Function() _clock;
  final Future<void> Function(Duration) _delayFunction;

  final StreamController<OnlineMatchEvent> _controller =
      StreamController<OnlineMatchEvent>.broadcast(sync: true);

  String? _currentMatchId;
  WebSocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;

  bool _isClosed = false;
  bool _isReconnecting = false;
  int _lastSubmitTimeMs = 0;
  int? _reconnectStartTimeMs;
  int _reconnectAttempt = 0;

  OnlineMatchClient({
    WebSocketConnector? connector,
    AuthTokenProvider? tokenProvider,
    String? serverWsUrl,
    this._connectTimeout = const Duration(seconds: 8),
    this._cooldownDuration = const Duration(milliseconds: 600),
    this._maxReconnectDuration = const Duration(seconds: 25),
    this._reconnectDelays,
    int Function()? clock,
    Future<void> Function(Duration)? delayFunction,
  })  : _connector = connector ?? const IoWebSocketConnector(),
        _tokenProvider = tokenProvider ?? FirebaseAuthTokenProvider(),
        _customServerWsUrl = serverWsUrl,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _delayFunction = delayFunction ?? Future.delayed;

  /// Maç olay akışı.
  Stream<OnlineMatchEvent> get events => _controller.stream;

  /// Belirtilen maça bağlanır.
  Future<void> connect(String matchId) async {
    _currentMatchId = matchId;
    _isClosed = false;
    _reconnectStartTimeMs = null;
    _reconnectAttempt = 0;

    await _performConnect();
  }

  Future<bool> _performConnect() async {
    if (_isClosed || _currentMatchId == null) return false;

    // 1. Token al
    final String? token;
    try {
      token = await _tokenProvider.getIdToken().timeout(_connectTimeout);
    } catch (e) {
      if (!_isClosed && !_isReconnecting) {
        _emit(OnlineMatchError('Token alınamadı: $e'));
      }
      return false;
    }

    if (_isClosed) return false;

    if (token == null || token.isEmpty) {
      if (!_isClosed && !_isReconnecting) {
        _emit(const OnlineMatchError('Kimlik jetonu bulunamadı.'));
      }
      return false;
    }

    // 2. WebSocket URL ve başlıklar
    final url = _customServerWsUrl != null
        ? ServerConfig.joinUrl(
            ServerConfig.toWebSocketUrl(_customServerWsUrl),
            ServerConfig.matchWsPath(_currentMatchId!),
          )
        : ServerConfig.matchWsUrl(_currentMatchId!);

    final headers = {'Authorization': 'Bearer $token'};

    try {
      final conn = await _connector.connect(
        url,
        headers: headers,
        timeout: _connectTimeout,
      );

      if (_isClosed) {
        await conn.close();
        return false;
      }

      _connection = conn;
      _subscription = conn.stream.listen(
        _handleIncomingMessage,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
      );

      _emit(const OnlineMatchConnected());
      _reconnectStartTimeMs = null;
      _reconnectAttempt = 0;
      return true;
    } catch (e) {
      if (!_isClosed && !_isReconnecting) {
        _emit(OnlineMatchError('Bağlantı kurulamadı: $e'));
      }
      return false;
    }
  }

  void _handleIncomingMessage(dynamic raw) {
    if (_isClosed) return;

    final msg = parseServerMessage(raw, receivedLocalMs: _clock());
    if (msg is StateServerMessage) {
      _emit(OnlineMatchStateUpdate(msg.state));
    } else if (msg is FeedbackServerMessage) {
      _emit(OnlineMatchFeedback(kind: msg.kind, reason: msg.reason));
    } else if (msg is FinalServerMessage) {
      _emit(OnlineMatchFinal(msg));
    } else if (msg is VoidedServerMessage) {
      _emit(OnlineMatchVoided(reason: msg.reason));
    } else if (msg is ErrorServerMessage) {
      _emit(OnlineMatchError(msg.code));
    }
  }

  void _handleStreamError(Object error) {
    if (_isClosed) return;
    _onConnectionLost();
  }

  void _handleStreamDone() {
    if (_isClosed) return;

    // Kod 4000: Aynı hesap başka bir yerden bağlandı, kesinlikle tekrar bağlanma
    if (_connection?.closeCode == 4000) {
      _emit(const OnlineMatchDisconnected(DisconnectReason.replaced));
      unawaited(_cleanupConnection());
      return;
    }

    _onConnectionLost();
  }

  void _onConnectionLost() {
    if (_isClosed || _isReconnecting) return;
    _scheduleReconnection();
  }

  Future<void> _scheduleReconnection() async {
    _isReconnecting = true;
    await _cleanupConnection();

    final now = _clock();
    _reconnectStartTimeMs ??= now;

    while (!_isClosed) {
      final currentNow = _clock();
      final elapsed = currentNow - _reconnectStartTimeMs!;

      if (elapsed >= _maxReconnectDuration.inMilliseconds) {
        // 25 sn doldu, kalıcı kopma bildir
        _isReconnecting = false;
        _emit(const OnlineMatchDisconnected(DisconnectReason.permanent));
        return;
      }

      // Üstel gecikme hesapla: 500ms, 1s, 2s, 4s ...
      final Duration delay;
      if (_reconnectDelays != null && _reconnectDelays.isNotEmpty) {
        final idx = min(_reconnectAttempt, _reconnectDelays.length - 1);
        delay = _reconnectDelays[idx];
      } else {
        final delayMs = 500 * (1 << min(_reconnectAttempt, 5));
        delay = Duration(milliseconds: delayMs);
      }

      // 25 saniyeyi aşmayacak şekilde gecikmeyi sınırla
      final remainingWindow = _maxReconnectDuration.inMilliseconds - elapsed;
      final actualDelay = delay.inMilliseconds > remainingWindow
          ? Duration(milliseconds: remainingWindow)
          : delay;

      if (actualDelay.inMilliseconds > 0) {
        await _delayFunction(actualDelay);
      }

      if (_isClosed) {
        _isReconnecting = false;
        return;
      }

      final success = await _performConnect();
      if (success) {
        _isReconnecting = false;
        // Yeniden bağlanınca güncel durumu almak için "sync" gönder
        await sync();
        return;
      }

      _reconnectAttempt++;
    }

    _isReconnecting = false;
  }

  /// Cevap gönderir.
  ///
  /// Cooldown (en az 600 ms) aşılmamışsa veya bağlantı yoksa false döner.
  bool submit(String text) {
    if (_isClosed || _connection == null) return false;

    final now = _clock();
    if (now - _lastSubmitTimeMs < _cooldownDuration.inMilliseconds) {
      // Hız sınırı (cooldown): erken çağrı sessizce yok sayılır
      return false;
    }

    final sanitized = sanitizeSubmitText(text);
    if (sanitized.isEmpty) return false;

    _lastSubmitTimeMs = now;
    try {
      _connection!.send(createSubmitMessage(sanitized));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Maçtan çıkma isteği gönderir (forfeit).
  Future<void> leave() async {
    if (_isClosed || _connection == null) return;
    try {
      _connection!.send(createLeaveMessage());
    } catch (_) {}
  }

  /// Durum senkronizasyonu talebi (`sync`) gönderir.
  Future<void> sync() async {
    if (_isClosed || _connection == null) return;
    try {
      _connection!.send(createSyncMessage());
    } catch (_) {}
  }

  /// Bağlantıyı istemci tarafından kasıtlı olarak kapatır; otomatik yeniden bağlanma YAPILMAZ.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _isReconnecting = false;

    await _cleanupConnection();
    _emit(const OnlineMatchDisconnected(DisconnectReason.closed));
  }

  void _emit(OnlineMatchEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
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

  /// Tüm kaynakları temizler ve akışı kapatır.
  Future<void> dispose() async {
    await close();
    await _controller.close();
  }
}
