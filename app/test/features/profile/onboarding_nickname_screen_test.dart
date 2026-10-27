import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  String? linkedEmail;

  AuthLinkResult signInResultToReturn;
  bool signInWithGoogleCalled = false;

  final _controller = StreamController<User?>.broadcast();

  FakeAuthRepository({
    this.isGoogleLinked = false,
    this.linkedEmail,
    this.signInResultToReturn = const AuthLinkSuccess(email: 'user@example.com'),
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<AuthLinkResult> linkWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<AuthLinkResult> signInWithGoogle() async {
    signInWithGoogleCalled = true;
    if (signInResultToReturn is AuthLinkSuccess) {
      isGoogleLinked = true;
      linkedEmail = (signInResultToReturn as AuthLinkSuccess).email ?? 'user@example.com';
      _controller.add(null);
    }
    return signInResultToReturn;
  }

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {}

  @override
  Future<void> signOutAndResetToAnonymous() async {}

  @override
  Future<AuthLinkResult> reauthenticateGoogle() async => const AuthLinkSuccess();

  @override
  Future<void> deleteFirebaseUser() async {}

  @override
  Future<void> completeAccountDeletionAndReset() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestScreen({
    VoidCallback? onComplete,
    AuthRepository? authRepo,
  }) {
    return ProviderScope(
      overrides: [
        if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: MaterialApp(
        home: OnboardingNicknameScreen(onComplete: onComplete),
      ),
    );
  }

  testWidgets('1. Başlangıç durumu: başlık, ipucu ve devre dışı Devam butonu, Google butonu aktif', (tester) async {
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

    // Google ile Giriş Yap butonu mevcut ve tıklanabilir
    final googleButton = tester.widget<SecondaryButton>(
      find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle),
    );
    expect(googleButton.onPressed, isNotNull);
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

  testWidgets('4. Google ile Giriş: Kullanıcı pencereyi iptal ederse onboarding ekranında kalır ve hata çıkmaz', (tester) async {
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkCanceled(),
    );

    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(authRepo.signInWithGoogleCalled, isTrue);
    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('5. Google ile Giriş: Hata dönerse SnackBar ile hata gösterilir ve onboardingde kalır', (tester) async {
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkError('Google servisine ulaşılamadı'),
    );

    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(authRepo.signInWithGoogleCalled, isTrue);
    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.text('Google servisine ulaşılamadı'), findsOneWidget);
  });

  testWidgets('6. Google ile Giriş başarılı: onComplete veya pop tetiklenir', (tester) async {
    bool completed = false;
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkSuccess(email: 'test@gmail.com'),
    );

    await tester.pumpWidget(buildTestScreen(
      authRepo: authRepo,
      onComplete: () => completed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(authRepo.signInWithGoogleCalled, isTrue);
    expect(completed, isTrue);
  });
}
