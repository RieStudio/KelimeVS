import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/coin_pill.dart';

void main() {
  group('CoinPill Widget Tests', () {
    testWidgets('1. Tekil mod (energyCurrent == null): sadece jeton bölümü çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoinPill(amount: 500),
            ),
          ),
        ),
      );

      expect(find.text('500'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.byKey(const Key('energy_pill_button')), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsNothing,
      );
    });

    testWidgets('2. Birleşik mod (energyCurrent != null): jeton, ayırıcı ve enerji bölümü birlikte çizilir', (tester) async {
      bool energyTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoinPill(
                amount: 1250,
                energyCurrent: 5,
                energyMax: 5,
                onEnergyTap: () => energyTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('1250'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.bolt),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppColors.mint),
        findsOneWidget,
      );

      // Enerjiye dokunma testi
      await tester.tap(find.byKey(const Key('energy_pill_button')));
      await tester.pump();
      expect(energyTapped, isTrue);
    });

    testWidgets('3. 5-6 haneli jeton miktarında ve dar alanda FittedBox ile taşma yapmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 170,
                child: CoinPill(
                  amount: 999999,
                  energyCurrent: 5,
                  energyMax: 5,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('999999'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('4. textScaler 1.5 altında taşma yapmadan çizilir', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: CoinPill(
                  amount: 88888,
                  energyCurrent: 3,
                  energyMax: 5,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('88888'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('5. Erişilebilirlik: Semantics etiketleri doğru atanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoinPill(
                amount: 75,
                energyCurrent: 2,
                energyMax: 5,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '75${AppStrings.coinSuffix}',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '2 / 5 Enerji',
        ),
        findsOneWidget,
      );
    });
  });
}
