import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/answer_bubble.dart';
import 'package:app/core/widgets/kelime_vs_logo.dart';
import 'package:app/core/widgets/section_label.dart';
import 'package:app/gallery/component_gallery.dart';

void main() {
  group('KelimeVSLogo Speech Bubble Unit and Widget Tests', () {
    testWidgets('1. Varsayılan KelimeVSLogo Varyant A konuşma balonu olarak doğru çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: KelimeVSLogo()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kelime'), findsOneWidget);
      expect(find.text('VS'), findsOneWidget);

      final kelimeText = tester.widget<Text>(find.text('Kelime'));
      expect(kelimeText.style?.color, AppColors.ink);

      final vsText = tester.widget<Text>(find.text('VS'));
      expect(vsText.style?.color, AppColors.card);

      final customPaintFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BubblePainter,
      );
      expect(customPaintFinder, findsOneWidget);

      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final painter = customPaint.painter as BubblePainter;

      expect(painter.color, AppColors.primary);
      expect(painter.borderColor, Colors.transparent);
      expect(painter.borderWidth, 0.0);
      expect(painter.nipPosition, BubbleNipPosition.bottomLeft);
    });

    testWidgets('2. bubbleOffsetFactor 0.06 değeriyle balonu dikeyde aşağı öteler', (tester) async {
      const testFontSize = 64.0;
      expect(KelimeVSLogo.bubbleOffsetFactor, 0.06);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: KelimeVSLogo(fontSize: testFontSize)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final transformFinder = find.byWidgetPredicate(
        (w) => w is Transform && w.transform.getTranslation().y == testFontSize * KelimeVSLogo.bubbleOffsetFactor,
      );
      expect(transformFinder, findsOneWidget);
    });

    testWidgets('3. 320 dp genişlik ve textScaler 1.5 altında logo sıfır taşma ile çizilir', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final logos = <Widget>[
        const KelimeVSLogo(fontSize: 64),
        const KelimeVSLogo(fontSize: 52),
      ];

      for (final logo in logos) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: Center(child: logo),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final logoFinder = find.byWidget(logo);
        expect(logoFinder, findsOneWidget);
        final logoSize = tester.getSize(logoFinder);
        expect(logoSize.width, lessThanOrEqualTo(320.0));
      }
    });

    testWidgets('4. ComponentGallery içinde KelimeVS Logo bölümü (64 dp ve 52 dp) yer alır', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 5000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: ComponentGallery(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SectionLabel, 'KELİMEVS LOGO (KONUŞMA BALONLU)'),
        findsOneWidget,
      );
      expect(find.text('Ana Sayfa Boyutu (64 dp):'), findsOneWidget);
      expect(find.text('Orta Boyut (52 dp):'), findsOneWidget);
    });
  });
}
