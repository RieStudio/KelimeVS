import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_tab_view.dart';

void main() {
  group('EnergyTabView Widget Tests', () {
    testWidgets('3/5 enerji durumunu, hücreleri ve canlı mm:ss sayacını gösterir',
        (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 14 dakika 25 saniye sonrası
      final nextAt = now + (14 * 60 + 25) * 1000;

      final energy = EnergyState(
        enabled: true,
        current: 3,
        max: 5,
        nextEnergyAtMs: nextAt,
        packs: const [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
                serverNowMs: now,
              ),
            ),
          ),
        ),
      );

      expect(find.text('3 / 5'), findsOneWidget);
      // mm:ss formatında (14:25) geri sayım metni aranır
      expect(find.textContaining('14:25'), findsOneWidget);

      // Paket kartları
      expect(find.text('+1 Enerji'), findsOneWidget);
      expect(find.text('Tam Doldur'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text(AppStrings.energyRegenInfo), findsOneWidget);
    });

    testWidgets('tam enerji (5/5) durumunda "Tüm enerjin doldu" ve "Enerjin dolu" yazar',
        (tester) async {
      final energy = const EnergyState(
        enabled: true,
        current: 5,
        max: 5,
        nextEnergyAtMs: null,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('Tüm enerjin doldu'), findsOneWidget);
      expect(find.text('Enerjin dolu'), findsNWidgets(2));
      expect(find.text(AppStrings.energyRegenInfo), findsNothing);
    });
  });
}
