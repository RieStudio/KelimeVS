import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';

class FakeProfileApiClient implements ProfileApiClient {
  UserProfileModel? mockProfile;
  bool shouldThrow = false;
  void Function()? onAccountDeleted;

  @override
  Future<UserProfileModel?> getProfile() async {
    if (shouldThrow) {
      throw const SocketException('Connection failed');
    }
    return mockProfile;
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);

  @override
  Future<bool> deleteProfile() async => true;
}

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  bool isAuthenticated;

  @override
  String? linkedEmail;

  AuthLinkResult signInResultToReturn;
  bool signInWithGoogleCalled = false;
  bool signOutCalled = false;

  final _controller = StreamController<User?>.broadcast();

  FakeAuthRepository({
    this.isGoogleLinked = true,
    this.isAuthenticated = true,
    this.linkedEmail = 'user@example.com',
    this.signInResultToReturn = const AuthLinkSuccess(email: 'user@example.com'),
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'fake_token';

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
  Future<void> signInAnonymously() async {}

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {}

  @override
  Future<void> signOutAndResetToAnonymous() async {
    signOutCalled = true;
    isAuthenticated = false;
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }

  @override
  Future<AuthLinkResult> reauthenticateGoogle() async => const AuthLinkSuccess();

  @override
  Future<void> deleteFirebaseUser() async {}

  @override
  Future<void> completeAccountDeletionAndReset() async {
    signOutCalled = true;
    isAuthenticated = false;
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestScreen({
    VoidCallback? onComplete,
    AuthRepository? authRepo,
    ProfileApiClient? apiClient,
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo ?? FakeAuthRepository()),
        if (apiClient != null) profileApiClientProvider.overrideWithValue(apiClient),
      ],
      child: MaterialApp(
        home: OnboardingNicknameScreen(onComplete: onComplete),
      ),
    );
  }

  testWidgets('1. Başlangıç durumu (Google ile oturum açık): Başlık, ipucu, e-posta, "Hesabı değiştir" görünür; Google butonu YOK; Devam butonu kapalı', (tester) async {
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

    // Google ile Giriş Yap butonu ARTIK BU EKRANDA YOKTUR
    expect(find.text(AppStrings.signInWithGoogle), findsNothing);

    // Hesap çubuğu: e-posta ve "Hesabı değiştir" bağlantısı mevcut
    expect(find.byKey(const Key('google_linked_no_profile_notice')), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text(AppStrings.switchAccount), findsOneWidget);
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

  testWidgets('4. "Hesabı değiştir" butonu: Tıklandığında onay penceresi açılır; Vazgeç\'e basılınca ekranda kalınır ve signOut çağrılmaz', (tester) async {
    final authRepo = FakeAuthRepository();
    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    // "Hesabı değiştir" bağlantısına tıkla
    await tester.tap(find.byKey(const Key('onboarding_switch_account_button')));
    await tester.pumpAndSettle();

    // Onay penceresi görünür
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppStrings.switchAccountDialogMessage), findsOneWidget);

    // "Vazgeç"e bas
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(authRepo.signOutCalled, isFalse);
    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('5. "Hesabı değiştir" butonu: Onaylandığında signOut çağrılır', (tester) async {
    final authRepo = FakeAuthRepository();
    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding_switch_account_button')));
    await tester.pumpAndSettle();

    // "Hesabı değiştir" onay butonuna tıkla
    await tester.tap(find.byKey(const Key('onboarding_confirm_sign_out_button')));
    await tester.pumpAndSettle();

    expect(authRepo.signOutCalled, isTrue);
  });

  testWidgets('6. Sistem geri tuşu (PopScope): Geri tuşuna basıldığında onay penceresi açılır; Vazgeç\'e basılınca ekranda kalınır', (tester) async {
    final authRepo = FakeAuthRepository();
    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    // Sistem geri tuşunu simüle et
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Çıkış onay penceresi açıldı
    expect(find.text(AppStrings.exitWithoutNicknameDialogTitle), findsOneWidget);
    expect(find.text(AppStrings.exitWithoutNicknameDialogMessage), findsOneWidget);

    // "Vazgeç"e tıkla
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(authRepo.signOutCalled, isFalse);
    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.text(AppStrings.exitWithoutNicknameDialogTitle), findsNothing);
  });

  testWidgets('7. Sistem geri tuşu (PopScope): Onaylandığında signOut çağrılır', (tester) async {
    final authRepo = FakeAuthRepository();
    await tester.pumpWidget(buildTestScreen(authRepo: authRepo));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Çıkış onay butonuna tıkla ("Çık")
    await tester.tap(find.byKey(const Key('onboarding_confirm_sign_out_button')));
    await tester.pumpAndSettle();

    expect(authRepo.signOutCalled, isTrue);
  });

  testWidgets('8. 360 dp genişlik ve 1.3 yazı ölçeğinde uzun e-posta ile taşma (overflow) olmadan çizilir', (tester) async {
    tester.view.physicalSize = const Size(360 * 2.0, 800 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authRepo = FakeAuthRepository(
      linkedEmail: 'cok_uzun_bir_google_hesabi_ve_eposta_adresi_test_icin_olusturuldu_123456789@example.com',
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(1.3),
          size: Size(360, 800),
        ),
        child: buildTestScreen(authRepo: authRepo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.text(AppStrings.switchAccount), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
