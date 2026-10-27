import 'dart:async';
import 'dart:io';

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
    ProfileApiClient? apiClient,
  }) {
    return ProviderScope(
      overrides: [
        if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
        if (apiClient != null) profileApiClientProvider.overrideWithValue(apiClient),
      ],
      child: MaterialApp(
        home: OnboardingNicknameScreen(onComplete: onComplete),
      ),
    );
  }

  testWidgets('1. Başlangıç durumu: başlık, ipucu, devre dışı Devam butonu, Google butonu, alt açıklama ve anonimde bilgi kutusu görünmez', (tester) async {
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

    // Google ile Devam Et butonu ve açıklama metni mevcut
    final googleButton = tester.widget<SecondaryButton>(
      find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle),
    );
    expect(googleButton.onPressed, isNotNull);
    expect(find.text(AppStrings.signInWithGoogleHint), findsOneWidget);

    // Normal anonim yeni kullanıcıda kalıcı Google bilgi kutusu görünmez
    expect(find.byKey(const Key('google_linked_no_profile_notice')), findsNothing);
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

  testWidgets('4. Google ile Devam: Kullanıcı pencereyi iptal ederse onboarding ekranında kalır ve hata çıkmaz', (tester) async {
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

  testWidgets('5. Google ile Devam: Hata dönerse SnackBar ile hata gösterilir ve onboardingde kalır', (tester) async {
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

  testWidgets('6. Google ile Devam (Mevcut Hesap): Sunucuda takma adı olan hesapta onComplete tetiklenir', (tester) async {
    bool completed = false;
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkSuccess(email: 'test@gmail.com'),
    );
    final apiClient = FakeProfileApiClient()
      ..mockProfile = const UserProfileModel(
        uid: 'test_uid',
        nickname: 'EskiKullanici',
        coins: 100,
      );

    await tester.pumpWidget(buildTestScreen(
      authRepo: authRepo,
      apiClient: apiClient,
      onComplete: () => completed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(authRepo.signInWithGoogleCalled, isTrue);
    expect(completed, isTrue);
  });

  testWidgets('7. Google ile Devam (Yeni Hesap): Sunucuda takma adı olmayan hesapta kalıcı bilgi kutusu ve e-posta görünür', (tester) async {
    bool completed = false;
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkSuccess(email: 'yeni@google.com'),
    );
    final apiClient = FakeProfileApiClient()
      ..mockProfile = const UserProfileModel(
        uid: 'test_uid_new',
        nickname: null,
        coins: 100,
      );

    await tester.pumpWidget(buildTestScreen(
      authRepo: authRepo,
      apiClient: apiClient,
      onComplete: () => completed = true,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('google_linked_no_profile_notice')), findsNothing);

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(authRepo.signInWithGoogleCalled, isTrue);
    expect(completed, isFalse);
    expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
    expect(find.byKey(const Key('google_linked_no_profile_notice')), findsOneWidget);
    expect(find.text(AppStrings.googleLinkedNoProfileNotice), findsOneWidget);
    expect(find.text('yeni@google.com'), findsOneWidget);
  });

  testWidgets('8. Yeni Google hesabı bağlandıktan sonra geçerli takma ad girilip devam edilince kaydedilir', (tester) async {
    bool completed = false;
    final authRepo = FakeAuthRepository(
      signInResultToReturn: const AuthLinkSuccess(email: 'yeni@google.com'),
    );
    final apiClient = FakeProfileApiClient()
      ..mockProfile = const UserProfileModel(
        uid: 'test_uid_new',
        nickname: null,
        coins: 100,
      );

    await tester.pumpWidget(buildTestScreen(
      authRepo: authRepo,
      apiClient: apiClient,
      onComplete: () => completed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('google_linked_no_profile_notice')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'GoogleOyuncu');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.continueAction));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    const repo = LocalProfileRepository();
    expect(await repo.getNickname(), 'GoogleOyuncu');
  });
}
