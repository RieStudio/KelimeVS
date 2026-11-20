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

    testWidgets('SecondaryButton hızlı dokunuşta (tester.tap): basılı görünüm (3 px kayma, gölge kalkması) uygulanır, en az 110 ms korunur', (tester) async {
      int pressCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SecondaryButton(
                text: 'Hızlı Buton',
                onPressed: () => pressCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(SecondaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;
      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);

      // Hızlı dokun (tap down & up aynı anda)
      await tester.tap(buttonFinder);
      await tester.pump();

      // onPressed gecikmesiz çalışır (actionDelay=0)
      expect(pressCount, 1);
      // Listener sayesinde anında gölge kalkar
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      // 90 ms sonra aşağı tam kayma gerçekleşir ve gölge kalkık kalır
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.secondaryButtonPressOffset, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      // 110 ms minPressedDuration sonrasında (90 + 30 = 120 ms) bırakılır
      await tester.pump(const Duration(milliseconds: 30));

      // 90 ms animasyon ile başlangıç pozisyonuna döner
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
      expect(pressCount, 1);
    });

    testWidgets('SecondaryButton ListView içinde hızlı dokunuşta gecikmesiz basma efekti gösterir', (tester) async {
      int pressCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 50),
                SecondaryButton(
                  text: 'Listede Buton',
                  onPressed: () => pressCount++,
                ),
              ],
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(SecondaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      await tester.tap(buttonFinder);
      await tester.pump();

      expect(pressCount, 1);
      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.secondaryButtonPressOffset, 0.01));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
    });

    testWidgets('SecondaryButton uzun basma ve sürükleyerek iptal (cancel) davranışını doğru işletir', (tester) async {
      int pressCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SecondaryButton(
                text: 'İptal',
                onPressed: () => pressCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(SecondaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      final gesture = await tester.startGesture(tester.getCenter(buttonFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.secondaryButtonPressOffset, 0.01));

      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      expect(pressCount, 0);
    });

    testWidgets('SecondaryButton devre dışıyken (onPressed: null) basma efekti çalışmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SecondaryButton(
                text: 'Pasif',
                onPressed: null,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(SecondaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      await tester.tap(buttonFinder);
      await tester.pump();

      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      await tester.pumpAndSettle();
    });
  });
}
