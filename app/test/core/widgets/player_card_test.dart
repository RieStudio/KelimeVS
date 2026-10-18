import 'package:flutter/material.dart';
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
  });
}
