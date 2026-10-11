import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/config/server_config.dart';
import '../data/auth_token_provider.dart';
import '../data/http_health_checker.dart';
import '../data/websocket_connector.dart';

/// Sunucu bağlantı testi aşama tanımlayıcıları.
enum ConnectionTestStepId {
  health,
  token,
  wsConnect,
  queue,
  cancel,
}

/// Her bir test aşamasının süresi ve sonucu.
class ConnectionTestStepResult {
  final ConnectionTestStepId stepId;
  final String stepName;
  final bool isSuccess;
  final int durationMs;
  final String? errorMessage;

  const ConnectionTestStepResult({
    required this.stepId,
    required this.stepName,
    required this.isSuccess,
    required this.durationMs,
    this.errorMessage,
  });

  @override
  String toString() {
    final status = isSuccess ? 'Tamam' : 'Hata ($errorMessage)';
    return '$stepName: $status (${durationMs}ms)';
  }
}

/// Tüm test aşamalarının genel raporu.
class ServerConnectionTestReport {
  final List<ConnectionTestStepResult> steps;
  final bool isOverallSuccess;
  final String? failureMessage;
  final int totalDurationMs;

  const ServerConnectionTestReport({
    required this.steps,
    required this.isOverallSuccess,
    this.failureMessage,
    required this.totalDurationMs,
  });
}

/// Sunucu adresi, kimlik jetonu ve eşleştirme WebSocket bağlantısını
/// baştan sona doğrulayan test servisi.
class ServerConnectionTest {
  final HttpHealthChecker _healthChecker;
  final AuthTokenProvider _tokenProvider;
  final WebSocketConnector _wsConnector;
  final String _serverUrl;
  final Duration _healthTimeout;
  final Duration _wsConnectTimeout;
  final Duration _messageTimeout;

  ServerConnectionTest({
    HttpHealthChecker? healthChecker,
    AuthTokenProvider? tokenProvider,
    WebSocketConnector? wsConnector,
    String? serverUrl,
    this._healthTimeout = const Duration(seconds: 10),
    this._wsConnectTimeout = const Duration(seconds: 10),
    this._messageTimeout = const Duration(seconds: 5),
  })  : _healthChecker = healthChecker ?? const IoHttpHealthChecker(),
        _tokenProvider = tokenProvider ?? FirebaseAuthTokenProvider(),
        _wsConnector = wsConnector ?? const IoWebSocketConnector(),
        _serverUrl = serverUrl ?? ServerConfig.serverUrl;

  /// Sıralı bağlantı testini yürütür ve [ServerConnectionTestReport] döner.
  Future<ServerConnectionTestReport> run() async {
    final steps = <ConnectionTestStepResult>[];
    final overallWatch = Stopwatch()..start();

    // 1. Aşama: GET /health kontrolü (10 sn zaman aşımı)
    final healthWatch = Stopwatch()..start();
    final healthUrl = ServerConfig.joinUrl(
      _serverUrl,
      ServerConfig.healthPath,
    );
    final healthUri = Uri.parse(healthUrl);
    if (kDebugMode) {
      debugPrint(
        '[server-test] hedef=${healthUri.scheme}://${healthUri.host}${healthUri.path}',
      );
    }

    try {
      final body = await _healthChecker.checkHealth(
        healthUrl,
        timeout: _healthTimeout,
      );
      healthWatch.stop();

      if (body != 'ok') {
        const err = 'Beklenmeyen yanıt (beklenen: ok)';
        if (kDebugMode) {
          debugPrint(
            '[server-test] aşama=Sağlık Kontrolü (/health) hata=HttpException mesaj=$err',
          );
        }
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.health,
            stepName: 'Sağlık Kontrolü (/health)',
            isSuccess: false,
            durationMs: healthWatch.elapsedMilliseconds,
            errorMessage: err,
          ),
        );
        overallWatch.stop();
        return ServerConnectionTestReport(
          steps: steps,
          isOverallSuccess: false,
          failureMessage: err,
          totalDurationMs: overallWatch.elapsedMilliseconds,
        );
      }

      steps.add(
        ConnectionTestStepResult(
          stepId: ConnectionTestStepId.health,
          stepName: 'Sağlık Kontrolü (/health)',
          isSuccess: true,
          durationMs: healthWatch.elapsedMilliseconds,
        ),
      );
    } catch (e) {
      healthWatch.stop();
      if (kDebugMode) {
        debugPrint(
          '[server-test] aşama=Sağlık Kontrolü (/health) hata=${e.runtimeType} mesaj=${_safeLogMessage(e)}',
        );
      }
      final err = _sanitizeError(e);
      steps.add(
        ConnectionTestStepResult(
          stepId: ConnectionTestStepId.health,
          stepName: 'Sağlık Kontrolü (/health)',
          isSuccess: false,
          durationMs: healthWatch.elapsedMilliseconds,
          errorMessage: err,
        ),
      );
      overallWatch.stop();
      return ServerConnectionTestReport(
        steps: steps,
        isOverallSuccess: false,
        failureMessage: err,
        totalDurationMs: overallWatch.elapsedMilliseconds,
      );
    }

    // 2. Aşama: Firebase Kimlik Jetonu Alma
    final tokenWatch = Stopwatch()..start();
    String? token;
    try {
      token = await _tokenProvider.getIdToken();
      tokenWatch.stop();

      if (token == null || token.isEmpty) {
        const err = 'Jeton alınamadı (oturum yok)';
        if (kDebugMode) {
          debugPrint(
            '[server-test] aşama=Kimlik Jetonu Alma hata=AuthException mesaj=$err',
          );
        }
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.token,
            stepName: 'Kimlik Jetonu Alma',
            isSuccess: false,
            durationMs: tokenWatch.elapsedMilliseconds,
            errorMessage: err,
          ),
        );
        overallWatch.stop();
        return ServerConnectionTestReport(
          steps: steps,
          isOverallSuccess: false,
          failureMessage: err,
          totalDurationMs: overallWatch.elapsedMilliseconds,
        );
      }

      steps.add(
        ConnectionTestStepResult(
          stepId: ConnectionTestStepId.token,
          stepName: 'Kimlik Jetonu Alma',
          isSuccess: true,
          durationMs: tokenWatch.elapsedMilliseconds,
        ),
      );
    } catch (e) {
      tokenWatch.stop();
      if (kDebugMode) {
        debugPrint(
          '[server-test] aşama=Kimlik Jetonu Alma hata=${e.runtimeType} mesaj=${_safeLogMessage(e)}',
        );
      }
      final err = _sanitizeError(e);
      steps.add(
        ConnectionTestStepResult(
          stepId: ConnectionTestStepId.token,
          stepName: 'Kimlik Jetonu Alma',
          isSuccess: false,
          durationMs: tokenWatch.elapsedMilliseconds,
          errorMessage: err,
        ),
      );
      overallWatch.stop();
      return ServerConnectionTestReport(
        steps: steps,
        isOverallSuccess: false,
        failureMessage: err,
        totalDurationMs: overallWatch.elapsedMilliseconds,
      );
    }

    // 3, 4, 5, 6. Aşamalar: WebSocket Bağlantısı ve Mesajlaşma
    WebSocketConnection? connection;
    StreamSubscription<dynamic>? subscription;

    try {
      // 3. Aşama: WebSocket Bağlantısı
      final wsWatch = Stopwatch()..start();
      final wsBaseUrl = ServerConfig.toWebSocketUrl(_serverUrl);
      final matchmakingWsUrl = ServerConfig.joinUrl(
        wsBaseUrl,
        ServerConfig.matchmakingWsPath,
      );
      final wsUri = Uri.parse(matchmakingWsUrl);
      if (kDebugMode) {
        debugPrint(
          '[server-test] hedef=${wsUri.scheme}://${wsUri.host}${wsUri.path}',
        );
      }

      try {
        connection = await _wsConnector.connect(
          matchmakingWsUrl,
          headers: {'Authorization': 'Bearer $token'},
          timeout: _wsConnectTimeout,
        );
        wsWatch.stop();
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.wsConnect,
            stepName: 'WebSocket Bağlantısı',
            isSuccess: true,
            durationMs: wsWatch.elapsedMilliseconds,
          ),
        );
      } catch (e) {
        wsWatch.stop();
        if (kDebugMode) {
          debugPrint(
            '[server-test] aşama=WebSocket Bağlantısı hata=${e.runtimeType} mesaj=${_safeLogMessage(e)}',
          );
        }
        final err = _sanitizeError(e);
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.wsConnect,
            stepName: 'WebSocket Bağlantısı',
            isSuccess: false,
            durationMs: wsWatch.elapsedMilliseconds,
            errorMessage: err,
          ),
        );
        overallWatch.stop();
        return ServerConnectionTestReport(
          steps: steps,
          isOverallSuccess: false,
          failureMessage: err,
          totalDurationMs: overallWatch.elapsedMilliseconds,
        );
      }

      // Tek dinleyici ile mesajları sırayla beklemek için completer köprüsü
      Completer<String>? nextMessageCompleter;

      subscription = connection.stream.listen(
        (dynamic raw) {
          final text = raw is List<int> ? utf8.decode(raw) : raw.toString();
          if (nextMessageCompleter != null &&
              !nextMessageCompleter.isCompleted) {
            nextMessageCompleter.complete(text);
          }
        },
        onError: (Object err) {
          if (nextMessageCompleter != null &&
              !nextMessageCompleter.isCompleted) {
            nextMessageCompleter.completeError(err);
          }
        },
        onDone: () {
          const closeError = SocketException('Bağlantı kapandı');
          if (nextMessageCompleter != null &&
              !nextMessageCompleter.isCompleted) {
            nextMessageCompleter.completeError(closeError);
          }
        },
      );

      // 4. Aşama: Kuyruğa Girme {"t":"queue","name":"Test"} -> {"t":"queued"}
      final queueWatch = Stopwatch()..start();
      try {
        nextMessageCompleter = Completer<String>();
        connection.send(jsonEncode({'t': 'queue', 'name': 'Test'}));

        final rawMsg = await nextMessageCompleter.future.timeout(
          _messageTimeout,
        );
        queueWatch.stop();

        final parsed = jsonDecode(rawMsg);
        if (parsed is Map<String, dynamic> && parsed['t'] == 'queued') {
          steps.add(
            ConnectionTestStepResult(
              stepId: ConnectionTestStepId.queue,
              stepName: 'Kuyruğa Girme (queue)',
              isSuccess: true,
              durationMs: queueWatch.elapsedMilliseconds,
            ),
          );
        } else {
          final tVal =
              parsed is Map<String, dynamic> ? parsed['t'] : 'geçersiz';
          final err = 'Beklenmeyen yanıt (beklenen: queued, gelen: $tVal)';
          if (kDebugMode) {
            debugPrint(
              '[server-test] aşama=Kuyruğa Girme (queue) hata=FormatException mesaj=$err',
            );
          }
          steps.add(
            ConnectionTestStepResult(
              stepId: ConnectionTestStepId.queue,
              stepName: 'Kuyruğa Girme (queue)',
              isSuccess: false,
              durationMs: queueWatch.elapsedMilliseconds,
              errorMessage: err,
            ),
          );
          overallWatch.stop();
          return ServerConnectionTestReport(
            steps: steps,
            isOverallSuccess: false,
            failureMessage: err,
            totalDurationMs: overallWatch.elapsedMilliseconds,
          );
        }
      } catch (e) {
        queueWatch.stop();
        if (kDebugMode) {
          debugPrint(
            '[server-test] aşama=Kuyruğa Girme (queue) hata=${e.runtimeType} mesaj=${_safeLogMessage(e)}',
          );
        }
        final err = _sanitizeError(e);
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.queue,
            stepName: 'Kuyruğa Girme (queue)',
            isSuccess: false,
            durationMs: queueWatch.elapsedMilliseconds,
            errorMessage: err,
          ),
        );
        overallWatch.stop();
        return ServerConnectionTestReport(
          steps: steps,
          isOverallSuccess: false,
          failureMessage: err,
          totalDurationMs: overallWatch.elapsedMilliseconds,
        );
      }

      // 5. Aşama: Kuyruktan Çıkma {"t":"cancel"} -> {"t":"cancelled"}
      final cancelWatch = Stopwatch()..start();
      try {
        nextMessageCompleter = Completer<String>();
        connection.send(jsonEncode({'t': 'cancel'}));

        final rawMsg = await nextMessageCompleter.future.timeout(
          _messageTimeout,
        );
        cancelWatch.stop();

        final parsed = jsonDecode(rawMsg);
        if (parsed is Map<String, dynamic> && parsed['t'] == 'cancelled') {
          steps.add(
            ConnectionTestStepResult(
              stepId: ConnectionTestStepId.cancel,
              stepName: 'Kuyruktan Çıkma (cancel)',
              isSuccess: true,
              durationMs: cancelWatch.elapsedMilliseconds,
            ),
          );
        } else {
          final tVal =
              parsed is Map<String, dynamic> ? parsed['t'] : 'geçersiz';
          final err = 'Beklenmeyen yanıt (beklenen: cancelled, gelen: $tVal)';
          if (kDebugMode) {
            debugPrint(
              '[server-test] aşama=Kuyruktan Çıkma (cancel) hata=FormatException mesaj=$err',
            );
          }
          steps.add(
            ConnectionTestStepResult(
              stepId: ConnectionTestStepId.cancel,
              stepName: 'Kuyruktan Çıkma (cancel)',
              isSuccess: false,
              durationMs: cancelWatch.elapsedMilliseconds,
              errorMessage: err,
            ),
          );
          overallWatch.stop();
          return ServerConnectionTestReport(
            steps: steps,
            isOverallSuccess: false,
            failureMessage: err,
            totalDurationMs: overallWatch.elapsedMilliseconds,
          );
        }
      } catch (e) {
        cancelWatch.stop();
        if (kDebugMode) {
          debugPrint(
            '[server-test] aşama=Kuyruktan Çıkma (cancel) hata=${e.runtimeType} mesaj=${_safeLogMessage(e)}',
          );
        }
        final err = _sanitizeError(e);
        steps.add(
          ConnectionTestStepResult(
            stepId: ConnectionTestStepId.cancel,
            stepName: 'Kuyruktan Çıkma (cancel)',
            isSuccess: false,
            durationMs: cancelWatch.elapsedMilliseconds,
            errorMessage: err,
          ),
        );
        overallWatch.stop();
        return ServerConnectionTestReport(
          steps: steps,
          isOverallSuccess: false,
          failureMessage: err,
          totalDurationMs: overallWatch.elapsedMilliseconds,
        );
      }
    } finally {
      unawaited(subscription?.cancel());
      try {
        await connection?.close();
      } catch (_) {
        // Kapanış hatası yoksayılır
      }
    }

    overallWatch.stop();
    return ServerConnectionTestReport(
      steps: steps,
      isOverallSuccess: true,
      totalDurationMs: overallWatch.elapsedMilliseconds,
    );
  }

  /// Loglama için hassas bilgileri (jeton, sorgu parametresi) temizler.
  static String _safeLogMessage(Object error) {
    var msg = error.toString();
    msg = msg.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    msg = msg.replaceAll(
      RegExp(r'token[:=]\s*[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'token=[REDACTED]',
    );
    msg = msg.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '[REDACTED_JWT]',
    );
    msg = msg.replaceAll(RegExp(r'\?[^#\s\)]*'), '');
    return msg;
  }

  /// Hataları güvenli, jeton ve hassas bilgi içermeyen net kategorilere dönüştürür.
  static String _sanitizeError(Object error) {
    if (error is TimeoutException) {
      return 'Zaman aşımı';
    }
    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      final osMsg = error.osError?.message.toLowerCase() ?? '';
      final osCode = error.osError?.errorCode;
      if (msg.contains('failed host lookup') ||
          osMsg.contains('failed host lookup') ||
          msg.contains('nodename nor servname')) {
        return 'DNS / sunucu erişilemiyor';
      }
      if (msg.contains('unreachable') ||
          msg.contains('connection refused') ||
          osMsg.contains('connection refused')) {
        return 'Ağ yok / bağlantı kurulamadı';
      }
      if (msg.contains('connection reset') ||
          osMsg.contains('connection reset') ||
          osCode == 104 ||
          osCode == 10054) {
        return 'Bağlantı sıfırlandı (engellendi / reset)';
      }
      return 'Ağ hatası';
    }
    if (error is HandshakeException ||
        error is TlsException ||
        error is CertificateException) {
      final msg = error.toString().toLowerCase();
      if (msg.contains('connection reset') || msg.contains('closed')) {
        return 'TLS bağlantısı sıfırlandı (engellendi)';
      }
      if (msg.contains('cert') || msg.contains('verify_failed')) {
        return 'TLS / Sertifika doğrulama hatası';
      }
      return 'TLS el sıkışma hatası';
    }
    if (error is HttpException) {
      if (error.message.contains('401')) {
        return '401 (Jeton reddedildi)';
      }
      return 'Sunucu hatası';
    }
    if (error is WebSocketException) {
      if (error.message.contains('401')) {
        return '401 (Jeton reddedildi)';
      }
      return 'WebSocket bağlantı hatası';
    }
    if (error is FormatException) {
      return 'Geçersiz veri biçimi';
    }
    if (error is StateError) {
      return 'Geçersiz durum hatası';
    }
    if (error is TypeError) {
      return 'Veri tipi uyuşmazlığı';
    }

    final str = error.toString().toLowerCase();
    if (str.contains('401') || str.contains('unauthorized')) {
      return '401 (Jeton reddedildi)';
    }
    if (str.contains('timeout')) {
      return 'Zaman aşımı';
    }
    if (str.contains('failed host lookup')) {
      return 'DNS / sunucu erişilemiyor';
    }
    if (str.contains('connection reset')) {
      return 'Bağlantı sıfırlandı (engellendi / reset)';
    }
    if (str.contains('handshake') || str.contains('certificate')) {
      return 'TLS el sıkışma hatası';
    }
    if (str.contains('socket') || str.contains('network')) {
      return 'Ağ hatası';
    }
    if (str.contains('beklenmeyen yanıt')) {
      final prefix = 'exception: ';
      final raw = error.toString();
      return raw.toLowerCase().startsWith(prefix)
          ? raw.substring(prefix.length)
          : raw;
    }
    return 'Beklenmeyen hata';
  }
}
