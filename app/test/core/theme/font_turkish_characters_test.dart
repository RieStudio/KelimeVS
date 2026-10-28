import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_text_styles.dart';
import 'package:app/core/widgets/app_widgets.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Load local Fredoka font files into the Flutter test engine
    final boldFile = File('assets/fonts/Fredoka-Bold.ttf');
    final semiBoldFile = File('assets/fonts/Fredoka-SemiBold.ttf');

    if (boldFile.existsSync() && semiBoldFile.existsSync()) {
      final boldBytes = boldFile.readAsBytesSync();
      final semiBytes = semiBoldFile.readAsBytesSync();

      final fontLoader = FontLoader(AppTextStyles.fontFredoka);
      fontLoader.addFont(Future.value(ByteData.view(boldBytes.buffer)));
      fontLoader.addFont(Future.value(ByteData.view(semiBytes.buffer)));
      await fontLoader.load();
    }
  });

  group('Turkish Characters Font and Typography Tests', () {
    const turkishChars = 'ş Ş ç Ç ğ Ğ ı İ ö Ö ü Ü';

    testWidgets('Fredoka renders all 12 Turkish characters in primary and secondary button styles',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(
                  turkishChars,
                  style: AppTextStyles.primaryButton,
                ),
                Text(
                  turkishChars,
                  style: AppTextStyles.secondaryButton,
                ),
                Text(
                  turkishChars,
                  style: AppTextStyles.screenTitle,
                ),
                Text(
                  turkishChars,
                  style: AppTextStyles.largeResult,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text(turkishChars), findsNWidgets(4));
    });

    testWidgets('SecondaryButton renders with Turkish characters (Adı Değiştir & Çıkış Yap)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SecondaryButton(
                  text: AppStrings.changeNickname,
                  onPressed: () {},
                ),
                SecondaryButton.danger(
                  text: AppStrings.signOut,
                  onPressed: () {},
                ),
                PrimaryButton(
                  text: AppStrings.quickMatch,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.changeNickname), findsOneWidget);
      expect(find.text(AppStrings.signOut), findsOneWidget);
      expect(find.text(AppStrings.quickMatch), findsOneWidget);
    });

    test('TextPainter layouts all Turkish characters with Fredoka without error', () {
      final painter = TextPainter(
        text: const TextSpan(
          text: 'Adı Değiştir - Çıkış Yap: ş Ş ç Ç ğ Ğ ı İ ö Ö ü Ü',
          style: AppTextStyles.secondaryButton,
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      expect(painter.width, greaterThan(0));
      expect(painter.height, greaterThan(0));
      painter.dispose();
    });

    test('Font asset files and license files exist and have non-zero size', () {
      final boldFile = File('assets/fonts/Fredoka-Bold.ttf');
      final semiBoldFile = File('assets/fonts/Fredoka-SemiBold.ttf');
      final origBoldFile = File('assets/fonts/original/Fredoka-Bold.ttf');
      final origSemiBoldFile = File('assets/fonts/original/Fredoka-SemiBold.ttf');
      final oflFile = File('assets/fonts/OFL.txt');

      expect(boldFile.existsSync(), isTrue);
      expect(semiBoldFile.existsSync(), isTrue);
      expect(origBoldFile.existsSync(), isTrue);
      expect(origSemiBoldFile.existsSync(), isTrue);
      expect(oflFile.existsSync(), isTrue);

      expect(boldFile.lengthSync(), greaterThan(45000));
      expect(semiBoldFile.lengthSync(), greaterThan(45000));
      expect(oflFile.lengthSync(), greaterThan(1000));
    });
  });
}
