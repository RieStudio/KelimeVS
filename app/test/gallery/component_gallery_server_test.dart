@Timeout(Duration(seconds: 30))
library;

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/application/server_connection_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/http_health_checker.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/gallery/component_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerTestDebugWidget (UI)', () {
    testWidgets(
      'başarılı test senaryosunda aşamaları ve başarı özetini ekranda gösterir',
      (tester) async {
        final fakeConn = FakeWebSocketConnection();
        fakeConn.onSend = (msg) {
          if (msg.contains('"queue"')) {
            fakeConn.emitIncoming('{"t":"queued"}');
          } else if (msg.contains('"cancel"')) {
            fakeConn.emitIncoming('{"t":"cancelled"}');
          }
        };

        final fakeService = ServerConnectionTest(
          healthChecker: FakeHttpHealthChecker(responseToReturn: 'ok'),
          tokenProvider: FakeAuthTokenProvider(token: 'test_token'),
          wsConnector: FakeWebSocketConnector(connectionToReturn: fakeConn),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServerTestDebugWidget(testService: fakeService),
            ),
          ),
        );

        expect(find.text(AppStrings.serverTestButton), findsOneWidget);

        await tester.tap(find.text(AppStrings.serverTestButton));
        await tester.pump();

        // Test tamamlanana kadar bekle
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.textContaining('Sağlık Kontrolü').evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.textContaining('Sağlık Kontrolü (/health): Tamam'), findsOneWidget);
        expect(find.textContaining('Kimlik Jetonu Alma: Tamam'), findsOneWidget);
        expect(find.textContaining('WebSocket Bağlantısı: Tamam'), findsOneWidget);
        expect(find.textContaining('Kuyruğa Girme (queue): Tamam'), findsOneWidget);
        expect(find.textContaining('Kuyruktan Çıkma (cancel): Tamam'), findsOneWidget);
        expect(find.textContaining(AppStrings.serverTestSuccessSummary), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'hata senaryosunda hata mesajını ve başarısız özetini ekranda gösterir',
      (tester) async {
        final fakeService = ServerConnectionTest(
          healthChecker: FakeHttpHealthChecker(responseToReturn: 'server_error'),
          tokenProvider: FakeAuthTokenProvider(token: 'test_token'),
          wsConnector: FakeWebSocketConnector(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServerTestDebugWidget(testService: fakeService),
            ),
          ),
        );

        await tester.tap(find.text(AppStrings.serverTestButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(find.textContaining('Sağlık Kontrolü (/health): HATA'), findsOneWidget);
        expect(find.textContaining(AppStrings.serverTestFailedSummary), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ComponentGallery içinde ServerTestDebugWidget butonunun yer aldığını doğrular',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ComponentGallery(),
            ),
          ),
        );
        await tester.pump();

        expect(find.text(AppStrings.serverTestButton), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
