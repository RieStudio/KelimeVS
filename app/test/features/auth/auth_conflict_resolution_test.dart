import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';
import 'package:app/features/store/application/store_notifier.dart';
import 'package:app/main.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  String? linkedEmail;

  AuthLinkResult linkResultToReturn;
  AuthLinkResult signInResultToReturn = const AuthLinkSuccess(email: 'user@example.com');
  bool signInWithConflictCalled = false;
  bool signInWithGoogleCalled = false;
  bool signOutCalled = false;
  bool completeAccountDeletionCalled = false;

  final _controller = StreamController<User?>.broadcast();

  FakeAuthRepository({
    this.isGoogleLinked = false,
    this.linkedEmail,
    this.linkResultToReturn = const AuthLinkCanceled(),
    this.signInResultToReturn = const AuthLinkSuccess(email: 'user@example.com'),
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<AuthLinkResult> linkWithGoogle() async => linkResultToReturn;

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
  Future<void> signInWithConflictCredential(AuthCredential credential) async {
    signInWithConflictCalled = true;
    isGoogleLinked = true;
    linkedEmail = 'conflict@example.com';
    _controller.add(null);
  }

  @override
  Future<void> signOutAndResetToAnonymous() async {
    signOutCalled = true;
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
    completeAccountDeletionCalled = true;
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createTestApp({
    required FakeAuthRepository authRepo,
    required FakeProfileApiClient apiClient,
    LocalProfileRepository repo = const LocalProfileRepository(),
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        profileApiClientProvider.overrideWithValue(apiClient),
        profileRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: MainShell(),
      ),
    );
  }

  group('Google Hesap Çakışması (resolveConflict) & Profil Yükleme Testleri', () {
    testWidgets('1. Mevcut hesaba geçiş (Takma ad var): OnboardingNicknameScreen ÇIKMAZ, doğrudan ana ekran açılır', (tester) async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_user_1',
          nickname: 'BulutOyuncu',
          coins: 500,
          equippedFrame: 'gold',
          stats: UserStats(played: 25, won: 18, lost: 7, correctAnswers: 80),
        );

      const repo = LocalProfileRepository();
      // Başlangıçta cihazda anonim takma ad var
      await repo.setNickname('EskiAnonim');

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      // Başlangıçta ana ekran görünür
      expect(find.byType(HomeScreen), findsOneWidget);

      // Çakışmayı çöz
      final cred = GoogleAuthProvider.credential(idToken: 'token_abc');
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).resolveConflict(cred);
      await tester.pumpAndSettle();

      // KRİTİK: OnboardingNicknameScreen HİÇ ÇIKMAMALI!
      expect(find.byType(OnboardingNicknameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      // Profil durumu güncellenmiş olmalı
      final profile = container.read(profileProvider);
      expect(profile.nickname, 'BulutOyuncu');
      expect(profile.coins, 500);
      expect(profile.equippedFrame, 'gold');
      expect(profile.stats.played, 25);
      expect(profile.stats.correctAnswers, 80);
      expect(profile.hasNickname, isTrue);

      // Depodaki takma ad da güncellenmeli
      expect(await repo.getNickname(), 'BulutOyuncu');
    });

    testWidgets('2. Meşru Onboarding: Sunucuda takma adı null olan Google hesabı için OnboardingNicknameScreen açılır', (tester) async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_new_user',
          nickname: null, // Sunucuda takma ad meşru olarak boş
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.setNickname('EskiAnonim');

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      final cred = GoogleAuthProvider.credential(idToken: 'token_new');
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).resolveConflict(cred);
      await tester.pumpAndSettle();

      // Sunucudan profil başarıyla alındı ama ad yok -> Meşru Onboarding
      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
      expect(find.byKey(const Key('profile_load_error_screen')), findsNothing);
    });

    testWidgets('3. Sunucu/Ağ Hatası: OnboardingNicknameScreen ASLA ÇIKMAZ; Tekrar Dene ekranı gösterilir ve retry ile kurtarılır', (tester) async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      final apiClient = FakeProfileApiClient()..shouldThrow = true; // Ağ hatası simülasyonu

      const repo = LocalProfileRepository();
      await repo.setNickname('EskiAnonim');

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      final cred = GoogleAuthProvider.credential(idToken: 'token_fail');
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).resolveConflict(cred);
      await tester.pumpAndSettle();

      // KRİTİK ŞART 1: Ağ hatasında OnboardingNicknameScreen ASLA gösterilmemeli!
      expect(find.byType(OnboardingNicknameScreen), findsNothing);

      // "Profil yüklenemedi, tekrar dene" ekranı gösterilmeli
      expect(find.byKey(const Key('profile_load_error_screen')), findsOneWidget);
      expect(find.text(AppStrings.profileLoadErrorTitle), findsOneWidget);
      expect(find.text(AppStrings.profileLoadErrorMessage), findsOneWidget);
      expect(find.byKey(const Key('profile_load_retry_button')), findsOneWidget);

      // Şimdi ağ düzeldi ve sunucu profili başarıyla döndürdü
      apiClient.shouldThrow = false;
      apiClient.mockProfile = const UserProfileModel(
        uid: 'google_recovered_user',
        nickname: 'KurtarilanOyuncu',
        coins: 250,
      );

      // "Tekrar Dene"ye bas
      await tester.tap(find.byKey(const Key('profile_load_retry_button')));
      await tester.pumpAndSettle();

      // Hata ekranı kaybolmalı, takma ad ekranına düşmeden doğrudan ana ekrana geçilmeli
      expect(find.byKey(const Key('profile_load_error_screen')), findsNothing);
      expect(find.byType(OnboardingNicknameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      final profile = container.read(profileProvider);
      expect(profile.nickname, 'KurtarilanOyuncu');
      expect(profile.coins, 250);
      expect(profile.hasNickname, isTrue);
    });

    testWidgets('4. 410 Tombstone (account_deleted): onAccountDeleted tetiklenir ve sıfırlanır', (tester) async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      bool accountDeletedCalled = false;

      final apiClient = FakeProfileApiClient();
      apiClient.onAccountDeleted = () {
        accountDeletedCalled = true;
      };

      const repo = LocalProfileRepository();
      await repo.setNickname('EskiAnonim');

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // 410 geldiğinde onAccountDeleted çağrılmalı
      apiClient.onAccountDeleted!();
      expect(accountDeletedCalled, isTrue);
    });

    testWidgets('5. Önbellek İzolasyonu: Eski anonim kullanıcının istatistikleri ve takma adı yeni hesaba sızmaz', (tester) async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_user_clean',
          nickname: 'TemizGoogle',
          coins: 100,
          stats: UserStats(played: 2, won: 1, lost: 1, correctAnswers: 6),
        );

      const repo = LocalProfileRepository();
      // Eski anonim kullanıcının verileri
      await repo.setNickname('KirliAnonim');
      await repo.setStats('anon_uid', const UserStats(played: 99, won: 90, lost: 9, correctAnswers: 500));

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final cred = GoogleAuthProvider.credential(idToken: 'token_clean');
      await container.read(authNotifierProvider.notifier).resolveConflict(cred);

      // Yeni kullanıcının istatistikleri ve takma adı doğru olmalı
      final profile = container.read(profileProvider);
      expect(profile.nickname, 'TemizGoogle');
      expect(profile.stats.played, 2);
      expect(profile.stats.correctAnswers, 6);

      // Eski anonim kullanıcının istatistikleri depodan silinmiş olmalı
      final anonStats = await repo.getStats(uid: 'anon_uid');
      expect(anonStats.played, 0);
      expect(anonStats.correctAnswers, 0);
    });

    test('6. Bağımlı Provider İzolasyonu: leaderboard, store ve onlineMatchSession invalidate edilir', () async {
      final authRepo = FakeAuthRepository(isGoogleLinked: false);
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_fresh',
          nickname: 'FreshPlayer',
          coins: 200,
        );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      // Provider'ları oku
      final storeInitial = container.read(storeNotifierProvider);
      expect(storeInitial, isNotNull);

      final cred = GoogleAuthProvider.credential(idToken: 'token_fresh');
      await container.read(authNotifierProvider.notifier).resolveConflict(cred);

      // Profil başarıyla yüklendi
      expect(container.read(profileProvider).nickname, 'FreshPlayer');
      expect(authRepo.signInWithConflictCalled, isTrue);
    });

    testWidgets('7. Onboarding ekranından signInWithGoogle: Mevcut hesaba geçiş (takma ad var) doğrudan HomeScreen açar', (tester) async {
      final authRepo = FakeAuthRepository(
        isGoogleLinked: false,
        signInResultToReturn: const AuthLinkSuccess(email: 'existing@google.com'),
      );
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(uid: 'anon_user', nickname: null, coins: 100);

      const repo = LocalProfileRepository();
      await repo.clear();

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // Google ile giriş yapıldığında sunucudaki Google profili gelir
      apiClient.mockProfile = const UserProfileModel(
        uid: 'google_user_existing',
        nickname: 'GoogleKral',
        coins: 750,
      );

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      expect(container.read(profileProvider).nickname, 'GoogleKral');
      expect(container.read(profileProvider).coins, 750);
      expect(authRepo.signInWithGoogleCalled, isTrue);
    });

    testWidgets('8. Onboarding ekranından signInWithGoogle: Sunucuda takma adı null olan yeni hesap Onboardingde kalır', (tester) async {
      final authRepo = FakeAuthRepository(
        isGoogleLinked: false,
        signInResultToReturn: const AuthLinkSuccess(email: 'brandnew@google.com'),
      );
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_user_new',
          nickname: null,
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.clear();

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(authRepo.signInWithGoogleCalled, isTrue);
      expect(authRepo.isGoogleLinked, isTrue);
    });

    testWidgets('9. Onboarding ekranından signInWithGoogle: Sunucu hatasında Onboarding yerine Hata/Tekrar Dene ekranı açılır', (tester) async {
      final authRepo = FakeAuthRepository(
        isGoogleLinked: false,
        signInResultToReturn: const AuthLinkSuccess(email: 'error@google.com'),
      );
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(uid: 'anon_user', nickname: null, coins: 100);

      const repo = LocalProfileRepository();
      await repo.clear();

      await tester.pumpWidget(createTestApp(
        authRepo: authRepo,
        apiClient: apiClient,
        repo: repo,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);

      // Google ile giriş anında sunucu hatası alınıyor
      apiClient.shouldThrow = true;

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsNothing);
      expect(find.byKey(const Key('profile_load_error_screen')), findsOneWidget);

      apiClient.shouldThrow = false;
      apiClient.mockProfile = const UserProfileModel(
        uid: 'google_recovered',
        nickname: 'KurtarilanKullanici',
        coins: 300,
      );

      await tester.tap(find.byKey(const Key('profile_load_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingNicknameScreen), findsNothing);
    });

    test('10. signInWithGoogle: Bağımlı providerlar ve eski depolar temizlenir', () async {
      final authRepo = FakeAuthRepository(
        isGoogleLinked: false,
        signInResultToReturn: const AuthLinkSuccess(email: 'fresh@google.com'),
      );
      final apiClient = FakeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_fresh',
          nickname: 'FreshNick',
          coins: 200,
        );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      final storeInitial = container.read(storeNotifierProvider);
      expect(storeInitial, isNotNull);

      await container.read(authNotifierProvider.notifier).signInWithGoogle();

      expect(container.read(profileProvider).nickname, 'FreshNick');
      expect(authRepo.signInWithGoogleCalled, isTrue);
    });
  });
}
