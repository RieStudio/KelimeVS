import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/config/server_config.dart';
import '../../online/data/auth_token_provider.dart';
import '../../online/data/websocket_connector.dart';
import 'match_request_messages.dart';

/// /ws/user WebSocket istemcisi.
class UserInboxClient {
  final WebSocketConnector _connector;
  final AuthTokenProvider _tokenProvider;
  final String? _customServerWsUrl;
  final Duration connectTimeout;
  final Duration pingInterval;
  final Duration pongTimeout;
  final Duration maxReconnectDelay;
  final List<Duration>? customReconnectDelays;
  final void Function()? onAccountDeleted;
  final String Function() getCurrentPresenceState;

  final StreamController<UserInboxServerMessage> _messageController =
      StreamController<UserInboxServerMessage>.broadcast(sync: true);
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast(sync: true);

  WebSocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _pongWatchdogTimer;
  Timer? _reconnectTimer;
  Timer? _snapshotPhaseTimer;

  bool _isClosed = false;
  bool _isReconnecting = false;
  bool _hasAccountDeleted = false;
  bool _isSnapshotPhase = false;
  int _reconnectAttempt = 0;
  final Random _random = Random();

  UserInboxClient({
    WebSocketConnector? connector,
    AuthTokenProvider? tokenProvider,
    String? serverWsUrl,
    this.connectTimeout = const Duration(seconds: 8),
    this.pingInterval = const Duration(seconds: 25),
    this.pongTimeout = const Duration(seconds: 10),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.customReconnectDelays,
    this.onAccountDeleted,
    required this.getCurrentPresenceState,
  })  : _connector = connector ?? const IoWebSocketConnector(),
        _tokenProvider = tokenProvider ?? FirebaseAuthTokenProvider(),
        _customServerWsUrl = serverWsUrl;

  Stream<UserInboxServerMessage> get messages => _messageController.stream;
  Stream<bool> get connectionStatus => _connectionStateController.stream;

  bool get isConnected => _connection != null;
  bool get isClosed => _isClosed;
  bool get isReconnecting => _isReconnecting;
  bool get isSnapshotPhase => _isSnapshotPhase;

  @visibleForTesting
  set isSnapshotPhase(bool value) => _isSnapshotPhase = value;

  /// Kullanıcı bildirim soketine bağlanır.
  Future<void> connect() async {
    _isClosed = false;
    _hasAccountDeleted = false;
    _reconnectAttempt = 0;

    await _performConnect();
  }

  Future<bool> _performConnect() async {
    if (_isClosed || _hasAccountDeleted) return false;

    // 1. Taze kimlik doğrulama jetonu al
    final String? token;
    try {
      token = await _tokenProvider.getIdToken().timeout(connectTimeout);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserInboxClient] Token fetch error: $e');
      }
      _scheduleReconnect();
      return false;
    }

    if (_isClosed || _hasAccountDeleted) return false;

    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        debugPrint('[UserInboxClient] No auth token available.');
      }
      return false;
    }

    // 2. URL ve başlıklar
    final url = _customServerWsUrl != null
        ? ServerConfig.joinUrl(
            ServerConfig.toWebSocketUrl(_customServerWsUrl),
            ServerConfig.userWsPath,
          )
        : ServerConfig.userWsUrl;

    final headers = {'Authorization': 'Bearer $token'};

    try {
      final conn = await _connector.connect(
        url,
        headers: headers,
        timeout: connectTimeout,
      );

      if (_isClosed || _hasAccountDeleted) {
        await conn.close(1000, 'closed');
        return false;
      }

      _connection = conn;
      _reconnectAttempt = 0;
      _isReconnecting = false;
      _isSnapshotPhase = true;
      _snapshotPhaseTimer?.cancel();
      _snapshotPhaseTimer = Timer(const Duration(seconds: 2), () {
        _isSnapshotPhase = false;
      });

      _subscription = conn.stream.listen(
        _handleIncomingData,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
      );

      _connectionStateController.add(true);

      // Bağlantı kurulur kurulmaz ilk mesaj olarak güncel presence durumunu gönder
      final currentPresence = getCurrentPresenceState();
      send(UserInboxPresenceMessage(currentPresence));

      // Kalp atışı (Ping/Pong) döngüsünü başlat
      _startHeartbeat();

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserInboxClient] Connection failed: $e');
      }

      // HTTP 410 (Gone) durumunda hesap silinmiştir
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('410')) {
        _handlePermanentAccountDeletion();
        return false;
      }

      _scheduleReconnect();
      return false;
    }
  }

  void _handleIncomingData(dynamic raw) {
    if (_isClosed) return;

    final message = parseUserInboxServerMessage(raw, isSnapshot: _isSnapshotPhase);
    if (message == null) {
      // Ayrıştırılamayan veya bilinmeyen mesaj; toleranslı davranılır ve bağlantı korunur
      return;
    }

    if (message is UserInboxPongMessage) {
      // Pong alındı, bekçi zamanlayıcısını ve snapshot evresini sonlandır
      _isSnapshotPhase = false;
      _snapshotPhaseTimer?.cancel();
      _snapshotPhaseTimer = null;
      _pongWatchdogTimer?.cancel();
      _pongWatchdogTimer = null;
      return;
    }

    _messageController.add(message);
  }

  void _handleStreamError(Object error) {
    if (_isClosed) return;
    if (kDebugMode) {
      debugPrint('[UserInboxClient] Stream error: $error');
    }
    _onConnectionLost();
  }

  void _handleStreamDone() {
    if (_isClosed) return;

    final code = _connection?.closeCode;
    final reason = _connection?.closeReason;

    if (code == 4001 || reason == 'account_deleted') {
      _handlePermanentAccountDeletion();
      return;
    }

    _onConnectionLost();
  }

  void _onConnectionLost() {
    _cleanupConnection();
    _connectionStateController.add(false);

    if (!_isClosed && !_hasAccountDeleted) {
      _scheduleReconnect();
    }
  }

  void _handlePermanentAccountDeletion() {
    _hasAccountDeleted = true;
    _isClosed = true;
    _cleanupConnection();
    _connectionStateController.add(false);
    onAccountDeleted?.call();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      _sendPingAndWatchForPong();
    });
  }

  void _sendPingAndWatchForPong() {
    if (_connection == null || _isClosed) return;

    // Bekçi zamanlayıcısını ping göndermeden HEMEN ÖNCE kuruyoruz ki,
    // senkron veya çok hızlı gelen pong yanıtları zamanlayıcıyı hemen iptal edebilsin.
    _pongWatchdogTimer?.cancel();
    _pongWatchdogTimer = Timer(pongTimeout, () {
      if (kDebugMode) {
        debugPrint('[UserInboxClient] Pong timeout! Treating connection as dead.');
      }
      _onConnectionLost();
    });

    send(const UserInboxPingMessage());
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongWatchdogTimer?.cancel();
    _pongWatchdogTimer = null;
  }

  void _cleanupConnection() {
    _stopHeartbeat();
    _snapshotPhaseTimer?.cancel();
    _snapshotPhaseTimer = null;
    _isSnapshotPhase = false;
    _subscription?.cancel();
    _subscription = null;
    try {
      _connection?.close();
    } catch (_) {}
    _connection = null;
  }

  void _scheduleReconnect() {
    if (_isClosed || _hasAccountDeleted || _isReconnecting) return;
    _isReconnecting = true;
    _reconnectTimer?.cancel();

    final Duration delay;
    if (customReconnectDelays != null && customReconnectDelays!.isNotEmpty) {
      final index = min(_reconnectAttempt, customReconnectDelays!.length - 1);
      delay = customReconnectDelays![index];
    } else {
      // Üstel geri çekilme + jitter: 1s, 2s, 4s, 8s... max 30s
      final expSec = pow(2, min(_reconnectAttempt, 5)).toInt(); // 1, 2, 4, 8, 16, 32
      final maxSec = min(expSec, maxReconnectDelay.inSeconds);
      // ±20% jitter
      final jitterMs = _random.nextInt(max(1, (maxSec * 200)));
      delay = Duration(milliseconds: (maxSec * 1000) + jitterMs);
    }

    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isClosed && !_hasAccountDeleted) {
        unawaited(_performConnect());
      }
    });
  }

  /// Sokete istemci mesajı gönderir.
  bool send(UserInboxClientMessage message) {
    if (_connection == null || _isClosed) return false;

    try {
      _connection!.send(message.toWireJson());
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserInboxClient] Send error: $e');
      }
      return false;
    }
  }

  /// Soket bağlantısını kasıtlı olarak kapatır.
  Future<void> close({int code = 1000, String reason = 'normal_closure'}) async {
    _isClosed = true;
    _snapshotPhaseTimer?.cancel();
    _snapshotPhaseTimer = null;
    _isSnapshotPhase = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;

    final conn = _connection;
    _connection = null;

    if (conn != null) {
      try {
        await conn.close(code, reason);
      } catch (_) {}
    }

    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(false);
    }
  }

  Future<void> dispose() async {
    _isClosed = true;
    _snapshotPhaseTimer?.cancel();
    _snapshotPhaseTimer = null;
    _isSnapshotPhase = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;

    final conn = _connection;
    _connection = null;

    if (conn != null) {
      try {
        await conn.close(1000, 'disposed');
      } catch (_) {}
    }

    await _messageController.close();
    await _connectionStateController.close();
  }
}
