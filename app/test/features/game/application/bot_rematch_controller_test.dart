import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/application/bot_rematch_controller.dart';
import 'package:app/features/online/domain/models/rematch_state.dart';

class ControlledRandom implements math.Random {
  final double doubleVal;
  final int intVal;

  ControlledRandom({this.doubleVal = 0.5, this.intVal = 2});

  @override
  double nextDouble() => doubleVal;

  @override
  int nextInt(int max) => intVal.clamp(0, max - 1);

  @override
  bool nextBool() => true;
}

void main() {
  group('BotRematchController Tests', () {
    test('1. Normal bitişte durum idle, anormal bitişte unavailable başlar', () {
      final normalCtrl = BotRematchController(isNormalEnd: true);
      expect(normalCtrl.state, equals(RematchState.idle));
      expect(normalCtrl.state.canOffer, isTrue);

      final nonNormalCtrl = BotRematchController(isNormalEnd: false);
      expect(nonNormalCtrl.state, equals(RematchState.unavailable));
      expect(nonNormalCtrl.state.canOffer, isFalse);
    });

    testWidgets('2. Bot %85 ihtimalle 5-10 sn arasında teklifi reddeder (declined)', (tester) async {
      // doubleVal = 0.5 (< 0.85), intVal = 2 -> 5 + 2 = 7 saniye gecikme
      final rand = ControlledRandom(doubleVal: 0.5, intVal: 2);
      final controller = BotRematchController(isNormalEnd: true, random: rand);
      addTearDown(controller.dispose);

      final states = <RematchState>[];
      controller.addListener(() => states.add(controller.state));

      final ok = controller.offerRematch();
      expect(ok, isTrue);
      expect(controller.state, isA<RematchPendingSent>());
      expect((controller.state as RematchPendingSent).secondsRemaining, 45);

      // 6 saniye ilerlet (henüz 7 saniye dolmadı)
      await tester.pump(const Duration(seconds: 6));
      expect(controller.state, isA<RematchPendingSent>());
      expect((controller.state as RematchPendingSent).secondsRemaining, 39);

      // 1 saniye daha ilerlet (toplam 7 saniye) -> bot reddetti
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state, equals(RematchState.declined));
      expect(controller.state.isTerminal, isTrue);
    });

    testWidgets('3. Sessiz bot (%15 ihtimalle) 45 sn sonra expired durumuna geçer', (tester) async {
      // doubleVal = 0.90 (>= 0.85) -> sessiz bot
      final rand = ControlledRandom(doubleVal: 0.90);
      final controller = BotRematchController(isNormalEnd: true, random: rand);
      addTearDown(controller.dispose);

      controller.offerRematch();
      expect(controller.state, isA<RematchPendingSent>());

      // 10 saniye sonra hala pendingSent
      await tester.pump(const Duration(seconds: 10));
      expect(controller.state, isA<RematchPendingSent>());
      expect((controller.state as RematchPendingSent).secondsRemaining, 35);

      // 35 saniye daha ilerlet (toplam 45 saniye)
      await tester.pump(const Duration(seconds: 35));
      expect(controller.state, equals(RematchState.expired));
      expect(controller.state.isTerminal, isTrue);
    });

    testWidgets('4. Dispose çağrıldığında zamanlayıcılar iptal edilir ve hata oluşmaz', (tester) async {
      final rand = ControlledRandom(doubleVal: 0.5, intVal: 4);
      final controller = BotRematchController(isNormalEnd: true, random: rand);

      controller.offerRematch();
      expect(controller.state, isA<RematchPendingSent>());

      // 2 saniye sonra ekran kapandı (dispose)
      await tester.pump(const Duration(seconds: 2));
      controller.dispose();

      // Süre ilerletildiğinde hiçbir dinleyici tetiklenmez veya hata vermez
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
