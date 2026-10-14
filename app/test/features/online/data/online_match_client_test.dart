import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/data/websocket_connector.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';

void main() {
  group('OnlineMatchClient', () {
    late FakeWebSocketConnection fakeConnection;
    late FakeWebSocketConnector fakeConnector;
    late FakeAuthTokenProvider fakeTokenProvider;

    setUp(() {
      fakeConnection = FakeWebSocketConnection();
      fakeConnector = FakeWebSocketConnector(connectionToReturn: fakeConnection);
      fakeTokenProvider = FakeAuthTokenProvider(token: 'valid_token');
    });

    test('durum akışı (state, feedback, final, voided) olayları yayar', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      expect(events.length, 1);
      expect(events[0], isA<OnlineMatchConnected>());

      // 1. State mesajı
      fakeConnection.emitIncoming(
        '{"t":"state","serverNowMs":1000,"phase":"roundActive","roundNumber":1,"scores":{"me":0,"opponent":0},"question":{"id":"q1","text":"Test?"},"turnIsMine":true,"deadlineMs":15000,"myHintsLeft":1,"attempts":[],"opponentName":"Rakip","opponentConnected":true}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 2);
      expect(events[1], isA<OnlineMatchStateUpdate>());
      final stateUpdate = events[1] as OnlineMatchStateUpdate;
      expect(stateUpdate.state.phase, OnlineMatchPhase.roundActive);
      expect(stateUpdate.state.turnIsMine, isTrue);

      // 2. Feedback mesajı
      fakeConnection.emitIncoming('{"t":"feedback","kind":"wrong","reason":"not_your_turn"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 3);
      expect(events[2], isA<OnlineMatchFeedback>());
      final fb = events[2] as OnlineMatchFeedback;
      expect(fb.kind, 'wrong');
      expect(fb.reason, 'not_your_turn');

      // 3. Final mesajı
      fakeConnection.emitIncoming(
        '{"t":"final","rounds":[],"scores":{"me":2,"opponent":1},"winnerIsMe":true,"endedBy":"normal"}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 4);
      expect(events[3], isA<OnlineMatchFinal>());
      final fin = events[3] as OnlineMatchFinal;
      expect(fin.result.winnerIsMe, isTrue);

      // 4. Voided mesajı
      fakeConnection.emitIncoming('{"t":"voided","reason":"opponent_absent"}');
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 5);
      expect(events[4], isA<OnlineMatchVoided>());
      final voided = events[4] as OnlineMatchVoided;
      expect(voided.reason, 'opponent_absent');

      await sub.cancel();
      await client.dispose();
    });

    test('submit hız sınırı (cooldown) erken çağrıları yok sayar', () async {
      var simulatedTimeMs = 10000;
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        cooldownDuration: const Duration(milliseconds: 600),
        clock: () => simulatedTimeMs,
      );

      await client.connect('m_123');

      // 1. İlk gönderim başarılı
      final res1 = client.submit('ankara');
      expect(res1, isTrue);
      expect(fakeConnection.sentMessages.length, 1);
      expect(fakeConnection.sentMessages[0], contains('"ankara"'));

      // 2. 300 ms sonra gönderim (600 ms dolmadı) -> false döner, mesaj gitmez
      simulatedTimeMs += 300;
      final res2 = client.submit('izmir');
      expect(res2, isFalse);
      expect(fakeConnection.sentMessages.length, 1);

      // 3. 650 ms sonra gönderim (toplam 950 ms) -> başarılı
      simulatedTimeMs += 350;
      final res3 = client.submit('istanbul');
      expect(res3, isTrue);
      expect(fakeConnection.sentMessages.length, 2);
      expect(fakeConnection.sentMessages[1], contains('"istanbul"'));

      // 4. Boş metin gönderilmez
      simulatedTimeMs += 700;
      final resEmpty = client.submit('   ');
      expect(resEmpty, isFalse);
      expect(fakeConnection.sentMessages.length, 2);

      await client.dispose();
    });

    test('bağlantı koparsa otomatik yeniden bağlanır ve sync gönderir', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 10)],
        maxReconnectDuration: const Duration(seconds: 5),
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');
      expect(events.length, 1);
      expect(events[0], isA<OnlineMatchConnected>());

      // Yeni bağlantı için yeni sahte socket hazırla
      final secondConnection = FakeWebSocketConnection();
      fakeConnector.connectionToReturn = secondConnection;

      // İlk bağlantıyı sunucu kopardı
      fakeConnection.simulateServerClose(1006, 'abnormal_closure');

      // Yeniden bağlanmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.length, 3);
      expect(events[1], isA<OnlineMatchReconnecting>());
      expect(events[2], isA<OnlineMatchConnected>());

      // Yeniden bağlanınca "sync" mesajı gitmeli
      expect(
        secondConnection.sentMessages.any((msg) => msg.contains('"sync"')),
        isTrue,
      );

      await sub.cancel();
      await client.dispose();
    });

    test('25 sn yeniden bağlanma süresi dolunca permanent kopma yayılır', () async {
      var simulatedTimeMs = 1000;
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 5)],
        maxReconnectDuration: const Duration(milliseconds: 30),
        clock: () => simulatedTimeMs,
        delayFunction: (d) async {
          simulatedTimeMs += 15;
          await Future<void>.delayed(Duration.zero);
        },
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      // Sonraki tüm bağlantı denemeleri başarısız olsun
      fakeConnector.errorToThrow = Exception('Sunucuya ulaşılamıyor');

      // İlk bağlantıyı kapat
      fakeConnection.simulateServerClose(1006, 'abnormal');

      // Reconnect döngüsünün 30 ms limitine ulaşmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        events.any((e) =>
            e is OnlineMatchDisconnected &&
            e.reason == DisconnectReason.permanent),
        isTrue,
      );

      await sub.cancel();
      await client.dispose();
    });

    test('sunucu 4000 (replaced) koduyla kapattığında yeniden bağlanmaz', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 5)],
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      // Kod 4000 ile kapatıldı (aynı hesap başka yerden bağlandı)
      fakeConnection.simulateServerClose(4000, 'replaced');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        events.any((e) =>
            e is OnlineMatchDisconnected &&
            e.reason == DisconnectReason.replaced),
        isTrue,
      );

      // Yeniden bağlanma tetiklenmemeli
      expect(events.whereType<OnlineMatchConnected>().length, 1);

      await sub.cancel();
      await client.dispose();
    });

    test('dışarıdan close() çağrılınca yeniden bağlanmaz', () async {
      final client = OnlineMatchClient(
        connector: fakeConnector,
        tokenProvider: fakeTokenProvider,
        reconnectDelays: [const Duration(milliseconds: 5)],
      );

      final events = <OnlineMatchEvent>[];
      final sub = client.events.listen(events.add);

      await client.connect('m_123');

      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        events.any((e) =>
            e is OnlineMatchDisconnected &&
            e.reason == DisconnectReason.closed),
        isTrue,
      );

      // Yeniden bağlanma tetiklenmemeli
      expect(events.whereType<OnlineMatchConnected>().length, 1);

      await sub.cancel();
      await client.dispose();
    });

    test('defaultMaxReconnectDuration 35 saniyedir (sunucunun 30 sn zaman aşımından 5 sn uzun)', () {
      expect(
        OnlineMatchClient.defaultMaxReconnectDuration,
        const Duration(seconds: 35),
      );
    });
  });
}
