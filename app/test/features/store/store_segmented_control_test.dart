import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/widgets/store_segmented_control.dart';

void main() {
  group('StoreSegmentedControl Widget Tests', () {
    testWidgets('1. 3 bölümlü mod: tüm sekmeler eşit genişlikte ve min 48 dp yükseklikte render edilir', (tester) async {
      StoreTab selected = StoreTab.frames;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StoreSegmentedControl(
                  availableTabs: const [
                    StoreTab.coins,
                    StoreTab.energy,
                    StoreTab.frames,
                  ],
                  selectedTab: selected,
                  onTabSelected: (tab) => selected = tab,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final coinsFinder = find.text('Jeton');
      final energyFinder = find.text('Enerji');
      final framesFinder = find.text('Çerçeve');

      expect(coinsFinder, findsOneWidget);
      expect(energyFinder, findsOneWidget);
      expect(framesFinder, findsOneWidget);

      final controlFinder = find.byType(StoreSegmentedControl);
      expect(controlFinder, findsOneWidget);
      final controlSize = tester.getSize(controlFinder);
      expect(controlSize.height, greaterThanOrEqualTo(48.0));
      expect(controlSize.width, 320.0);

      // Kart köşe yarıçapı ve kenarlık dili
      final container = tester.widget<Container>(
        find.descendant(
          of: controlFinder,
          matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
        ).first,
      );
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, AppColors.card);
      expect(deco.borderRadius, AppDimens.borderRadiusListCard);
      expect((deco.border as Border).top.color, AppColors.ink);
      expect((deco.border as Border).top.width, AppDimens.borderThin);

      // 3 bölümün eşit genişlikte olduğunu doğrula
      final coinsTapFinder = find.byKey(const ValueKey(StoreTab.coins));
      final energyTapFinder = find.byKey(const ValueKey(StoreTab.energy));
      final framesTapFinder = find.byKey(const ValueKey(StoreTab.frames));

      final coinsWidth = tester.getSize(coinsTapFinder).width;
      final energyWidth = tester.getSize(energyTapFinder).width;
      final framesWidth = tester.getSize(framesTapFinder).width;

      expect(coinsWidth, equals(energyWidth));
      expect(energyWidth, equals(framesWidth));
      // Toplam iç alan = 320 - (2px kenarlık * 2 + 2px iç padding * 2) = 312 -> 312 / 3 = 104
      expect(coinsWidth, closeTo(104.0, 0.5));
    });

    testWidgets('2. 2 bölümlü mod (enerji gizli): 2 bölüm %50-%50 eşit genişliktedir', (tester) async {
      StoreTab selected = StoreTab.frames;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StoreSegmentedControl(
                  availableTabs: const [
                    StoreTab.coins,
                    StoreTab.frames,
                  ],
                  selectedTab: selected,
                  onTabSelected: (tab) => selected = tab,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jeton'), findsOneWidget);
      expect(find.text('Enerji'), findsNothing);
      expect(find.text('Çerçeve'), findsOneWidget);

      final coinsTapFinder = find.byKey(const ValueKey(StoreTab.coins));
      final framesTapFinder = find.byKey(const ValueKey(StoreTab.frames));

      final coinsWidth = tester.getSize(coinsTapFinder).width;
      final framesWidth = tester.getSize(framesTapFinder).width;

      expect(coinsWidth, equals(framesWidth));
      // Toplam iç alan = 312 -> 312 / 2 = 156
      expect(coinsWidth, closeTo(156.0, 0.5));
    });

    testWidgets('3. Dokunma ve animasyonlu seçim geçişi: onTabSelected çağrılır ve kayma gerçekleşir', (tester) async {
      StoreTab selected = StoreTab.coins;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: StoreSegmentedControl(
                      availableTabs: const [
                        StoreTab.coins,
                        StoreTab.energy,
                        StoreTab.frames,
                      ],
                      selectedTab: selected,
                      onTabSelected: (tab) {
                        setState(() => selected = tab);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Başlangıç: coins (sol başta)
      final indicatorFinder = find.byType(AnimatedPositioned);
      expect(indicatorFinder, findsOneWidget);
      AnimatedPositioned indicator = tester.widget<AnimatedPositioned>(indicatorFinder);
      expect(indicator.left, closeTo(0.0, 0.5));

      // Enerji sekmesine tıkla
      await tester.tap(find.text('Enerji'));
      await tester.pump(); // animasyon başladı
      await tester.pump(const Duration(milliseconds: 90)); // yarı zaman
      await tester.pumpAndSettle(); // animasyon tamamlandı (180 ms)

      indicator = tester.widget<AnimatedPositioned>(indicatorFinder);
      expect(indicator.left, closeTo(104.0, 0.5));
      expect(selected, StoreTab.energy);
    });

    testWidgets('4. Erişilebilirlik: Semantics seçili durumu (selected) doğru yansıtır', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StoreSegmentedControl(
                  availableTabs: const [
                    StoreTab.coins,
                    StoreTab.energy,
                    StoreTab.frames,
                  ],
                  selectedTab: StoreTab.energy,
                  onTabSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final coinsSemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.byKey(const ValueKey(StoreTab.coins)),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(coinsSemantics.properties.selected, isFalse);

      final energySemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.byKey(const ValueKey(StoreTab.energy)),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(energySemantics.properties.selected, isTrue);

      final framesSemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.byKey(const ValueKey(StoreTab.frames)),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(framesSemantics.properties.selected, isFalse);
    });

    testWidgets('5. 320 dp dar ekran ve textScale 1.5 altında sıfır taşma ile çizilir', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280, // 320 - 40 ekran yan boşluğu
                  child: StoreSegmentedControl(
                    availableTabs: [
                      StoreTab.coins,
                      StoreTab.energy,
                      StoreTab.frames,
                    ],
                    selectedTab: StoreTab.energy,
                    onTabSelected: _emptyTabCallback,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Jeton'), findsOneWidget);
      expect(find.text('Enerji'), findsOneWidget);
      expect(find.text('Çerçeve'), findsOneWidget);
    });
  });
}

void _emptyTabCallback(StoreTab _) {}

