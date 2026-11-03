import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/player_card.dart';

void main() {
  group('PlayerCard Widget Tests', () {
    testWidgets(
      'Oyuncu adı, skoru ve avatarı düzgün görüntülenir',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Zeynep',
                score: 2,
                avatar: SizedBox(width: 36, height: 36),
              ),
            ),
          ),
        );

        expect(find.text('Zeynep'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.byType(SizedBox), findsWidgets);
      },
    );

    testWidgets(
      'Pasif oyuncuda süre dolgusu ve süre yazısı görünmez',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Sen',
                score: 1,
                avatar: SizedBox(width: 36, height: 36),
                isActive: false,
                remainingSeconds: 12,
              ),
            ),
          ),
        );

        expect(find.text('Sen'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('12 sn'), findsNothing);
        expect(find.bySemanticsLabel(AppStrings.timeLeftLabel), findsNothing);
      },
    );

    testWidgets(
      'Aktif oyuncuda kalan süre ve ilerleme dolgusu gösterilir, 5 sn altında danger rengine geçer',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Rakip',
                score: 0,
                avatar: SizedBox(width: 36, height: 36),
                isActive: true,
                remainingSeconds: 4,
                timeProgress: 0.25,
              ),
            ),
          ),
        );

        expect(find.text('Rakip'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.text('4 sn'), findsOneWidget);

        // Kalan süre dolgusu semantik olarak mevcuttur
        expect(find.bySemanticsLabel(AppStrings.timeLeftLabel), findsOneWidget);

        // AnimatedContainer'ın rengi dangerSoft olmalıdır
        final animatedContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.bySemanticsLabel(AppStrings.timeLeftLabel),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (animatedContainer.decoration as BoxDecoration?)?.color,
          AppColors.dangerSoft,
        );
      },
    );

    testWidgets(
      'Süre sınır testleri: 15ten büyük (4965 sn), negatif (-5 sn), tam 0 ve tam 15 sn durumları 0-15 arasına clamp edilir',
      (tester) async {
        // Durum 1: 4965 sn verildiğinde 15 sn olarak görüntülenir
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Oyuncu 1',
                score: 0,
                avatar: SizedBox(),
                isActive: true,
                remainingSeconds: 4965,
              ),
            ),
          ),
        );
        expect(find.text('15 sn'), findsOneWidget);

        // Durum 2: Negatif süre (-5 sn) verildiğinde 0 sn olarak görüntülenir
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Oyuncu 2',
                score: 0,
                avatar: SizedBox(),
                isActive: true,
                remainingSeconds: -5,
              ),
            ),
          ),
        );
        expect(find.text('0 sn'), findsOneWidget);

        // Durum 3: Tam 0 sn
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Oyuncu 3',
                score: 0,
                avatar: SizedBox(),
                isActive: true,
                remainingSeconds: 0,
              ),
            ),
          ),
        );
        expect(find.text('0 sn'), findsOneWidget);

        // Durum 4: Tam 15 sn
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Oyuncu 4',
                score: 0,
                avatar: SizedBox(),
                isActive: true,
                remainingSeconds: 15,
              ),
            ),
          ),
        );
        expect(find.text('15 sn'), findsOneWidget);
      },
    );

    testWidgets(
      'isPaused true iken PlayerCard süre çubuğu donar, false olunca akmaya devam eder',
      (tester) async {
        Widget buildCard(bool isPaused) {
          return MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Oyuncu',
                score: 0,
                avatar: const SizedBox(),
                isActive: true,
                remainingSeconds: 10,
                timeProgress: 0.5,
                maxSeconds: 20,
                isPaused: isPaused,
              ),
            ),
          );
        }

        await tester.pumpWidget(buildCard(true));
        await tester.pump();

        FractionallySizedBox getBox() => tester.widget<FractionallySizedBox>(
              find.byWidgetPredicate(
                (w) => w is FractionallySizedBox && w.alignment == Alignment.centerLeft,
              ),
            );

        expect(getBox().widthFactor, 0.5);

        // isPaused true iken 500 ms pump edilse de donuk kalmalı
        await tester.pump(const Duration(milliseconds: 500));
        expect(getBox().widthFactor, 0.5);

        // isPaused false olunca devam etmeli
        await tester.pumpWidget(buildCard(false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(getBox().widthFactor, lessThan(0.5));
      },
    );

    testWidgets(
      'Küçük ekran (360 dp) ve textScale 1.3 altında M-#### adı kırpılmaz, uzun ad kısaltılır',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 360 dp ekranda iki oyuncu kartı yatay düzende (MatchScreen düzeni gibi)
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: const [
                      Expanded(
                        child: PlayerCard(
                          name: 'Sen',
                          score: 0,
                          avatar: SizedBox(width: 34, height: 34),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: PlayerCard(
                          name: 'M-9633',
                          score: 0,
                          avatar: SizedBox(width: 34, height: 34),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // M-9633 metninin kırpılmadığını (didExceedMaxLines == false) doğrula
        final mTextFinder = find.text('M-9633');
        expect(mTextFinder, findsOneWidget);
        final mParagraph = tester.renderObject<RenderParagraph>(mTextFinder);
        expect(
          mParagraph.didExceedMaxLines,
          isFalse,
          reason: 'M-9633 metni 360 dp ve textScale 1.3 iken kırpılmamalı/kısaltılmamalıdır',
        );

        // Şimdi çok uzun takma ad içeren kart test edilsin
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: const [
                      Expanded(
                        child: PlayerCard(
                          name: 'Sen',
                          score: 0,
                          avatar: SizedBox(width: 34, height: 34),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: PlayerCard(
                          name: 'CokUzunTakmaAd1234',
                          score: 0,
                          avatar: SizedBox(width: 34, height: 34),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final longTextFinder = find.text('CokUzunTakmaAd1234');
        expect(longTextFinder, findsOneWidget);
        final longParagraph = tester.renderObject<RenderParagraph>(longTextFinder);
        expect(
          longParagraph.didExceedMaxLines,
          isTrue,
          reason: 'Çok uzun takma ad için kısaltma (…) davranışı korunmalıdır',
        );
      },
    );
  });
}
