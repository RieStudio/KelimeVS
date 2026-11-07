import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/auth/presentation/welcome_screen.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';
import 'package:app/main.dart';

class _TrackingAuthRepo implements AuthRepository {
  bool _isAuthenticated = false;
  int signInAnonymouslyCallCount = 0;
  int signInWithGoogleCallCount = 0;
  int signOutCallCount = 0;
  int completeAccountDeletionCallCount = 0;

  final _controller = StreamController<User?>.broadcast();

  _TrackingAuthRepo({bool initialAuthenticated = false})
      : _isAuthenticated = initialAuthenticated;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool isGoogleLinked = false;

  @override
  String? linkedEmail;

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return _isAuthenticated ? 'valid_test_token' : null;
  }

  @override
  Future<AuthLinkResult> linkWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<AuthLinkResult> signInWithGoogle() async {
    signInWithGoogleCallCount++;
    _isAuthenticated = true;
    isGoogleLinked = true;
    linkedEmail = 'google@test.com';
    _controller.add(null);
    return const AuthLinkSuccess(email: 'google@test.com');
  }

  @override
  Future<void> signInAnonymously() async {
    signInAnonymouslyCallCount++;
    _isAuthenticated = true;
    isGoogleLinked = false;
    _controller.add(null);
  }

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {
    _isAuthenticated = true;
    _controller.add(null);
  }

  @override
  Future<void> signOutAndResetToAnonymous() async {
    signOutCallCount++;
    _isAuthenticated = false;
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
    completeAccountDeletionCallCount++;
    _isAuthenticated = false;
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }
}

class _TrackingProfileApiClient implements ProfileApiClient {
  int getProfileCallCount = 0;
  UserProfileModel? profileToReturn;
  Object? errorToThrow;

  @override
  Future<UserProfileModel?> getProfile() async {
    getProfileCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return profileToReturn;
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      const ProfileUpdateSuccess('M-1234');

  @override
  Future<bool> deleteProfile() async => true;
}

class _TestNetworkNotifier extends NetworkStatusNotifier {
  bool _online;
  _TestNetworkNotifier(this._online);

  void setOnline(bool online) {
    _online = online;
    state = NetworkState(
      status: online ? NetworkStatus.online : NetworkStatus.offline,
      lastProbeTime: DateTime.now(),
    );
  }

  @override
  NetworkState build() => NetworkState(
        status: _online ? NetworkStatus.online : NetworkStatus.offline,
        lastProbeTime: DateTime.now(),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildApp({
    required _TrackingAuthRepo authRepo,
    required _TrackingProfileApiClient apiClient,
    LocalProfileRepository repo = const LocalProfileRepository(),
    bool isOnline = true,
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        profileApiClientProvider.overrideWithValue(apiClient),
        profileRepositoryProvider.overrideWithValue(repo),
        networkStatusProvider.overrideWith(() => _TestNetworkNotifier(isOnline)),
      ],
      child: const MaterialApp(
        home: MainShell(),
      ),
    );
  }

  group('Temiz Kurulum ve Kimlik Akışı Testleri (Otomatik Hesap Oluşturmama)', () {
    testWidgets('1. Temiz kurulum (oturum yok): Welcome görünür, hiçbir anonim giriş ve sunucu isteği yapılmaz', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: false);
      final apiClient = _TrackingProfileApiClient();

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient));
      await tester.pumpAndSettle();

      // WelcomeScreen görünür olmalı
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byKey(const Key('profile_load_error_screen')), findsNothing);

      // Hiçbir Firebase anonim giriş veya sunucu isteği YAPILMAMALIDIR
      expect(authRepo.signInAnonymouslyCallCount, 0);
      expect(apiClient.getProfileCallCount, 0);
    });

    testWidgets('2. Misafir seç: anonim giriş + zorunlu profil senkronu çalışır, M-#### gelince ana sayfaya geçilir', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: false);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'anon_123',
          nickname: 'M-1234',
          coins: 100,
          equippedFrame: 'classic',
          isGuest: true,
        );

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);

      // Misafir butonuna bas
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      // Anonim giriş yapıldı ve sunucudan M-#### yüklendi
      expect(authRepo.signInAnonymouslyCallCount, 1);
      expect(apiClient.getProfileCallCount, greaterThanOrEqualTo(1));

      // Ana sayfaya geçildi
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('3. Google ile ilk giriş: hesaba geçilir, takma ad yoksa OnboardingNicknameScreen açılır', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: false);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'google_user_new',
          nickname: null, // İlk kez Google ile açılan hesapta henüz takma ad yok
          coins: 100,
          isGuest: false,
        );

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient));
      await tester.pumpAndSettle();

      // Google butonuna bas
      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(authRepo.signInWithGoogleCallCount, 1);
      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.widgetWithText(SecondaryButton, AppStrings.signInWithGoogle), findsNothing);
      expect(find.text(AppStrings.switchAccount), findsOneWidget);
      expect(find.text('google@test.com'), findsOneWidget);
    });

    testWidgets('3b. Takma ad ekranından "Hesabı değiştir" onaylanınca signOut çalışır ve WelcomeScreen açılır', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: false);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'google_user_new',
          nickname: null,
          coins: 100,
          isGuest: false,
        );

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingNicknameScreen), findsOneWidget);

      // "Hesabı değiştir" butonuna tıkla
      await tester.tap(find.byKey(const Key('onboarding_switch_account_button')));
      await tester.pumpAndSettle();

      // Onay penceresi görünür
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.switchAccountDialogMessage), findsOneWidget);

      // Onayla
      await tester.tap(find.byKey(const Key('onboarding_confirm_sign_out_button')));
      await tester.pumpAndSettle();

      expect(authRepo.signOutCallCount, 1);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(OnboardingNicknameScreen), findsNothing);
    });

    testWidgets('4. Çıkış yapınca (signOut) WelcomeScreen açılır ve YENİ anonim hesap açılmaz', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: true);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'user_active',
          nickname: 'M-5555',
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.setNickname('M-5555');

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // Çıkış yap
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).signOut();
      await tester.pumpAndSettle();

      // Welcome ekranına dönmeli
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // Otomatik yeni anonim hesap AÇILMAMALIDIR
      expect(authRepo.signOutCallCount, 1);
      expect(authRepo.signInAnonymouslyCallCount, 0);
    });

    testWidgets('5. Hesap silince (deleteAccount) WelcomeScreen açılır ve YENİ anonim hesap açılmaz', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: true);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'user_active',
          nickname: 'M-7777',
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.setNickname('M-7777');

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // Hesap sil
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).deleteAccount();
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      // Otomatik yeni anonim hesap AÇILMAMALIDIR
      expect(authRepo.completeAccountDeletionCallCount, 1);
      expect(authRepo.signInAnonymouslyCallCount, 0);
    });

    testWidgets('6. 410 Tombstone (handleAccountDeletedElsewhere) sonrası WelcomeScreen açılır ve anonim hesap açılmaz', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: true);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'user_active',
          nickname: 'M-8888',
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.setNickname('M-8888');

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // 410 account_deleted tetiklendiğinde
      final container = ProviderScope.containerOf(tester.element(find.byType(MainShell)));
      await container.read(authNotifierProvider.notifier).handleAccountDeletedElsewhere();
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(authRepo.signInAnonymouslyCallCount, 0);
    });

    testWidgets('7. Oturum varken açılış: doğrudan HomeScreen açılır', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: true);
      final apiClient = _TrackingProfileApiClient()
        ..profileToReturn = const UserProfileModel(
          uid: 'user_active',
          nickname: 'M-9999',
          coins: 100,
        );

      const repo = LocalProfileRepository();
      await repo.setNickname('M-9999');

      await tester.pumpWidget(buildApp(authRepo: authRepo, apiClient: apiClient, repo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('8. İnternet yokken misafir butonu hata mesajı verir ve buton tekrar aktif kalır', (tester) async {
      final authRepo = _TrackingAuthRepo(initialAuthenticated: false);
      final apiClient = _TrackingProfileApiClient();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
          networkStatusProvider.overrideWith(() => _TestNetworkNotifier(false)),
        ],
        child: const MaterialApp(
          home: WelcomeScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      // Ağ uyarısı gösterildi (ensureNetworkConnected: noInternetActionError)
      expect(find.text(AppStrings.noInternetActionError), findsOneWidget);

      // Buton kilitli kalmadı, tekrar tıklanabilir
      final guestButton = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest),
      );
      expect(guestButton.onPressed, isNotNull);
      expect(authRepo.signInAnonymouslyCallCount, 0);
    });
  });
}
