import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/energy_icon.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';

void main() {
  group('EnergyDepletedBottomSheet Widget Tests', () {
    testWidgets(
        'başlık, sayaç kartı, 1 Enerji butonu ve Vazgeç butonunu gösterir; açıklama metni ve Botla Oyna butonu bulunmaz',
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

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyDepletedBottomSheet(
                energy: energy,
                userCoins: 50,
                serverNowMs: now,
              ),
            ),
          ),
        ),
      );

      // Kalan / beklenen öğeler
      expect(find.text('Enerjin bitti'), findsOneWidget);
      expect(find.textContaining('18:40'), findsOneWidget);
      expect(find.text('1 Enerji  ·  20 Jeton'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.byKey(const Key('energy_sheet_buy_button')), findsOneWidget);
      expect(find.byKey(const Key('energy_sheet_cancel_button')), findsOneWidget);
      expect(find.byType(EnergyIcon), findsNWidgets(2));

      // Kaldırılan öğeler (açıklama metni ve Botla Oyna butonu)
      expect(
        find.text('Sıralı online maç oynamak için en az 1 enerjiye ihtiyacın var.'),
        findsNothing,
      );
      expect(find.text('Botla Oyna'), findsNothing);
      expect(find.byKey(const Key('energy_sheet_bot_button')), findsNothing);

      // Sayaç kartının arka plan renginin kaldırıldığı (şeffaf/dolgusuz zemin) doğrulanır
      final countdownRowFinder = find.ancestor(
        of: find.textContaining('18:40'),
        matching: find.byType(Container),
      );
      final containerWidget = tester.widget<Container>(countdownRowFinder.first);
      final decoration = containerWidget.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.color, isNull); // Dolgusuz / şeffaf zemin
      expect(decoration.border, isNotNull); // Kenarlık korunur
      expect(decoration.border!.top.color, AppColors.mint);
    });
  });
}

