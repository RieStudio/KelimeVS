import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/widgets/coin_pill.dart';
import 'package:app/core/widgets/energy_icon.dart';
import 'package:app/core/widgets/energy_pill.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import 'package:app/features/store/presentation/widgets/energy_tab_view.dart';

void main() {
  group('EnergyIcon Widget Tests', () {
    testWidgets('1. Varsayılan parametrelerle SVG doğru yoldan ve 24dp çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnergyIcon(),
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
        (w) => w is EnergyIcon && EnergyIcon.assetPath == 'assets/icons/energy_badge.svg',
      );
      expect(assetFinder, findsOneWidget);
    });

    testWidgets('2. Özel boyut doğru şekilde uygulanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnergyIcon(size: 48.0),
          ),
        ),
      );

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 48.0);
      expect(svg.height, 48.0);
    });

    testWidgets('3. Opacity < 1.0 olduğunda Opacity widgetı ile sarmalanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnergyIcon(size: 32.0, opacity: 0.25),
          ),
        ),
      );

      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, 0.25);
    });

    testWidgets('4. Erişilebilirlik: Varsayılan Semantics etiketi "Enerji"dir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnergyIcon(),
          ),
        ),
      );

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Enerji',
      );
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('5. Özel anlamsal etiket uygulanabilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnergyIcon(semanticLabel: 'Kalan Enerji'),
          ),
        ),
      );

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Kalan Enerji',
      );
      expect(semanticsFinder, findsOneWidget);
    });
  });

  group('Eski İkonların Kullanılmadığının Doğrulanması (Audit Tests)', () {
    testWidgets('6. CoinPill içinde AppIcons.bolt veya Icons.bolt kullanılmaz, EnergyIcon kullanılır', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoinPill(
              amount: 100,
              energyCurrent: 4,
              energyMax: 5,
              onEnergyTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(EnergyIcon), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.bolt),
        findsNothing,
      );
    });

    testWidgets('7. EnergyPill içinde AppIcons.bolt veya Icons.bolt kullanılmaz, EnergyIcon kullanılır', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnergyPill(
              current: 3,
              max: 5,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(EnergyIcon), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.bolt),
        findsNothing,
      );
    });

    testWidgets('8. EnergyDepletedBottomSheet içinde AppIcons.bolt veya Icons.bolt kullanılmaz, EnergyIcon kullanılır', (tester) async {
      const energyState = EnergyState(
        enabled: true,
        current: 0,
        max: 5,
        regenSeconds: 1200,
        nextEnergyAtMs: 1000000,
        packs: [],
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyDepletedBottomSheet(
                energy: energyState,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      // Hem üstteki hero rozeti (64dp) hem sayaç kutusu (26dp) EnergyIcon kullanır
      expect(find.byType(EnergyIcon), findsNWidgets(2));
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.bolt),
        findsNothing,
      );
    });

    testWidgets('9. EnergyTabView içinde AppIcons.bolt veya Icons.bolt kullanılmaz, EnergyIcon kullanılır', (tester) async {
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
          EnergyPack(
            id: 'pack_full',
            energy: 5,
            cost: 200,
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

      // Sayaç kartında 5 yuva (3 dolu + 2 boş) + 2 paket kartı = 7 EnergyIcon
      expect(find.byType(EnergyIcon), findsNWidgets(7));
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.bolt),
        findsNothing,
      );
    });
  });
}
