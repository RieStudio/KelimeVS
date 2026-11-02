import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/widgets/coin_icon.dart';
import 'package:app/core/widgets/coin_pill.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/widgets/coins_tab_view.dart';
import 'package:app/features/store/presentation/widgets/energy_tab_view.dart';
import 'package:app/features/store/presentation/widgets/purchase_bottom_sheet.dart';
import 'package:app/features/store/presentation/widgets/store_frame_card.dart';

void main() {
  group('CoinIcon Widget Tests', () {
    testWidgets('1. Varsayılan parametrelerle SVG doğru yoldan ve 24dp çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(),
          ),
        ),
      );

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);

      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, 24.0);
      expect(svg.height, 24.0);
      expect(svg.fit, BoxFit.contain);
      expect(svg.clipBehavior, Clip.none);

      final assetFinder = find.byWidgetPredicate(
        (w) => w is CoinIcon && CoinIcon.assetPath == 'assets/icons/coin.svg',
      );
      expect(assetFinder, findsOneWidget);
    });

    testWidgets('2. Özel boyut doğru şekilde uygulanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(size: 72.0),
          ),
        ),
      );

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 72.0);
      expect(svg.height, 72.0);
    });

    testWidgets('3. Opacity < 1.0 olduğunda Opacity widgetı ile sarmalanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(size: 32.0, opacity: 0.5),
          ),
        ),
      );

      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.5);
    });

    testWidgets('4. Opacity == 1.0 olduğunda fazladan Opacity widgetı eklenmez', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(size: 32.0, opacity: 1.0),
          ),
        ),
      );

      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('5. Erişilebilirlik: Varsayılan Semantics etiketi "Jeton"dur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(),
          ),
        ),
      );

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Jeton',
      );
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('6. Özel anlamsal etiket uygulanabilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinIcon(semanticLabel: 'Jeton Bakiyesi'),
          ),
        ),
      );

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Jeton Bakiyesi',
      );
      expect(semanticsFinder, findsOneWidget);
    });
  });

  group('Eski Jeton İkonu Kullanılmadığının Doğrulanması (Audit Tests)', () {
    testWidgets('7. CoinPill içinde CoinIcon kullanılır, eski harf Container ikonu kullanılmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinPill(amount: 500),
          ),
        ),
      );

      expect(find.byType(CoinIcon), findsOneWidget);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('8. CoinsTabView içinde CoinIcon(size: 72) kullanılır, eski Container ikonu kullanılmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoinsTabView(),
          ),
        ),
      );

      final iconFinder = find.byType(CoinIcon);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<CoinIcon>(iconFinder);
      expect(icon.size, 72.0);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('9. EnergyTabView içinde paket satın alma butonunda CoinIcon(size: 18) kullanılır', (tester) async {
      const energyState = EnergyState(
        enabled: true,
        current: 3,
        max: 5,
        regenSeconds: 1200,
        packs: [
          EnergyPack(
            id: 'pack_1',
            energy: 1,
            cost: 50,
          ),
        ],
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energyState,
                userCoins: 500,
              ),
            ),
          ),
        ),
      );

      final iconFinder = find.byType(CoinIcon);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<CoinIcon>(iconFinder);
      expect(icon.size, 18.0);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('10. PurchaseBottomSheet içinde CoinIcon(size: 24) kullanılır', (tester) async {
      const testItem = StoreItem(
        id: 'frame_gold',
        name: 'Altın Çerçeve',
        price: 250,
        owned: false,
        isEquipped: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PurchaseBottomSheet(
              item: testItem,
              userCoins: 500,
              playerName: 'Ahmet',
            ),
          ),
        ),
      );

      final iconFinder = find.byType(CoinIcon);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<CoinIcon>(iconFinder);
      expect(icon.size, 24.0);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('11. StoreFrameCard içinde CoinIcon(size: 18) kullanılır', (tester) async {
      const testItem = StoreItem(
        id: 'frame_gold',
        name: 'Altın Çerçeve',
        price: 250,
        owned: false,
        isEquipped: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoreFrameCard(
              item: testItem,
              userCoins: 500,
              playerName: 'Ahmet',
            ),
          ),
        ),
      );

      final iconFinder = find.byType(CoinIcon);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<CoinIcon>(iconFinder);
      expect(icon.size, 18.0);
      expect(find.text('G'), findsNothing);
    });
  });
}
