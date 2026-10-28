import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/theme/app_text_styles.dart';
import 'package:app/core/widgets/answer_bubble.dart';

void main() {
  group('AnswerBubble Unit & Widget Tests', () {
    testWidgets('Kendi balonu sağa hizalanır ve kuyruk showTail=true iken etkindir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'KELİME',
              isMe: true,
              showTail: true,
            ),
          ),
        ),
      );

      final align = tester.widget<Align>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(Align)),
      );
      expect(align.alignment, Alignment.centerRight);

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(CustomPaint)),
      );
      final painter = customPaint.painter as BubblePainter;
      expect(painter.isMe, isTrue);
      expect(painter.showTail, isTrue);
      expect(painter.color, AppColors.bright);
      expect(painter.borderColor, AppColors.ink);
      expect(painter.borderWidth, AppDimens.borderThin);
    });

    testWidgets('Rakip balonu sola hizalanır ve kuyruk showTail=true iken etkindir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'KUTU',
              isMe: false,
              showTail: true,
            ),
          ),
        ),
      );

      final align = tester.widget<Align>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(Align)),
      );
      expect(align.alignment, Alignment.centerLeft);

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(CustomPaint)),
      );
      final painter = customPaint.painter as BubblePainter;
      expect(painter.isMe, isFalse);
      expect(painter.showTail, isTrue);
      expect(painter.color, AppColors.card);
      expect(painter.borderColor, AppColors.ink);
    });

    testWidgets('showTail=false olduğunda painter kuyruksuz modda çalışır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'DEVAM',
              isMe: true,
              showTail: false,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(CustomPaint)),
      );
      final painter = customPaint.painter as BubblePainter;
      expect(painter.showTail, isFalse);
    });

    testWidgets('Reddedilen cevap: card dolgu, danger kenarlık ve dangerText yazı', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble.rejected(
              text: 'YANLIŞ',
              isMe: true,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(CustomPaint)),
      );
      final painter = customPaint.painter as BubblePainter;
      expect(painter.isRejected, isTrue);
      expect(painter.color, AppColors.card);
      expect(painter.borderColor, AppColors.danger);

      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.style?.color, AppTextStyles.answerBubbleRejected.color);
    });

    testWidgets('Seçili balon: borderThick ve isSelected=true ile çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'SEÇİLİ',
              isMe: true,
              isSelected: true,
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(AnswerBubble), matching: find.byType(CustomPaint)),
      );
      final painter = customPaint.painter as BubblePainter;
      expect(painter.isSelected, isTrue);
      expect(painter.borderWidth, AppDimens.borderThick);
    });

    testWidgets('RepaintBoundary ile sarılıdır', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'TEST',
              isMe: true,
            ),
          ),
        ),
      );

      expect(find.descendant(of: find.byType(AnswerBubble), matching: find.byType(RepaintBoundary)), findsOneWidget);
    });

    testWidgets('Dokunma (onTap) geri çağrımı çalışır', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerBubble(
              text: 'DOKUN',
              isMe: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('DOKUN'));
      expect(tapped, isTrue);
    });

    testWidgets('Kendi balonları (isMe=true): kuyruklu ve kuyruksuz balon gövde ve metin yatayda TAM HİZALIDIR', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                children: [
                  AnswerBubble(
                    key: ValueKey('bubble_1'),
                    text: 'AYNI_KELİME',
                    isMe: true,
                    showTail: true,
                  ),
                  AnswerBubble(
                    key: ValueKey('bubble_2'),
                    text: 'AYNI_KELİME',
                    isMe: true,
                    showTail: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Metinlerin X başlangıç pozisyonlarını bul
      final text1Finder = find.descendant(of: find.byKey(const ValueKey('bubble_1')), matching: find.byType(Text));
      final text2Finder = find.descendant(of: find.byKey(const ValueKey('bubble_2')), matching: find.byType(Text));

      final text1Rect = tester.getRect(text1Finder);
      final text2Rect = tester.getRect(text2Finder);

      // Metinler yatayda piksel piksel aynı X pozisyonunda ve aynı genişlikte olmalı
      expect(text1Rect.left, equals(text2Rect.left));
      expect(text1Rect.right, equals(text2Rect.right));
      expect(text1Rect.width, equals(text2Rect.width));

      // Balon gövdelerinin (CustomPaint) X başlangıç pozisyonlarını bul
      final paint1Finder = find.descendant(of: find.byKey(const ValueKey('bubble_1')), matching: find.byType(CustomPaint));
      final paint2Finder = find.descendant(of: find.byKey(const ValueKey('bubble_2')), matching: find.byType(CustomPaint));

      final paint1Rect = tester.getRect(paint1Finder);
      final paint2Rect = tester.getRect(paint2Finder);

      // Gövdenin sol kenarı aynı X koordinatında olmalı
      expect(paint1Rect.left, equals(paint2Rect.left));
      // Kuyruklu olan, sağda ek olarak nipWidth (6px) kuyruğa sahiptir
      expect(paint1Rect.width - paint2Rect.width, closeTo(BubblePainter.nipWidth, 0.001));
    });

    testWidgets('Rakip balonları (isMe=false): kuyruklu ve kuyruksuz balon gövde ve metin yatayda TAM HİZALIDIR', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                children: [
                  AnswerBubble(
                    key: ValueKey('opp_1'),
                    text: 'RAKİP_KELİME',
                    isMe: false,
                    showTail: true,
                  ),
                  AnswerBubble(
                    key: ValueKey('opp_2'),
                    text: 'RAKİP_KELİME',
                    isMe: false,
                    showTail: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final text1Finder = find.descendant(of: find.byKey(const ValueKey('opp_1')), matching: find.byType(Text));
      final text2Finder = find.descendant(of: find.byKey(const ValueKey('opp_2')), matching: find.byType(Text));

      final text1Rect = tester.getRect(text1Finder);
      final text2Rect = tester.getRect(text2Finder);

      // Metinler yatayda tam aynı X pozisyonunda ve aynı genişlikte olmalı
      expect(text1Rect.left, equals(text2Rect.left));
      expect(text1Rect.right, equals(text2Rect.right));
      expect(text1Rect.width, equals(text2Rect.width));

      final paint1Finder = find.descendant(of: find.byKey(const ValueKey('opp_1')), matching: find.byType(CustomPaint));
      final paint2Finder = find.descendant(of: find.byKey(const ValueKey('opp_2')), matching: find.byType(CustomPaint));

      final paint1Rect = tester.getRect(paint1Finder);
      final paint2Rect = tester.getRect(paint2Finder);

      // Sağ kenarlar aynı X koordinatında olmalı
      expect(paint1Rect.right, equals(paint2Rect.right));
      // Kuyruklu olan, solda ek olarak nipWidth (6px) kuyruğa sahiptir
      expect(paint1Rect.width - paint2Rect.width, closeTo(BubblePainter.nipWidth, 0.001));
    });

    testWidgets('320 dp ekran ve textScaler 1.5 altında 40 karakterlik kelime taşmaz (overflow yok)', (tester) async {
      const long40CharWord = 'MUVAFFAKİYETSİZLEŞTİRİCİLEŞTİRİVEREMEYEB';
      expect(long40CharWord.length, 40);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: Column(
                  children: [
                    AnswerBubble(
                      text: long40CharWord,
                      isMe: true,
                      showTail: true,
                    ),
                    AnswerBubble(
                      text: long40CharWord,
                      isMe: false,
                      showTail: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // RenderFlex overflow hatası yakalanmamalıdır
      expect(tester.takeException(), isNull);

      final bubbleFinders = find.byType(AnswerBubble);
      for (final b in bubbleFinders.evaluate()) {
        final renderBox = b.renderObject as RenderBox;
        // Balon hiçbir zaman ekran genişliğini (320) aşmamalı
        expect(renderBox.size.width, lessThanOrEqualTo(320.0));
      }
    });
  });
}
