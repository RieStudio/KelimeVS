import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/empty_state_card.dart';

void main() {
  group('EmptyStateCard Tests', () {
    testWidgets('varsayılan dekorasyon kalın kenarlık (3px), ink rengi ve gölge içerir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: EmptyStateCard(
                child: Text('Boş Durum'),
              ),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(EmptyStateCard),
          matching: find.byType(Container),
        ).first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(AppColors.card));
      expect(decoration.borderRadius, equals(AppDimens.borderRadiusListCard));
      expect(decoration.border?.top.color, equals(AppColors.ink));
      expect(decoration.border?.top.width, equals(AppDimens.borderThick));
      expect(decoration.boxShadow, equals(AppDimens.shadowQuestionCard));
      expect(container.padding, equals(const EdgeInsets.all(AppDimens.space24)));
      expect(find.text('Boş Durum'), findsOneWidget);
    });

    test('buildDecoration statik yardımcısı doğru değerleri üretir', () {
      final defaultDec = EmptyStateCard.buildDecoration();
      expect(defaultDec.color, equals(AppColors.card));
      expect(defaultDec.border?.top.color, equals(AppColors.ink));
      expect(defaultDec.border?.top.width, equals(AppDimens.borderThick));
      expect(defaultDec.borderRadius, equals(AppDimens.borderRadiusListCard));
      expect(defaultDec.boxShadow, equals(AppDimens.shadowQuestionCard));

      final customDec = EmptyStateCard.buildDecoration(
        color: AppColors.surface,
        borderColor: AppColors.dangerSoft,
        borderWidth: AppDimens.borderThin,
        boxShadow: const [],
      );
      expect(customDec.color, equals(AppColors.surface));
      expect(customDec.border?.top.color, equals(AppColors.dangerSoft));
      expect(customDec.border?.top.width, equals(AppDimens.borderThin));
      expect(customDec.boxShadow, isEmpty);
    });
  });
}

