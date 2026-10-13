import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/data/websocket_connector.dart';

void main() {
  group('OnlineMatchClient - Yaşam Döngüsü ve Yeniden Bağlanma', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    test('Arka plana geçildiğinde (paused/inactive) leave gönderilmez ve bağlantı korunur', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      await client.connect('m_123');
      expect(client.isConnected, isTrue);

      // Arka plana geçiş
      client.handleAppPaused();

      // Leave mesajı gitmemeli, bağlantı açık kalmalı
      expect(
        fakeConnection.sentMessages.any((m) => m.contains('"leave"')),
        isFalse,
      );
      expect(client.isConnected, isTrue);

      await client.dispose();
    });

    test('Bağlantı açıkken öne gelindiğinde (resumed) derhal sync gönderilir', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      await client.connect('m_123');
      fakeConnection.sentMessages.clear();

      client.handleAppPaused();
      await client.handleAppResumed();

      // sync mesajı hemen gönderilmiş olmalı
      expect(
        fakeConnection.sentMessages.any((m) => m.contains('"sync"')),
        isTrue,
      );

      await client.dispose();
    });

    test('Kopma olduğunda OnlineMatchReconnecting yayılır', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 10)],
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      // Yeni bağlantı için soket
      final secondConnection = FakeWebSocketConnection();
      fakeConnector.connectionToReturn = secondConnection;

      // Sunucu bağlantıyı koparır
      fakeConnection.simulateServerClose(1006, 'abnormal');

      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Reconnecting olayı yayılmış olmalı
      expect(events.any((e) => e is OnlineMatchReconnecting), isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test(
      'Bağlantı kopukken öne gelindiğinde (resumed) backoff sayacı sıfırlanır ve derhal bağlanır',
      () async {
        var clockMs = 1000;
        final delaysCalled = <Duration>[];

        final client = OnlineMatchClient(
          connector: fakeConnector,
          tokenProvider: fakeTokenProvider,
          reconnectDelays: [
            const Duration(seconds: 1),
            const Duration(seconds: 2),
            const Duration(seconds: 4),
          ],
          clock: () => clockMs,
          delayFunction: (d) async {
            delaysCalled.add(d);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          },
        );

        final events = <OnlineMatchEvent>[];
        final sub = client.events.listen(events.add);

        await client.connect('m_123');

        // İlk denemeler başarısız olsun
        fakeConnector.errorToThrow = Exception('Ağ hatası');
        fakeConnection.simulateServerClose(1006, 'abnormal');

        // İlk denemenin başarısız olmasını ve backoff beklemesine girmesini bekle
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(client.isReconnecting, isTrue);

        // Şimdi bağlantı düzelmiş olsun
        final successConnection = FakeWebSocketConnection();
        fakeConnector.errorToThrow = null;
        fakeConnector.connectionToReturn = successConnection;

        // Öne gelinir
        await client.handleAppResumed();

        // Beklemeden hemen bağlandı ve sync gönderdi
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events.whereType<OnlineMatchConnected>().length, 2);
        expect(
          successConnection.sentMessages.any((m) => m.contains('"sync"')),
          isTrue,
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'Arka planda geçen süre (örn. 30 sn) 25 sn yerel pencereyi tüketmez, resumed olunca 25 sn sıfırdan başlar',
      () async {
        var clockMs = 1000;

        final client = OnlineMatchClient(
          connector: fakeConnector,
          tokenProvider: fakeTokenProvider,
          maxReconnectDuration: const Duration(seconds: 25),
          clock: () => clockMs,
          delayFunction: (d) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          },
        );

        final events = <OnlineMatchEvent>[];
        final sub = client.events.listen(events.add);

        await client.connect('m_123');

        // Bağlantı başarısız olsun
        fakeConnector.errorToThrow = Exception('Sunucu yok');
        fakeConnection.simulateServerClose(1006, 'abnormal');
        await Future<void>.delayed(const Duration(milliseconds: 15));

        // Arka plana geçilir
        client.handleAppPaused();

        // Simüle edilen zaman 30 saniye ilerler (25 saniyelik normal pencereden fazla!)
        clockMs += 30000;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Arka plandayken kalıcı kopma (permanent) tetiklenmemiş olmalı!
        expect(
          events.any((e) =>
              e is OnlineMatchDisconnected &&
              e.reason == DisconnectReason.permanent),
          isFalse,
        );

        // Öne gelinir: pencere sıfırlanır, sunucu hazır
        final successConnection = FakeWebSocketConnection();
        fakeConnector.errorToThrow = null;
        fakeConnector.connectionToReturn = successConnection;

        await client.handleAppResumed();
        await Future<void>.delayed(const Duration(milliseconds: 25));

        // Başarıyla bağlanmış olmalı, kalıcı kopma olmamalı
        expect(events.whereType<OnlineMatchConnected>().length, 2);
        expect(
          events.any((e) =>
              e is OnlineMatchDisconnected &&
              e.reason == DisconnectReason.permanent),
          isFalse,
        );

        await sub.cancel();
        await client.dispose();
      },
    );
  });
}
