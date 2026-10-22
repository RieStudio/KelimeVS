import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';

void main() {
  group('EnergyDepletedBottomSheet Widget Tests', () {
    testWidgets('başlık, sayaç, 1 Enerji butonu, Botla Oyna ve Vazgeç butonlarını gösterir',
        (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final nextAt = now + (18 * 60 + 40) * 1000;

      final energy = EnergyState(
        enabled: true,
        current: 0,
        max: 5,
        nextEnergyAtMs: nextAt,
        packs: const [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      bool botClicked = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyDepletedBottomSheet(
                energy: energy,
                userCoins: 50,
                serverNowMs: now,
                onPlayWithBot: () {
                  botClicked = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Enerjin bitti'), findsOneWidget);
      expect(find.textContaining('18:40'), findsOneWidget);
      expect(find.text('1 Enerji  ·  20 Jeton'), findsOneWidget);
      expect(find.text('Botla Oyna'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);

      // Botla Oyna butonuna tıklanır
      await tester.tap(find.byKey(const Key('energy_sheet_bot_button')));
      await tester.pumpAndSettle();

      expect(botClicked, isTrue);
    });
  });
}

