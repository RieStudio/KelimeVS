import 'dart:math' as math;

import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/match_request/presentation/widgets/match_request_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 Bağıl Parlaklık (Relative Luminance) hesaplayıcı
double _calculateRelativeLuminance(Color color) {
  double channel(double c) {
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 2.1 Kontrast Oranı (L1 + 0.05) / (L2 + 0.05)
double _calculateContrastRatio(Color foreground, Color background) {
  final l1 = _calculateRelativeLuminance(foreground);
  final l2 = _calculateRelativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('MatchRequestToastWidget Widget Tests', () {
    testWidgets('uyarı/hata tostunda danger stili (card zemin, danger kenarlık, dangerText yazı, ink gölge) ve error ikonu gösterilir', (tester) async {
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

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
      expect(icon.color, AppColors.dangerText);

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      // Zemin: card (beyaz), KIRMIZI DOLGU YOK
      expect(decoration.color, AppColors.card);

      // Kenarlık: kırmızı (AppColors.danger), kalınlık 2
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.danger);
      expect(border.top.width, 2.0);

      // Sert gölge: ink
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppColors.ink);

      // Yazı: AppColors.dangerText ve TextDecoration.none (sarı alt çizgi yok)
      final text = tester.widget<Text>(find.text('İstek reddedildi'));
      expect(text.style?.color, AppColors.dangerText);
      expect(text.style?.decoration, TextDecoration.none);
    });

    testWidgets('bilgilendirme tostunda nötr stil (card zemin, ink kenarlık, ink yazı, ink gölge) ve info ikonu gösterilir', (tester) async {
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

      final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded));
      expect(icon.color, AppColors.ink);

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      // Zemin: card (beyaz)
      expect(decoration.color, AppColors.card);

      // Kenarlık: ink, kalınlık 2
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.ink);
      expect(border.top.width, 2.0);

      // Sert gölge: ink
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppColors.ink);

      final text = tester.widget<Text>(find.text('İstek yanıtsız kaldı'));
      expect(text.style?.color, AppColors.ink);
      expect(text.style?.decoration, TextDecoration.none);
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

    test('dangerText beyaz card zemin üzerinde WCAG AA (>= 4.5:1) kontrast gereksinimini sağlar', () {
      final ratio = _calculateContrastRatio(AppColors.dangerText, AppColors.card);
      // Beklenen oran ~6.45:1 - 6.6:1 arasıdır, 4.5:1 eşiğini fazlasıyla geçer
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, greaterThan(6.0));
    });
  });
}
