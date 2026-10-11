@Timeout(Duration(seconds: 30))
library;

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/application/network_diagnostics.dart';
import 'package:app/gallery/component_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkDiagnosticsDebugWidget (UI)', () {
    testWidgets(
      'başarılı tanılama senaryosunda sonuçları ekranda listeler',
      (tester) async {
        final fakeService = NetworkDiagnostics(
          targets: const [
            'https://www.google.com/generate_204',
            'https://server.riestudio.workers.dev/health',
          ],
          probeFunction: (url, timeout) async {
            if (url.contains('generate_204')) {
              return DiagnosticTargetResult(
                url: url,
                isSuccess: true,
                statusCode: 204,
                durationMs: 35,
                ipv4Count: 1,
                ipv6Count: 1,
              );
            }
            return DiagnosticTargetResult(
              url: url,
              isSuccess: false,
              durationMs: 267,
              errorType: 'SocketException',
              osErrorCode: 104,
              ipv4Count: 2,
              ipv6Count: 2,
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NetworkDiagnosticsDebugWidget(
                diagnosticsService: fakeService,
              ),
            ),
          ),
        );

        expect(find.text(AppStrings.networkDiagnosticsButton), findsOneWidget);

        await tester.tap(find.text(AppStrings.networkDiagnosticsButton));
        await tester.pump();

        // Sonuçlar ekrana gelene kadar bekle
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text(AppStrings.networkDiagnosticsTitle).evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.text(AppStrings.networkDiagnosticsTitle), findsOneWidget);
        expect(
          find.textContaining('https://www.google.com/generate_204'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Tamam (HTTP 204)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('https://server.riestudio.workers.dev/health'),
          findsOneWidget,
        );
        expect(
          find.textContaining('HATA (SocketException, errno 104)'),
          findsOneWidget,
        );
        expect(find.textContaining('Toplam süre:'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ComponentGallery içinde NetworkDiagnosticsDebugWidget butonunun yer aldığını doğrular',
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

        expect(find.text(AppStrings.networkDiagnosticsButton), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

