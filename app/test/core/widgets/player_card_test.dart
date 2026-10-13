import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/player_card.dart';

void main() {
  group('PlayerCard Widget Tests', () {
    testWidgets(
      'statusNote verildiğinde oyuncu adının altında görünür ve dangerText rengindedir',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Zeynep',
                score: 2,
                avatar: SizedBox(width: 36, height: 36),
                statusNote: AppStrings.opponentDisconnectedNote,
              ),
            ),
          ),
        );

        expect(find.text('Zeynep'), findsOneWidget);
        expect(find.text(AppStrings.opponentDisconnectedNote), findsOneWidget);

        final textWidget = tester.widget<Text>(
          find.text(AppStrings.opponentDisconnectedNote),
        );
        expect(textWidget.style?.color, AppColors.dangerText);
        expect(textWidget.style?.fontSize, 12);
      },
    );

    testWidgets(
      'statusNote null olduğunda adın altında not alanı görünmez',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Sen',
                score: 1,
                avatar: SizedBox(width: 36, height: 36),
                statusNote: null,
              ),
            ),
          ),
        );

        expect(find.text('Sen'), findsOneWidget);
        expect(find.text(AppStrings.opponentDisconnectedNote), findsNothing);
      },
    );

    testWidgets(
      'Aktif oyuncuda hem statusNote hem de kalan süre ve ilerleme dolgusu birlikte çalışır',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlayerCard(
                name: 'Rakip',
                score: 0,
                avatar: SizedBox(width: 36, height: 36),
                isActive: true,
                remainingSeconds: 11,
                timeProgress: 0.73,
                statusNote: AppStrings.opponentDisconnectedNote,
              ),
            ),
          ),
        );

        expect(find.text('Rakip'), findsOneWidget);
        expect(find.text(AppStrings.opponentDisconnectedNote), findsOneWidget);
        expect(find.text('11 sn'), findsOneWidget);

        // Kalan süre dolgusu semantik olarak mevcuttur
        expect(find.bySemanticsLabel(AppStrings.timeLeftLabel), findsOneWidget);
      },
    );
  });
}

