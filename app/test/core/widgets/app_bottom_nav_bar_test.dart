import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/app_bottom_nav_bar.dart';

void main() {
  const testNavItems = [
    AppNavItem(
      svgAsset: AppBottomNavBar.homeAsset,
      label: AppStrings.navHome,
    ),
    AppNavItem(
      svgAsset: AppBottomNavBar.leaderboardAsset,
      label: AppStrings.navLeaderboard,
    ),
    AppNavItem(
      svgAsset: AppBottomNavBar.storeAsset,
      label: AppStrings.navShop,
    ),
    AppNavItem(
      svgAsset: AppBottomNavBar.profileAsset,
      label: AppStrings.navProfile,
    ),
  ];

  Widget buildNavBar({
    int currentIndex = 0,
    ValueChanged<int>? onTap,
    List<AppNavItem> items = testNavItems,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: currentIndex,
          onTap: onTap ?? (_) {},
          items: items,
        ),
      ),
    );
  }

  group('AppBottomNavBar Widget Tests', () {
    testWidgets('1. Dört sekme ve doğru etiketler ekranda yer alır', (tester) async {
      await tester.pumpWidget(buildNavBar());

      expect(find.text(AppStrings.navHome), findsOneWidget);
      expect(find.text(AppStrings.navLeaderboard), findsOneWidget);
      expect(find.text(AppStrings.navShop), findsOneWidget);
      expect(find.text(AppStrings.navProfile), findsOneWidget);
    });

    testWidgets('2. Her sekme doğru SVG asset yolunu kullanır ve 32px boyutundadır', (
      tester,
    ) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 0));

      final svgWidgets = tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
      expect(svgWidgets.length, 4);

      final expectedAssets = [
        'assets/icons/nav_home.svg',
        'assets/icons/nav_leaderboard.svg',
        'assets/icons/nav_store.svg',
        'assets/icons/nav_profile.svg',
      ];

      for (int i = 0; i < 4; i++) {
        final svg = svgWidgets[i];
        expect(svg.width, AppBottomNavBar.iconSize);
        expect(svg.height, AppBottomNavBar.iconSize);
        expect(svg.bytesLoader, isA<SvgAssetLoader>());
        expect((svg.bytesLoader as SvgAssetLoader).assetName, expectedAssets[i]);
      }
    });

    testWidgets(
      '3. Seçili sekme (index 0) ColorFiltered ile sarılmaz; seçili olmayan sekmeler (index 1, 2, 3) ColorFiltered ile sarılır',
      (tester) async {
        await tester.pumpWidget(buildNavBar(currentIndex: 0));

        // 4 sekmenin GestureDetector widget'larını bul
        final tabFinders = [
          find.ancestor(
            of: find.text(AppStrings.navHome),
            matching: find.byType(GestureDetector),
          ),
          find.ancestor(
            of: find.text(AppStrings.navLeaderboard),
            matching: find.byType(GestureDetector),
          ),
          find.ancestor(
            of: find.text(AppStrings.navShop),
            matching: find.byType(GestureDetector),
          ),
          find.ancestor(
            of: find.text(AppStrings.navProfile),
            matching: find.byType(GestureDetector),
          ),
        ];

        // Seçili sekme: ColorFiltered KESİNLİKLE YOKTUR
        final selectedColorFiltered = find.descendant(
          of: tabFinders[0],
          matching: find.byType(ColorFiltered),
        );
        expect(selectedColorFiltered, findsNothing);

        // Seçili olmayan sekmeler: her biri ColorFiltered içerir
        for (int i = 1; i <= 3; i++) {
          final unselectedColorFiltered = find.descendant(
            of: tabFinders[i],
            matching: find.byType(ColorFiltered),
          );
          expect(unselectedColorFiltered, findsOneWidget);

          final cfWidget = tester.widget<ColorFiltered>(unselectedColorFiltered);
          expect(
            cfWidget.colorFilter,
            const ColorFilter.matrix(AppBottomNavBar.grayscaleMatrix),
          );

          // Opacity widget kontrolü
          final opacityFinder = find.descendant(
            of: tabFinders[i],
            matching: find.byType(Opacity),
          );
          expect(opacityFinder, findsOneWidget);
          final opacityWidget = tester.widget<Opacity>(opacityFinder);
          expect(opacityWidget.opacity, AppBottomNavBar.unselectedOpacity);
        }
      },
    );

    testWidgets(
      '4. Farklı bir sekme seçildiğinde (index 2 - Mağaza) seçili olan sarılmaz, diğerleri sarılır',
      (tester) async {
        await tester.pumpWidget(buildNavBar(currentIndex: 2));

        final homeTab = find.ancestor(
          of: find.text(AppStrings.navHome),
          matching: find.byType(GestureDetector),
        );
        final leaderboardTab = find.ancestor(
          of: find.text(AppStrings.navLeaderboard),
          matching: find.byType(GestureDetector),
        );
        final shopTab = find.ancestor(
          of: find.text(AppStrings.navShop),
          matching: find.byType(GestureDetector),
        );
        final profileTab = find.ancestor(
          of: find.text(AppStrings.navProfile),
          matching: find.byType(GestureDetector),
        );

        // Mağaza seçili: ColorFiltered YOK
        expect(
          find.descendant(of: shopTab, matching: find.byType(ColorFiltered)),
          findsNothing,
        );

        // Ana Sayfa, Sıralama, Profil seçili değil: ColorFiltered VAR
        for (final unselectedTab in [homeTab, leaderboardTab, profileTab]) {
          final cfFinder = find.descendant(
            of: unselectedTab,
            matching: find.byType(ColorFiltered),
          );
          expect(cfFinder, findsOneWidget);
          final cf = tester.widget<ColorFiltered>(cfFinder);
          expect(
            cf.colorFilter,
            const ColorFilter.matrix(AppBottomNavBar.grayscaleMatrix),
          );
        }
      },
    );

    testWidgets('5. Sekmeye tıklandığında onTap callbacki doğru index ile çağrılır', (
      tester,
    ) async {
      int tappedIndex = -1;
      await tester.pumpWidget(
        buildNavBar(
          currentIndex: 0,
          onTap: (index) {
            tappedIndex = index;
          },
        ),
      );

      await tester.tap(find.text(AppStrings.navLeaderboard));
      expect(tappedIndex, 1);

      await tester.tap(find.text(AppStrings.navShop));
      expect(tappedIndex, 2);

      await tester.tap(find.text(AppStrings.navProfile));
      expect(tappedIndex, 3);

      await tester.tap(find.text(AppStrings.navHome));
      expect(tappedIndex, 0);
    });

    testWidgets('6. Semantics özellikleri erişilebilirlik gereksinimlerini karşılar', (
      tester,
    ) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 1));

      final semantics = tester.widgetList<Semantics>(find.byType(Semantics)).where((s) {
        return s.properties.label != null &&
            [
              AppStrings.navHome,
              AppStrings.navLeaderboard,
              AppStrings.navShop,
              AppStrings.navProfile,
            ].contains(s.properties.label);
      }).toList();

      expect(semantics.length, 4);

      // Sıralama (index 1) seçili olmalı
      final selectedSemantics = semantics.firstWhere(
        (s) => s.properties.label == AppStrings.navLeaderboard,
      );
      expect(selectedSemantics.properties.selected, isTrue);
      expect(selectedSemantics.properties.button, isTrue);

      // Diğerleri seçili olmamalı
      final unselectedSemantics = semantics.where(
        (s) => s.properties.label != AppStrings.navLeaderboard,
      );
      for (final s in unselectedSemantics) {
        expect(s.properties.selected, isFalse);
        expect(s.properties.button, isTrue);
      }
    });

    testWidgets('7. Seçili sekme mint zemin (pill), seçili olmayan şeffaf zemin kullanır', (
      tester,
    ) async {
      await tester.pumpWidget(buildNavBar(currentIndex: 0));

      final containers = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      ).toList();

      expect(containers.length, 4);

      final selectedDecoration = containers[0].decoration as BoxDecoration;
      expect(selectedDecoration.color, AppColors.mint);

      for (int i = 1; i < 4; i++) {
        final unselectedDecoration = containers[i].decoration as BoxDecoration;
        expect(unselectedDecoration.color, Colors.transparent);
      }
    });
  });
}
