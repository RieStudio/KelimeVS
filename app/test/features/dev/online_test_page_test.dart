import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/dev/online_test_page.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/matchmaking_client.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/gallery/component_gallery.dart';

void main() {
  group('OnlineTestPage UI', () {
    late FakeWebSocketConnection fakeMatchmakingConnection;
    late FakeWebSocketConnector fakeMatchmakingConnector;
    late FakeWebSocketConnection fakeMatchConnection;
    late FakeWebSocketConnector fakeMatchConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeMatchmakingConnection = FakeWebSocketConnection();
      fakeMatchmakingConnector = FakeWebSocketConnector(
        connectionToReturn: fakeMatchmakingConnection,
      );

      fakeMatchConnection = FakeWebSocketConnection();
      fakeMatchConnector = FakeWebSocketConnector(
        connectionToReturn: fakeMatchConnection,
      );

      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    testWidgets(
      'OnlineTestPage ilk yüklendiğinde gerekli kontrolleri gösterir ve kuyruk akışını işletir',
      (tester) async {
        final mmClient = MatchmakingClient(
          connector: fakeMatchmakingConnector,
          tokenProvider: fakeTokenProvider,
        );
        final matchClient = OnlineMatchClient(
          connector: fakeMatchConnector,
          tokenProvider: fakeTokenProvider,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: OnlineTestPage(
              matchmakingClient: mmClient,
              matchClient: matchClient,
            ),
          ),
        );

        // İlk kontroller
        expect(find.text('Online Test (Protokol v1)'), findsOneWidget);
        expect(find.text('Kuyruğa gir'), findsOneWidget);
        expect(find.text('İptal'), findsOneWidget);
        expect(find.text('Test'), findsOneWidget); // Varsayılan oyuncu adı

        // Kuyruğa gir butonuna tıkla
        await tester.tap(find.text('Kuyruğa gir'));
        await tester.pump(const Duration(milliseconds: 50));

        // Sunucudan matched simüle et
        fakeMatchmakingConnection.emitIncoming('{"t":"queued"}');
        await tester.pump(const Duration(milliseconds: 50));

        fakeMatchmakingConnection.emitIncoming(
          '{"t":"matched","matchId":"m_live123","opponentName":"Ayşe"}',
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Canlı maç kontrolleri görünmeli
        expect(find.text('Maç ID: m_live123 | Rakip: Ayşe'), findsOneWidget);
        expect(find.text('Gönder'), findsOneWidget);
        expect(find.text('Maçtan çık'), findsOneWidget);

        // Cevap gir ve gönder
        await tester.enterText(find.byType(TextField).last, 'ankara');
        await tester.tap(find.text('Gönder'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          fakeMatchConnection.sentMessages.any((m) => m.contains('"ankara"')),
          isTrue,
        );

        // Maçtan çık butonuna tıkla
        await tester.tap(find.text('Maçtan çık'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          fakeMatchConnection.sentMessages.any((m) => m.contains('"leave"')),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'ComponentGallery içinde Online test butonu yer alır ve sayfayı açar',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: ComponentGallery(),
          ),
        );

        // Sayfayı aşağı kaydırarak butonu görünür kıl
        final onlineTestBtn = find.text('Online test');
        await tester.scrollUntilVisible(
          onlineTestBtn,
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(onlineTestBtn, findsOneWidget);

        await tester.tap(onlineTestBtn);
        await tester.pumpAndSettle();

        expect(find.byType(OnlineTestPage), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
