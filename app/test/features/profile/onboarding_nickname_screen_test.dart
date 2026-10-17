import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestScreen({VoidCallback? onComplete}) {
    return ProviderScope(
      child: MaterialApp(
        home: OnboardingNicknameScreen(onComplete: onComplete),
      ),
    );
  }

  testWidgets('1. Başlangıç durumu: başlık, ipucu ve devre dışı Devam butonu', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.welcomeTitle), findsOneWidget);
    expect(find.text(AppStrings.welcomePrompt), findsOneWidget);
    expect(find.text(AppStrings.nicknameRuleHint), findsOneWidget);
    expect(find.text('0/16'), findsOneWidget);

    final continueButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.continueAction),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('2. Geçersiz girdi (kısa ya da küfür): hata mesajı görünür ve Devam butonu kapalı kalır', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    // 2 karakterli girdi
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pumpAndSettle();

    expect(find.text('Takma ad en az 3 karakter olmalıdır.'), findsOneWidget);
    expect(find.text('2/16'), findsOneWidget);
    var continueButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.continueAction),
    );
    expect(continueButton.onPressed, isNull);

    // Küfürlü girdi
    await tester.enterText(find.byType(TextField), 'aptal_oyuncu');
    await tester.pumpAndSettle();

    expect(find.text('Bu takma ad uygunsuz ifadeler içeriyor.'), findsOneWidget);
    continueButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.continueAction),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('3. Geçerli girdi: Devam butonu aktif olur ve basılınca kaydedilir', (tester) async {
    bool completed = false;
    await tester.pumpWidget(buildTestScreen(onComplete: () {
      completed = true;
    }));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Zeynep_01  ');
    await tester.pumpAndSettle();

    expect(find.text('13/16'), findsOneWidget);
    final continueButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.continueAction),
    );
    expect(continueButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.continueAction));
    await tester.pumpAndSettle();

    expect(completed, isTrue);

    // Depoyu kontrol et
    const repo = LocalProfileRepository();
    final saved = await repo.getNickname();
    expect(saved, 'Zeynep_01');
  });
}
