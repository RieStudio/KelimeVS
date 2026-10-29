import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/match_tip_card.dart';
import 'package:app/core/widgets/section_label.dart';

void main() {
  group('MatchTipCard Widget Tests', () {
    testWidgets('Başlık ve ipucu metnini doğru stillerle çizer', (tester) async {
      const sampleTip = 'Yanlış cevap turu kaybettirmez; süren bitene kadar tekrar deneyebilirsin.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchTipCard(tip: sampleTip),
          ),
        ),
      );

      expect(find.byType(SectionLabel), findsOneWidget);
      expect(find.text(AppStrings.searchTipTitle), findsOneWidget);
      expect(find.text(sampleTip), findsOneWidget);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.card);
      expect(decoration.border?.top.color, AppColors.mint);
    });

    testWidgets('320 dp dar ekran ve textScaler 1.5 altında tüm havuz metinleri taşma olmadan çizilir', (tester) async {
      final tips = AppStrings.getMatchTips(answerSeconds: 15);

      for (final tip in tips) {
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
                  child: MatchTipCard(tip: tip),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: 'Metin taştı: $tip');
        expect(find.text(tip), findsOneWidget);
      }
    });
  });
}

