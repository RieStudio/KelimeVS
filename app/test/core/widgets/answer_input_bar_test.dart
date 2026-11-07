import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets(
      '4. Odak hiç alınmamışken sıra değişince (isMyTurn true -> false -> true) klavye zorla açılmaz ve TextInput.show çağrılmaz',
      (tester) async {
        final List<MethodCall> textInputCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call);
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.textInput, null);
        });

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        bool isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return AnswerInputBar(
                    isMyTurn: isMyTurn,
                    focusNode: focusNode,
                    onSubmitted: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(focusNode.hasFocus, isFalse);
        textInputCalls.clear();

        // Sıra rakibe geçer
        isMyTurn = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isFalse);

        // Sıra tekrar bana geçer
        isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Odak hiç alınmadığı için klavye zorla açılmamalı
        expect(focusNode.hasFocus, isFalse);
        final showCalls = textInputCalls.where((c) => c.method == 'TextInput.show');
        expect(showCalls, isEmpty);
      },
    );

    testWidgets(
      '5. Odak daha önce alınmışken isMyTurn true -> false -> true geçişinde hasFocus korunur ve TextInput.show çağrılır',
      (tester) async {
        final List<MethodCall> textInputCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call);
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.textInput, null);
        });

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        bool isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Alana odaklanılır
        focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isTrue);

        textInputCalls.clear();

        // Sıra rakibe geçer (true -> false)
        isMyTurn = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        // focusNode unfocus yapılmadı, hasFocus hala true
        expect(focusNode.hasFocus, isTrue);

        // Sıra tekrar bana geçer (false -> true)
        isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        // PostFrameCallback tetiklenmesi için pump
        await tester.pump();

        expect(focusNode.hasFocus, isTrue);
        final showCalls = textInputCalls.where((c) => c.method == 'TextInput.show');
        expect(showCalls, isNotEmpty);
      },
    );

    testWidgets(
      '6. Odak daha önce alınmış ancak sıra rakipteyken focus kaybedilmişse, false -> true geçişinde requestFocus çağrılarak odak geri alınır',
      (tester) async {
        final List<MethodCall> textInputCalls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call);
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.textInput, null);
        });

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        bool isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Alana odaklanılır
        focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isTrue);

        // Sıra rakibe geçer
        isMyTurn = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        // Sistem veya kullanıcı tarafından odak kaybedildiğini simüle et
        focusNode.unfocus();
        await tester.pump();
        expect(focusNode.hasFocus, isFalse);

        // Sıra tekrar bana geçer (false -> true)
        isMyTurn = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerInputBar(
                isMyTurn: isMyTurn,
                focusNode: focusNode,
                onSubmitted: (_) {},
              ),
            ),
          ),
        );
        // Post-frame callback
        await tester.pump();

        // Odak yeniden kazanılmış olmalıdır
        expect(focusNode.hasFocus, isTrue);
      },
    );
  });
}
