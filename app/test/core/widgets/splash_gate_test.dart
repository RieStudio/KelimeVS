import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/splash_gate.dart';

void main() {
  group('SplashGate Widget Tests', () {
    setUp(() {
      SplashConfig.resetForTest(hasShown: false);
    });

    tearDown(() {
      SplashConfig.resetForTest(hasShown: false);
    });

    testWidgets('1. Soğuk başlangıçta siyah zemin ve beyaz logo görünür, 1200ms + 250ms fade sonrası kaybolur', (tester) async {
      expect(SplashConfig.backgroundColor, const Color(0xFF000000));

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashGate(
            child: Scaffold(
              body: Center(child: Text('MainContent')),
            ),
          ),
        ),
      );

      // t = 0 ms: İlk kare çizildi, splash siyah zemin ve beyaz logo ile görünür
      await tester.pump();
      final imageFinder = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == AppStrings.companyName,
      );
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<Image>(imageFinder);
      final imageProvider = image.image;
      final assetImage = imageProvider is ResizeImage
          ? imageProvider.imageProvider as AssetImage
          : imageProvider as AssetImage;
      expect(assetImage.assetName, 'assets/images/riestudio_logo_white.png');

      // Siyah zemin Container'ı mevcut olmalı
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == const Color(0xFF000000),
        ),
        findsOneWidget,
      );

      // t = 600 ms: Splash hâlâ aktif olmalı
      await tester.pump(const Duration(milliseconds: 600));
      expect(imageFinder, findsOneWidget);

      // t = 1199 ms: 1200 ms dolmadan splash hâlâ görünür
      await tester.pump(const Duration(milliseconds: 599));
      expect(imageFinder, findsOneWidget);

      // t = 1200 ms: minSplashDuration doldu, fade-out başladı
      await tester.pump(const Duration(milliseconds: 1));

      // Fade-out animasyonunu tamamla (250 ms) ve widget ağacını yerleştir
      await tester.pumpAndSettle();

      // Splash overlay'i tamamen kaldırılmış olmalı, ana içerik görünmeli
      expect(find.text('MainContent'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == AppStrings.companyName,
        ),
        findsNothing,
      );
      expect(SplashConfig.hasShownSplash, isTrue);
    });

    testWidgets('2. hasShownSplash = true iken splash gösterilmez, doğrudan child açılır', (tester) async {
      SplashConfig.hasShownSplash = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashGate(
            child: Scaffold(
              body: Center(child: Text('DirectContent')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('DirectContent'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == AppStrings.companyName,
        ),
        findsNothing,
      );
    });

    testWidgets('3. Splash logo errorBuilder fallback metin üretir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashGate(
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final imageFinder = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == AppStrings.companyName,
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);

      final context = tester.element(imageFinder);
      final fallbackWidget = imageWidget.errorBuilder!(
        context,
        Exception('Asset missing'),
        StackTrace.empty,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: fallbackWidget)),
        ),
      );
      expect(find.text(AppStrings.companyName), findsOneWidget);
    });

    testWidgets('4. 320 dp ve textScaler 1.5 altında taşma olmadan çizilir', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            home: SplashGate(
              child: Scaffold(body: Text('Ready')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == AppStrings.companyName,
        ),
        findsOneWidget,
      );
    });
  });
}
