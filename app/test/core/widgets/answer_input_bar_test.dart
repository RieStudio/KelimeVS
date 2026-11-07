import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/answer_input_bar.dart';

void main() {
  group('AnswerInputBar Widget Tests', () {
    testWidgets('1. TextField üzerinde autocorrect, enableSuggestions ve keyboardType TextInputType.text açıktır', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerInputBar(
              isMyTurn: true,
              onSubmitted: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);

      expect(textField.autocorrect, isTrue);
      expect(textField.enableSuggestions, isTrue);
      expect(textField.keyboardType, TextInputType.text);
      expect(textField.textCapitalization, TextCapitalization.none);
      expect(textField.textInputAction, TextInputAction.send);
      expect(textField.readOnly, isFalse);
    });

    testWidgets('2. Türkçe karakterli ve büyük harfli metin gönderildiğinde onSubmitted doğru metni alır', (tester) async {
      String? submittedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerInputBar(
              isMyTurn: true,
              onSubmitted: (val) {
                submittedText = val;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Türkçe karakterli ve ilk harfi büyük metin gir
      await tester.enterText(find.byType(TextField), 'Ispanak');
      await tester.pump();

      // Gönder butonuna tıkla
      await tester.tap(find.bySemanticsLabel(AppStrings.send));
      await tester.pump();

      expect(submittedText, equals('Ispanak'));

      // Ayrıca klavyeden send eylemi ile göndermeyi de doğrula
      await tester.enterText(find.byType(TextField), 'Şeftali');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(submittedText, equals('Şeftali'));
    });

    testWidgets('3. Sıra rakipteyken alan readOnly olur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerInputBar(
              isMyTurn: false,
              onSubmitted: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.readOnly, isTrue);
    });
  });
}
