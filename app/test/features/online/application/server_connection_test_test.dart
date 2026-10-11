@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:app/features/online/application/server_connection_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/http_health_checker.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerConnectionTest (Sıralı Bağlantı Testi)', () {
    const sensitiveToken = 'super_secret_jwt_firebase_id_token_12345';
    const serverUrl = 'https://api.riestudio.com.tr';

    test('tam başarılı akış: health -> token -> connect -> queue -> cancel -> close', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'ok');
      final fakeAuth = FakeAuthTokenProvider(token: sensitiveToken);
      final fakeConn = FakeWebSocketConnection();

      // Sunucu mesaj akışını simüle et
      fakeConn.onSend = (message) {
        if (message.contains('"queue"')) {
          fakeConn.emitIncoming('{"t":"queued"}');
        } else if (message.contains('"cancel"')) {
          fakeConn.emitIncoming('{"t":"cancelled"}');
        }
      };

      final fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConn);

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: fakeConnector,
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isTrue);
      expect(report.failureMessage, isNull);
      expect(report.steps.length, 5);

      // Aşama 1: Health
      expect(report.steps[0].stepId, ConnectionTestStepId.health);
      expect(report.steps[0].isSuccess, isTrue);
      expect(fakeHealth.lastCheckedUrl, 'https://api.riestudio.com.tr/health');

      // Aşama 2: Token
      expect(report.steps[1].stepId, ConnectionTestStepId.token);
      expect(report.steps[1].isSuccess, isTrue);

      // Aşama 3: WsConnect
      expect(report.steps[2].stepId, ConnectionTestStepId.wsConnect);
      expect(report.steps[2].isSuccess, isTrue);
      expect(
        fakeConnector.lastConnectedUrl,
        'wss://api.riestudio.com.tr/ws/matchmaking',
      );
      expect(
        fakeConnector.lastHeaders?['Authorization'],
        'Bearer $sensitiveToken',
      );

      // Aşama 4: Queue
      expect(report.steps[3].stepId, ConnectionTestStepId.queue);
      expect(report.steps[3].isSuccess, isTrue);
      expect(fakeConn.sentMessages[0], '{"t":"queue","name":"Test"}');

      // Aşama 5: Cancel
      expect(report.steps[4].stepId, ConnectionTestStepId.cancel);
      expect(report.steps[4].isSuccess, isTrue);
      expect(fakeConn.sentMessages[1], '{"t":"cancel"}');

      // 6: Bağlantı kapatıldı mı?
      expect(fakeConn.isClosed, isTrue);
    });

    test('GET /health "ok" dönmezse test ilk aşamada başarısız olur', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'bad_gateway');
      final fakeAuth = FakeAuthTokenProvider(token: sensitiveToken);
      final fakeConn = FakeWebSocketConnection();
      final fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConn);

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: fakeConnector,
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps.length, 1);
      expect(report.steps[0].stepId, ConnectionTestStepId.health);
      expect(report.steps[0].isSuccess, isFalse);
      expect(report.steps[0].errorMessage, contains('Beklenmeyen yanıt'));
      expect(report.failureMessage, contains('Beklenmeyen yanıt'));
      // Sonraki aşamalar çalıştırılmamalı
      expect(fakeConnector.lastConnectedUrl, isNull);
    });

    test('GET /health DNS hatasında açık hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: const SocketException('Failed host lookup: api.riestudio.com.tr'),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'DNS / sunucu erişilemiyor');
    });

    test('GET /health zaman aşımında net hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: TimeoutException('Health timeout'),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'Zaman aşımı');
    });

    test('jeton alınamazsa (null) test 2. aşamada durur', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'ok');
      final fakeAuth = FakeAuthTokenProvider(token: null);
      final fakeConnector = FakeWebSocketConnector();

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: fakeConnector,
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps.length, 2);
      expect(report.steps[0].isSuccess, isTrue);
      expect(report.steps[1].stepId, ConnectionTestStepId.token);
      expect(report.steps[1].isSuccess, isFalse);
      expect(report.steps[1].errorMessage, contains('Jeton alınamadı'));
      expect(fakeConnector.lastConnectedUrl, isNull);
    });

    test('WebSocket 401 hatası aldığında (jeton reddi) net raporlar', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'ok');
      final fakeAuth = FakeAuthTokenProvider(token: sensitiveToken);
      final fakeConnector = FakeWebSocketConnector(
        errorToThrow: const WebSocketException('Invalid status code: 401'),
      );

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: fakeConnector,
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps.length, 3);
      expect(report.steps[0].isSuccess, isTrue);
      expect(report.steps[1].isSuccess, isTrue);
      expect(report.steps[2].stepId, ConnectionTestStepId.wsConnect);
      expect(report.steps[2].isSuccess, isFalse);
      expect(report.steps[2].errorMessage, '401 (Jeton reddedildi)');
    });

    test('kuyruğa girme adımında queued yerine beklenmeyen yanıt gelirse hata verir', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'ok');
      final fakeAuth = FakeAuthTokenProvider(token: sensitiveToken);
      final fakeConn = FakeWebSocketConnection();

      fakeConn.onSend = (message) {
        if (message.contains('"queue"')) {
          fakeConn.emitIncoming('{"t":"error","code":"already_queued"}');
        }
      };

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: FakeWebSocketConnector(connectionToReturn: fakeConn),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps.length, 4);
      expect(report.steps[3].stepId, ConnectionTestStepId.queue);
      expect(report.steps[3].isSuccess, isFalse);
      expect(report.steps[3].errorMessage, contains('Beklenmeyen yanıt'));
      expect(fakeConn.isClosed, isTrue);
    });

    test('kuyruk adımında sunucu yanıt vermezse zaman aşımı bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(responseToReturn: 'ok');
      final fakeAuth = FakeAuthTokenProvider(token: sensitiveToken);
      final fakeConn = FakeWebSocketConnection();
      // fakeConn.onSend hiçbir şey yaymaz -> timeout

      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: fakeAuth,
        wsConnector: FakeWebSocketConnector(connectionToReturn: fakeConn),
        serverUrl: serverUrl,
        messageTimeout: const Duration(milliseconds: 50),
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[3].stepId, ConnectionTestStepId.queue);
      expect(report.steps[3].isSuccess, isFalse);
      expect(report.steps[3].errorMessage, 'Zaman aşımı');
      expect(fakeConn.isClosed, isTrue);
    });

    test('GET /health bağlantı sıfırlandığında (TCP reset/errno 104) net hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: const SocketException(
          'Connection reset by peer',
          osError: OSError('Connection reset by peer', 104),
        ),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'Bağlantı sıfırlandı (engellendi / reset)');
    });

    test('GET /health TLS el sıkışma / handshake hatasında net hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: const HandshakeException(
          'Handshake error in client (OS Error: Connection reset by peer)',
        ),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'TLS bağlantısı sıfırlandı (engellendi)');
    });

    test('GET /health sertifika doğrulama hatasında açık hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: const HandshakeException(
          'Handshake error in client (CERTIFICATE_VERIFY_FAILED: self signed certificate)',
        ),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'TLS / Sertifika doğrulama hatası');
    });

    test('GET /health geçersiz veri biçimi / FormatException hatasında net hata bildirir', () async {
      final fakeHealth = FakeHttpHealthChecker(
        errorToThrow: const FormatException('Invalid UTF-8 encoding'),
      );
      final service = ServerConnectionTest(
        healthChecker: fakeHealth,
        tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        wsConnector: FakeWebSocketConnector(),
        serverUrl: serverUrl,
      );

      final report = await service.run();

      expect(report.isOverallSuccess, isFalse);
      expect(report.steps[0].errorMessage, 'Geçersiz veri biçimi');
    });

    test('GÜVENLİK KURALI: sonuç ve hata metinlerinde jeton, sorgu parametresi ve hassas bilgi bulunamaz', () async {
      // Birkaç hata durumu ve başarılı durumu döngüyle sına
      final scenarios = <Future<ServerConnectionTestReport>>[
        // 1. Başarılı
        ServerConnectionTest(
          healthChecker: FakeHttpHealthChecker(responseToReturn: 'ok'),
          tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
          wsConnector: FakeWebSocketConnector(
            connectionToReturn: FakeWebSocketConnection()
              ..onSend = (m) {
                if (m.contains('"queue"')) FakeWebSocketConnection().emitIncoming('{"t":"queued"}');
              },
          ),
          messageTimeout: const Duration(milliseconds: 20),
        ).run(),

        // 2. 401 hatası
        ServerConnectionTest(
          healthChecker: FakeHttpHealthChecker(responseToReturn: 'ok'),
          tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
          wsConnector: FakeWebSocketConnector(
            errorToThrow: const WebSocketException('HttpException: 401 with token=$sensitiveToken'),
          ),
        ).run(),

        // 3. Socket / Ağ hatası
        ServerConnectionTest(
          healthChecker: FakeHttpHealthChecker(
            errorToThrow: const SocketException('Connection to https://server.workers.dev?token=xxx refused'),
          ),
          tokenProvider: FakeAuthTokenProvider(token: sensitiveToken),
        ).run(),
      ];

      for (final futureReport in scenarios) {
        final report = await futureReport;

        // failureMessage kontrolü
        if (report.failureMessage != null) {
          expect(report.failureMessage, isNot(contains(sensitiveToken)));
          expect(report.failureMessage, isNot(contains('?token=')));
        }

        // Tüm aşama sonuçlarının kontrolü
        for (final step in report.steps) {
          expect(step.stepName, isNot(contains(sensitiveToken)));
          expect(step.stepName, isNot(contains('?token=')));
          if (step.errorMessage != null) {
            expect(step.errorMessage, isNot(contains(sensitiveToken)));
            expect(step.errorMessage, isNot(contains('?token=')));
            expect(step.errorMessage, isNot(contains('Bearer')));
          }
          expect(step.toString(), isNot(contains(sensitiveToken)));
          expect(step.toString(), isNot(contains('?token=')));
        }
      }
    });
  });
}

