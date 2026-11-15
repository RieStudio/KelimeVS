import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/match_request/presentation/widgets/match_request_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchRequestToastWidget Widget Tests', () {
    testWidgets('uyarı/hata tostunda danger stili ve error ikonu gösterilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'İstek reddedildi',
              isDanger: true,
            ),
          ),
        ),
      );

      expect(find.text('İstek reddedildi'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      final text = tester.widget<Text>(find.text('İstek reddedildi'));
      expect(text.style?.color, AppColors.dangerText);
    });

    testWidgets('bilgilendirme tostunda nötr stil ve info ikonu gösterilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'İstek yanıtsız kaldı',
              isDanger: false,
            ),
          ),
        ),
      );

      expect(find.text('İstek yanıtsız kaldı'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

      final text = tester.widget<Text>(find.text('İstek yanıtsız kaldı'));
      expect(text.style?.color, AppColors.ink);
    });

    testWidgets('tosta tıklandığında onDismiss tetiklenir', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'Test mesajı',
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test mesajı'));
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });
}
