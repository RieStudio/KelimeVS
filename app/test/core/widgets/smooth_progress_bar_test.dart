import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/smooth_progress_bar.dart';

void main() {
  group('SmoothProgressBar Widget Tests', () {
    testWidgets('1. Sürekli pürüzsüz ve monotonik azalış: her karede (16 ms) sıçramadan azalır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: 1000,
                remainingMs: 1000,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        ),
      );

      // İlk kare: tam 1.0
      await tester.pump();
      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, 1.0);

      // 50 ms sonra: ~0.95 olmalı ve 1.0'dan küçük olmalı
      await tester.pump(const Duration(milliseconds: 50));
      final p50 = getBox().widthFactor!;
      expect(p50, lessThan(1.0));
      expect(p50, closeTo(0.95, 0.02));

      // 100 ms sonra: p50'den daha küçük olmalı (monotonik azalış)
      await tester.pump(const Duration(milliseconds: 50));
      final p100 = getBox().widthFactor!;
      expect(p100, lessThan(p50));
      expect(p100, closeTo(0.90, 0.02));

      // 500 ms sonra: ~0.40
      await tester.pump(const Duration(milliseconds: 500));
      final p600 = getBox().widthFactor!;
      expect(p600, lessThan(p100));
      expect(p600, closeTo(0.40, 0.02));

      // 1000 ms sonra: tam 0.0'a inip durmalı
      await tester.pump(const Duration(milliseconds: 600));
      expect(getBox().widthFactor, 0.0);
    });

    testWidgets('2. Duraklatma (isPaused: true): Ticker durur ve genişlik donar', (tester) async {
      Widget buildTest(bool isPaused) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: 2000,
                remainingMs: 1000,
                isPaused: isPaused,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTest(true));
      await tester.pump();

      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, 0.5);

      // isPaused true iken 500 ms ilerletildiğinde genişlik donmuş kalmalı
      await tester.pump(const Duration(milliseconds: 500));
      expect(getBox().widthFactor, 0.5);

      // isPaused false olunca akış kaldığı yerden devam etmeli
      await tester.pumpWidget(buildTest(false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(getBox().widthFactor, lessThan(0.5));
    });

    testWidgets('3. Ek süre (+5 sn / süre artışı): sert sıçramak yerine yumuşakça genişler', (tester) async {
      Widget buildTest(int remainingMs, int totalMs) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: totalMs,
                remainingMs: remainingMs,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        );
      }

      // Başlangıç: 2000 ms / 10000 ms = 0.20
      await tester.pumpWidget(buildTest(2000, 10000));
      await tester.pump();

      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, 0.20);

      // Ek süre kullanıldı: süre 7000 ms (+5000 ms) oldu, toplam 15000 ms -> hedef ~0.467
      await tester.pumpWidget(buildTest(7000, 15000));
      await tester.pump();

      // Anında 0.467'ye zıplamaz, lerp başlar
      final initialLerp = getBox().widthFactor!;
      expect(initialLerp, closeTo(0.20, 0.05));

      // 125 ms sonra (~yarı yolda): 0.20 ile 0.467 arasında olmalı
      await tester.pump(const Duration(milliseconds: 125));
      final midLerp = getBox().widthFactor!;
      expect(midLerp, greaterThan(initialLerp));
      expect(midLerp, lessThan(0.48));

      // 250 ms sonra lerp tamamlanır, hedef değere ulaşır
      await tester.pump(const Duration(milliseconds: 150));
      final finalLerp = getBox().widthFactor!;
      expect(finalLerp, closeTo(0.45, 0.05));
    });

    testWidgets('4. Pasif (isActive: false): Ticker çalışmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: 1000,
                remainingMs: 500,
                isActive: false,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, 0.5);

      // isActive false iken süre aksa bile değişmez
      await tester.pump(const Duration(milliseconds: 300));
      expect(getBox().widthFactor, 0.5);
    });

    testWidgets('5. Erişilebilirlik (disableAnimations: true): Ticker çalışmaz, doğrudan statik değer çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 300,
                height: 20,
                child: SmoothProgressBar(
                  totalDurationMs: 1000,
                  remainingMs: 700,
                  fillColor: AppColors.bright,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, closeTo(0.70, 0.01));

      // Ticker çalışmadığı için animasyon ilerlemez
      await tester.pump(const Duration(milliseconds: 200));
      expect(getBox().widthFactor, closeTo(0.70, 0.01));
    });

    testWidgets('6. Grace süresi ve 0 ms: çubuk 0.0da sabit bekler, negatif olmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: 1000,
                remainingMs: 0,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
            find.byWidgetPredicate((w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft),
          );

      expect(getBox().widthFactor, 0.0);

      // 400 ms grace süresi boyunda 0.0'da kalır
      await tester.pump(const Duration(milliseconds: 400));
      expect(getBox().widthFactor, 0.0);
    });

    testWidgets('7. Dispose: Widget kaldırıldığında açık Ticker kalmaz ve hata fırlatmaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 20,
              child: SmoothProgressBar(
                totalDurationMs: 5000,
                remainingMs: 5000,
                fillColor: AppColors.bright,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));

      // Widget'ı ağaçtan kaldır
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );
      await tester.pump();

      // Hiçbir exception fırlatılmadan temizlenmiş olmalı
      expect(tester.takeException(), isNull);
    });
  });
}

