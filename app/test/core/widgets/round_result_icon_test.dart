import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/round_result_icon.dart';

void main() {
  group('RoundResultIcon Widget Tests', () {
    testWidgets('1. Kazandın varyantı (win) round_win.svg çizer ve Clip.none kullanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoundResultIcon.win(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, AppDimens.avatarEnd);
      expect(svg.height, AppDimens.avatarEnd);
      expect(svg.clipBehavior, Clip.none);
      expect(find.byType(ClipRect), findsNothing);

      final iconFinder = find.byType(RoundResultIcon);
      final iconWidget = tester.widget<RoundResultIcon>(iconFinder);
      expect(iconWidget.variant, RoundResultVariant.win);
      expect(iconWidget.assetPath, RoundResultIcon.winAsset);
    });

    testWidgets('2. Kaybettin varyantı (lose) round_lose.svg çizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoundResultIcon.lose(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, AppDimens.avatarEnd);
      expect(svg.clipBehavior, Clip.none);

      final iconFinder = find.byType(RoundResultIcon);
      final iconWidget = tester.widget<RoundResultIcon>(iconFinder);
      expect(iconWidget.variant, RoundResultVariant.lose);
      expect(iconWidget.assetPath, RoundResultIcon.loseAsset);
    });

    testWidgets('3. Berabere varyantı (draw) round_draw.svg çizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoundResultIcon.draw(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, AppDimens.avatarEnd);
      expect(svg.clipBehavior, Clip.none);

      final iconFinder = find.byType(RoundResultIcon);
      final iconWidget = tester.widget<RoundResultIcon>(iconFinder);
      expect(iconWidget.variant, RoundResultVariant.draw);
      expect(iconWidget.assetPath, RoundResultIcon.drawAsset);
    });

    testWidgets('4. disableAnimations true iken FadeTransition ve ScaleTransition olmadan doğrudan çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: RoundResultIcon.win(),
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(RoundResultIcon),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(RoundResultIcon),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('5. Özel boyut ve dolgu (padding) parametreleri doğru uygulanır', (tester) async {
      const customSize = 80.0;
      const customPadding = EdgeInsets.all(8.0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RoundResultIcon(
                variant: RoundResultVariant.win,
                size: customSize,
                padding: customPadding,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, customSize);
      expect(svg.height, customSize);

      final paddingFinder = find.ancestor(of: svgFinder, matching: find.byType(Padding));
      expect(paddingFinder, findsOneWidget);
      final padding = tester.widget<Padding>(paddingFinder);
      expect(padding.padding, customPadding);
    });
  });
}
