import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/match_result_icon.dart';

void main() {
  group('MatchResultIcon Widget Tests', () {
    testWidgets('1. Kazandın varyantı (win) match_win.svg çizer ve Clip.none kullanır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MatchResultIcon.win(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, AppDimens.matchEndIcon);
      expect(svg.height, AppDimens.matchEndIcon);
      expect(svg.clipBehavior, Clip.none);
      expect(find.byType(ClipRect), findsNothing);

      final iconFinder = find.byType(MatchResultIcon);
      final iconWidget = tester.widget<MatchResultIcon>(iconFinder);
      expect(iconWidget.variant, MatchResultVariant.win);
      expect(iconWidget.assetPath, MatchResultIcon.winAsset);
      expect(iconWidget.semanticLabel, AppStrings.wonExclamation);
    });

    testWidgets('2. Kaybettin varyantı (lose) match_lose.svg çizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MatchResultIcon.lose(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);
      final svg = tester.widget<SvgPicture>(svgFinder);
      expect(svg.width, AppDimens.matchEndIcon);
      expect(svg.height, AppDimens.matchEndIcon);
      expect(svg.clipBehavior, Clip.none);
      expect(find.byType(ClipRect), findsNothing);

      final iconFinder = find.byType(MatchResultIcon);
      final iconWidget = tester.widget<MatchResultIcon>(iconFinder);
      expect(iconWidget.variant, MatchResultVariant.lose);
      expect(iconWidget.assetPath, MatchResultIcon.loseAsset);
      expect(iconWidget.semanticLabel, AppStrings.lost);
    });

    testWidgets('3. disableAnimations true iken FadeTransition ve ScaleTransition olmadan doğrudan çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: MatchResultIcon.win(),
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(MatchResultIcon),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(MatchResultIcon),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('4. Özel boyut ve dolgu (padding) parametreleri doğru uygulanır', (tester) async {
      const customSize = 120.0;
      const customPadding = EdgeInsets.all(8.0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MatchResultIcon(
                variant: MatchResultVariant.win,
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

      final paddingFinder = find.ancestor(
        of: svgFinder,
        matching: find.byType(Padding),
      );
      expect(paddingFinder, findsOneWidget);
      final padding = tester.widget<Padding>(paddingFinder);
      expect(padding.padding, customPadding);
    });
  });
}

