import 'dart:async';
import 'dart:io';

/// Tek bir WebSocket bağlantısını temsil eden soyut arayüz.
abstract interface class WebSocketConnection {
  /// Sunucudan gelen mesajları içeren akış (String veya `List<int>`).
  Stream<dynamic> get stream;

  /// Sunucuya metin formatında mesaj gönderir.
  void send(String data);

  /// WebSocket bağlantısını kapatır.
  Future<void> close([int? code, String? reason]);
}

/// WebSocket bağlantısı kuran fabrika / bağlayıcı arayüzü.
abstract interface class WebSocketConnector {
  /// Verilen [url] ve [headers] ile WebSocket bağlantısı kurar.
  Future<WebSocketConnection> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? timeout,
  });
}

/// `dart:io` WebSocket uygulamasını sarmalayan [WebSocketConnection].
class IoWebSocketConnection implements WebSocketConnection {
  final WebSocket _socket;

  IoWebSocketConnection(this._socket);

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void send(String data) {
    _socket.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) {
    return _socket.close(code, reason);
  }
}

/// Gerçek `dart:io` WebSocket kütüphanesini kullanan [WebSocketConnector].
class IoWebSocketConnector implements WebSocketConnector {
  const IoWebSocketConnector();

  @override
  Future<WebSocketConnection> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? timeout,
  }) async {
    final future = WebSocket.connect(
      url,
      headers: headers,
    );
    final socket =
        timeout != null ? await future.timeout(timeout) : await future;
    return IoWebSocketConnection(socket);
  }
}

/// Test ortamında kullanılmak üzere hazırlanmış sahte WebSocket bağlantısı.
class FakeWebSocketConnection implements WebSocketConnection {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast(sync: true);
  final List<String> sentMessages = [];
  bool isClosed = false;
  int? closeCode;
  String? closeReason;

  void Function(String message)? onSend;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String data) {
    if (isClosed) {
      throw StateError('Cannot send on closed connection');
    }
    sentMessages.add(data);
    onSend?.call(data);
  }

  /// Sunucudan mesaj gelmiş gibi simüle eder.
  void emitIncoming(String data) {
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  /// Sunucudan hata akışı simüle eder.
  void emitError(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    closeCode = code;
    closeReason = reason;
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}

/// Test ortamında kullanılmak üzere hazırlanmış sahte bağlayıcı.
class FakeWebSocketConnector implements WebSocketConnector {
  WebSocketConnection? connectionToReturn;
  Object? errorToThrow;
  String? lastConnectedUrl;
  Map<String, dynamic>? lastHeaders;

  FakeWebSocketConnector({
    this.connectionToReturn,
    this.errorToThrow,
  });

  @override
  Future<WebSocketConnection> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? timeout,
  }) async {
    lastConnectedUrl = url;
    lastHeaders = headers;
    if (errorToThrow != null) {
      // ignore: only_throw_errors
      throw errorToThrow!;
    }
    return connectionToReturn ?? FakeWebSocketConnection();
  }
}

