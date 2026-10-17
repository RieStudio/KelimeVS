import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Mehmet',
    });
  });

  Widget buildTestScreen() {
    return const ProviderScope(
      child: MaterialApp(
        home: ProfileScreen(),
      ),
    );
  }

  testWidgets('1. Profil ekranı: Başlık, mevcut takma ad ve Adı Değiştir butonu görüntülenir', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileTitle), findsOneWidget);
    expect(find.text('Mehmet'), findsOneWidget);
    expect(find.text('M'), findsOneWidget); // Avatar initial
    expect(find.text(AppStrings.changeNickname), findsOneWidget);
  });

  testWidgets('2. "Adı Değiştir" butonuna basılınca diyalog açılır ve yeni geçerli ad kaydedilir', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.changeNickname));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.newNicknamePrompt), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Geçersiz ad gir (küfür)
    await tester.enterText(find.byType(TextField), 'salak');
    await tester.pumpAndSettle();

    expect(find.text('Bu takma ad uygunsuz ifadeler içeriyor.'), findsOneWidget);
    var saveButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.save),
    );
    expect(saveButton.onPressed, isNull);

    // Geçerli yeni ad gir
    await tester.enterText(find.byType(TextField), 'Baris_34');
    await tester.pumpAndSettle();

    saveButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.save),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.save));
    await tester.pumpAndSettle();

    // Diyalog kapanmalı ve ekranda yeni ad görünmeli
    expect(find.text(AppStrings.newNicknamePrompt), findsNothing);
    expect(find.text('Baris_34'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    // Depoyu doğrula
    const repo = LocalProfileRepository();
    final updated = await repo.getNickname();
    expect(updated, 'Baris_34');
  });
}
