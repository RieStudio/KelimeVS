import 'dart:async';
import 'dart:convert';

import '../../../core/config/server_config.dart';
import '../../online/data/auth_token_provider.dart';
import '../../online/data/websocket_connector.dart';
import '../../online/domain/models/online_messages.dart';

/// Arkadaş düellosu sürecinde oluşan olayların temel sınıfı.
sealed class FriendMatchEvent {
  const FriendMatchEvent();
}

/// Eşleştirme sunucusuna bağlanılıyor.
class FriendMatchConnecting extends FriendMatchEvent {
  const FriendMatchConnecting();

  @override
  String toString() => 'FriendMatchConnecting()';
}

/// Oda başarıyla kuruldu.
class FriendMatchRoomCreated extends FriendMatchEvent {
  final String code;
  final int expiresAt;

  const FriendMatchRoomCreated({
    required this.code,
    required this.expiresAt,
  });

  @override
  String toString() =>
      'FriendMatchRoomCreated(code: $code, expiresAt: $expiresAt)';
}

/// Askıdaki odaya başarıyla devam edildi.
class FriendMatchRoomResumed extends FriendMatchEvent {
  final String code;
  final int expiresAt;

  const FriendMatchRoomResumed({
    required this.code,
    required this.expiresAt,
  });

  @override
  String toString() =>
      'FriendMatchRoomResumed(code: $code, expiresAt: $expiresAt)';
}

/// Rakip odaya katıldı ve maç oluşturuldu (`matched`).
class FriendMatchMatched extends FriendMatchEvent {
  final String matchId;
  final String opponentName;

  const FriendMatchMatched({
    required this.matchId,
    required this.opponentName,
  });

  @override
  String toString() =>
      'FriendMatchMatched(matchId: $matchId, opponentName: $opponentName)';
}

/// Odanın 5 dakikalık süresi doldu.
class FriendMatchRoomExpired extends FriendMatchEvent {
  const FriendMatchRoomExpired();

  @override
  String toString() => 'FriendMatchRoomExpired()';
}

/// Oda iptal edildi.
class FriendMatchCancelled extends FriendMatchEvent {
  const FriendMatchCancelled();

  @override
  String toString() => 'FriendMatchCancelled()';
}

/// Hata oluştu (oda bulunamadı, rate limited, engellendi vb.).
class FriendMatchFailed extends FriendMatchEvent {
  final String code;
  final String message;
  final int? retryAfterSeconds;

  const FriendMatchFailed({
    required this.code,
    required this.message,
    this.retryAfterSeconds,
  });

  @override
  String toString() =>
      'FriendMatchFailed(code: $code, message: $message, retryAfterSeconds: $retryAfterSeconds)';
}

/// Arkadaş düellosu lobi WebSocket iletişimi yöneticisi.
class FriendMatchClient {
  final WebSocketConnector _connector;
  final AuthTokenProvider _tokenProvider;
  final String? _customServerWsUrl;
  final Duration _connectTimeout;

  final StreamController<FriendMatchEvent> _controller =
      StreamController<FriendMatchEvent>.broadcast(sync: true);

  WebSocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  bool _isClosed = false;

  FriendMatchClient({
    WebSocketConnector? connector,
    AuthTokenProvider? tokenProvider,
    String? serverWsUrl,
    Duration? connectTimeout,
  })  : _connector = connector ?? const IoWebSocketConnector(),
        _tokenProvider = tokenProvider ?? const FirebaseAuthTokenProvider(),
        _customServerWsUrl = serverWsUrl,
        _connectTimeout = connectTimeout ?? const Duration(seconds: 10);

  Stream<FriendMatchEvent> get events => _controller.stream;

  Future<void> _ensureConnected() async {
    if (_connection != null && !_isClosed) return;

    _emit(const FriendMatchConnecting());

    final token = await _tokenProvider.getIdToken();
    final baseWsUrl = _customServerWsUrl != null
        ? ServerConfig.toWebSocketUrl(_customServerWsUrl)
        : ServerConfig.wsUrl;
    final url = ServerConfig.joinUrl(baseWsUrl, ServerConfig.matchmakingWsPath);

    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final conn = await _connector.connect(
        url,
        headers: headers,
        timeout: _connectTimeout,
      );
      _connection = conn;
      _subscription = conn.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
    } catch (err) {
      _emit(
        FriendMatchFailed(
          code: 'network_error',
          message: 'Sunucuya bağlanılamadı: $err',
        ),
      );
    }
  }

  /// Yeni bir arkadaş odası kurar.
  Future<void> createRoom({String? name}) async {
    await _ensureConnected();
    final msg = createRoomMessage(name: name);
    _send(msg);
  }

  /// Askıdaki odaya devam eder (WhatsApp dönüşü vb.).
  Future<void> resumeRoom(String code) async {
    await _ensureConnected();
    final msg = createResumeRoomMessage(code);
    _send(msg);
  }

  /// Davet koduyla var olan bir odaya katılır.
  Future<void> joinRoom(String code, {String? name}) async {
    await _ensureConnected();
    final msg = createJoinRoomMessage(code, name: name);
    _send(msg);
  }

  /// Odayı iptal eder ve kapatır.
  Future<void> cancelRoom({String? code}) async {
    if (_connection != null) {
      final msg = createCancelRoomMessage(code: code);
      _send(msg);
    }
    await close();
  }

  void _send(String message) {
    try {
      _connection?.send(message);
    } catch (err) {
      _emit(
        FriendMatchFailed(
          code: 'send_error',
          message: 'Mesaj gönderilemedi: $err',
        ),
      );
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final message = parseServerMessage(raw);
      if (message is RoomCreatedServerMessage) {
        _emit(
          FriendMatchRoomCreated(
            code: message.code,
            expiresAt: message.expiresAt,
          ),
        );
      } else if (message is RoomResumedServerMessage) {
        _emit(
          FriendMatchRoomResumed(
            code: message.code,
            expiresAt: message.expiresAt,
          ),
        );
      } else if (message is MatchedServerMessage) {
        _emit(
          FriendMatchMatched(
            matchId: message.matchId,
            opponentName: message.opponentName,
          ),
        );
      } else if (message is RoomExpiredServerMessage) {
        _emit(const FriendMatchRoomExpired());
      } else if (message is CancelledServerMessage) {
        _emit(const FriendMatchCancelled());
      } else if (message is ErrorServerMessage) {
        // Hata kodunu ve varsa mesajı ayrıştır
        Map<String, dynamic>? decoded;
        try {
          if (raw is String) {
            decoded = jsonDecode(raw) as Map<String, dynamic>?;
          } else if (raw is Map<String, dynamic>) {
            decoded = raw;
          }
        } catch (_) {}

        final msgText = decoded?['message'] as String? ?? message.code;
        final retryAfter = (decoded?['retryAfterSeconds'] as num?)?.toInt();

        _emit(
          FriendMatchFailed(
            code: message.code,
            message: msgText,
            retryAfterSeconds: retryAfter,
          ),
        );
      }
    } catch (err) {
      _emit(
        FriendMatchFailed(
          code: 'parse_error',
          message: 'Sunucu yanıtı anlaşılamadı: $err',
        ),
      );
    }
  }

  void _handleError(dynamic error) {
    if (_isClosed) return;
    _emit(
      FriendMatchFailed(
        code: 'socket_error',
        message: 'Bağlantı kesildi: $error',
      ),
    );
  }

  void _handleDone() {
    _connection = null;
    _subscription?.cancel();
    _subscription = null;
  }

  void _emit(FriendMatchEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<void> close() async {
    _isClosed = true;
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      await sub.cancel();
    }
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

