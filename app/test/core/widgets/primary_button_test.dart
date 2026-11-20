import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/primary_button.dart';

void main() {
  group('PrimaryButton Widget Tests', () {
    testWidgets('1. Standart PrimaryButton primary zemin, beyaz yazı, gölge ve semantics içerir', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'Başla',
                subtitle: 'Hemen Oyna',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
      expect(buttonFinder, findsOneWidget);

      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final decoration = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(decoration.color, AppColors.primary);
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.offset, const Offset(0, 5));

      expect(find.text('Başla'), findsOneWidget);
      expect(find.text('Hemen Oyna'), findsOneWidget);

      final semantics = tester.getSemantics(buttonFinder);
      expect(semantics.label, contains('Başla, Hemen Oyna'));
    });

    testWidgets('2. Hızlı dokunuşta (tester.tap): basılı görünüm sonraki karelerde görünür, en az ~110 ms korunur ve onPressed tam 1 kez çalışır', (tester) async {
      int pressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'Hızlı Bas',
                onPressed: () => pressCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;
      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);

      // Hızlı dokun (down ve up aynı karede)
      await tester.tap(buttonFinder);

      // İlk kare: Listener sayesinde basılı durum başlar ve onPressed anında (actionDelay=0) tetiklenir
      await tester.pump();
      expect(pressCount, 1);

      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      // 90 ms animasyon sonunda tam aşağı kayma (4 px) ve gölge kalkık kalır
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.primaryButtonPressOffset, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      // 110 ms minPressedDuration dolduğunda (90 + 30 = 120 ms) bırakılır
      await tester.pump(const Duration(milliseconds: 30));

      // 90 ms animasyon ile başlangıç konumuna döner
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
      expect(pressCount, 1); // Çift tetikleme olmamalı
    });

    testWidgets('3. Kaydırılabilir ata (ListView) içinde hızlı dokunuşta gecikmesiz basma efekti görünür', (tester) async {
      int pressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 50),
                PrimaryButton(
                  text: 'Listede Buton',
                  onPressed: () => pressCount++,
                ),
              ],
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      // ListView içinde hızlı dokun
      await tester.tap(buttonFinder);
      await tester.pump();

      // Listener sayesinde ListView jest gecikmesine takılmadan ilk karede basılıdır
      expect(pressCount, 1);
      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.primaryButtonPressOffset, 0.01));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
    });

    testWidgets('4. Uzun basma (hold): basılı tutulunca kayma ve gölge kalkar, bırakınca eski haline döner', (tester) async {
      int pressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'Uzun Bas',
                onPressed: () => pressCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      final gesture = await tester.startGesture(tester.getCenter(buttonFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.primaryButtonPressOffset, 0.01));
      var dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isEmpty);

      // Parmağı 150 ms daha basılı tut
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.primaryButtonPressOffset, 0.01));

      // Bırak
      await gesture.up();
      await tester.pump();
      expect(pressCount, 1);

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
    });

    testWidgets('5. Kaydırma/parmak çıkınca (cancel) efekt eski haline döner ve onPressed tetiklenmez', (tester) async {
      int pressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'İptal Testi',
                onPressed: () => pressCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
      final containerFinder = find.descendant(
        of: buttonFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(containerFinder).dy;

      final gesture = await tester.startGesture(tester.getCenter(buttonFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + AppDimens.primaryButtonPressOffset, 0.01));

      // Sürükle veya iptal et
      await gesture.cancel();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      final dec = tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(dec.boxShadow, isNotEmpty);
      expect(pressCount, 0);
    });

    testWidgets('6. Devre dışı (onPressed: null) olduğunda basma efekti ve tıklama çalışmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'Devre Dışı',
                onPressed: null,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(PrimaryButton);
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

    testWidgets('7. minTouchTarget en az 48x48 dokunma alanı sağlar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PrimaryButton(
                text: 'Min',
                width: 30,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byType(PrimaryButton),
          matching: find.byType(ConstrainedBox),
        ),
      );

      expect(
        constrainedBoxes.any((cb) =>
            cb.constraints.minWidth >= AppDimens.minTouchTarget &&
            cb.constraints.minHeight >= AppDimens.minTouchTarget),
        isTrue,
      );
    });
  });
}
