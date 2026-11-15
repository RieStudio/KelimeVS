import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/secondary_button.dart';

void main() {
  group('SecondaryButton Widget Tests', () {
    testWidgets('Standart SecondaryButton card zemin, ink kenarlık ve ink yazıya sahiptir', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton(
              text: 'Normal Buton',
              onPressed: () {},
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, AppColors.card);
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.ink);
      expect(border.top.width, AppDimens.borderThick);

      final text = tester.widget<Text>(find.text('Normal Buton'));
      expect(text.style?.color, AppColors.ink);
    });

    testWidgets('SecondaryButton.danger (tehlike çerçeveli) card zemin, danger kenarlık, dangerText yazı ve dangerDark gölgeye sahiptir', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton.danger(
              text: 'İptal',
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      // Zemin: card (beyaz), KIRMIZI DOLGU YOK
      expect(decoration.color, AppColors.card);

      // Kenarlık: kırmızı (AppColors.danger), kalınlık 3
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.danger);
      expect(border.top.width, AppDimens.borderThick);

      // Gölge: dangerDark
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppColors.dangerDark);

      // Yazı: AppColors.dangerText
      final text = tester.widget<Text>(find.text('İptal'));
      expect(text.style?.color, AppColors.dangerText);

      // Tıklanma testi
      await tester.tap(find.text('İptal'));
      await tester.pump();
      expect(pressed, isTrue);
    });

    testWidgets('SecondaryButton.danger buton ölçüleri ve dokunma alanı standartları korur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondaryButton.danger(
              text: 'İptal',
              onPressed: () {},
            ),
          ),
        ),
      );

      final sizeBoxFinder = find.byType(ConstrainedBox);
      expect(sizeBoxFinder, findsWidgets);
      final constrainedBox = tester.widget<ConstrainedBox>(sizeBoxFinder.first);
      expect(constrainedBox.constraints.minHeight, greaterThanOrEqualTo(AppDimens.minTouchTarget));
    });
  });
}
