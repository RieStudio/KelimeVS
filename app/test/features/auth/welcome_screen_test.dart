import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/auth/presentation/welcome_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';

class FakeWelcomeAuthRepo implements AuthRepository {
  @override
  bool isGoogleLinked = false;

  @override
  String? linkedEmail;

  bool signInAnonymouslyCalled = false;
  bool signInWithGoogleCalled = false;
  AuthLinkResult googleResultToReturn = const AuthLinkSuccess(email: 'user@google.com');
  Completer<void>? signInCompleter;
  Object? errorToThrowOnSignInAnonymously;

  final _controller = StreamController<User?>.broadcast();

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'fake_token';

  @override
  Future<void> signInAnonymously() async {
    if (errorToThrowOnSignInAnonymously != null) {
      throw errorToThrowOnSignInAnonymously!;
    }
    signInAnonymouslyCalled = true;
    if (signInCompleter != null) {
      await signInCompleter!.future;
    }
    _controller.add(null);
  }

  @override
  Future<AuthLinkResult> signInWithGoogle() async {
    signInWithGoogleCalled = true;
    if (googleResultToReturn is AuthLinkSuccess) {
      isGoogleLinked = true;
      linkedEmail = (googleResultToReturn as AuthLinkSuccess).email;
      _controller.add(null);
    }
    return googleResultToReturn;
  }

  @override
  Future<AuthLinkResult> linkWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {}

  @override
  Future<void> signOutAndResetToAnonymous() async {
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }

  @override
  Future<AuthLinkResult> reauthenticateGoogle() async => const AuthLinkSuccess();

  @override
  Future<void> deleteFirebaseUser() async {}

  @override
  Future<void> completeAccountDeletionAndReset() async {}
}

class FakeWelcomeProfileApiClient implements ProfileApiClient {
  UserProfileModel? mockProfile;
  bool shouldThrow = false;
  Object? errorToThrow;

  @override
  Future<UserProfileModel?> getProfile() async {
    if (shouldThrow) {
      throw errorToThrow ?? Exception('Ağ hatası');
    }
    return mockProfile;
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);

  @override
  Future<bool> deleteProfile() async => true;
}

class _TestNetworkNotifier extends NetworkStatusNotifier {
  final bool _online;
  _TestNetworkNotifier(this._online);

  @override
  NetworkState build() => NetworkState(
        status: _online ? NetworkStatus.online : NetworkStatus.offline,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildWelcomeScreen({
    FakeWelcomeAuthRepo? authRepo,
    FakeWelcomeProfileApiClient? apiClient,
    bool isOnline = true,
    VoidCallback? onComplete,
  }) {
    return ProviderScope(
      overrides: [
        if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
        if (apiClient != null) profileApiClientProvider.overrideWithValue(apiClient),
        networkStatusProvider.overrideWith(() => _TestNetworkNotifier(isOnline)),
      ],
      child: MaterialApp(
        home: WelcomeScreen(onComplete: onComplete),
      ),
    );
  }

  group('WelcomeScreen (Giriş / Karşılama Ekranı) Testleri', () {
    testWidgets('1. Giriş ekranında takma ad giriş alanı (TextField) YOKTUR', (tester) async {
      await tester.pumpWidget(buildWelcomeScreen());
      await tester.pumpAndSettle();

      // Takma ad TextField'ı KESİNLİKLE bulunmamalıdır!
      expect(find.byType(TextField), findsNothing);
      expect(find.text(AppStrings.welcomeTitle), findsOneWidget);
      expect(find.text(AppStrings.slogan), findsOneWidget);
    });

    testWidgets('2. İki buton bulunur ve bilgilendirme kartı tamamen kaldırılmıştır', (tester) async {
      await tester.pumpWidget(buildWelcomeScreen());
      await tester.pumpAndSettle();

      // Google ile Giriş Yap (PrimaryButton)
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle),
        findsOneWidget,
      );

      // Misafir Olarak Devam Et (SecondaryButton)
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest),
        findsOneWidget,
      );

      // Açıklama kartı KESİNLİKLE kaldırılmış olmalıdır!
      expect(find.byKey(const Key('welcome_guest_notice_card')), findsNothing);
    });

    testWidgets('3. Misafir Olarak Devam Et: Firebase anonim girişi tetiklenir, M-#### senkronlanır ve OnboardingNicknameScreen açılmaz', (tester) async {
      final authRepo = FakeWelcomeAuthRepo();
      final apiClient = FakeWelcomeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'anon_123',
          nickname: 'M-4821', // Sunucudan otomatik M-#### adı geldi
          coins: 100,
          isGuest: true,
        );

      bool completedCalled = false;
      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
        apiClient: apiClient,
        onComplete: () => completedCalled = true,
      ));
      await tester.pumpAndSettle();

      // Misafir butonuna bas
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      // Anonim oturum başlatıldı
      expect(authRepo.signInAnonymouslyCalled, isTrue);
      // OnboardingNicknameScreen kesinlikle görünmemeli
      expect(find.byType(OnboardingNicknameScreen), findsNothing);
      // onComplete tetiklendi
      expect(completedCalled, isTrue);

      // Depoya da M-#### adı kaydedildi
      const repo = LocalProfileRepository();
      expect(await repo.getNickname(), 'M-4821');
    });

    testWidgets('4. Misafir girişi sırasında loading gösterilir ve çift tıklama engellenir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo();
      final completer = Completer<void>();
      authRepo.signInCompleter = completer;

      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
      ));
      await tester.pumpAndSettle();

      // Butona tıkla
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pump();

      // Loading göstergesi görünür
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // İşlem devam ederken butonlar pasif olmalı (onPressed: null)
      final primary = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle),
      );
      expect(primary.onPressed, isNull);

      final secondary = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest),
      );
      expect(secondary.onPressed, isNull);

      // Completer'ı bitir
      completer.complete();
      await tester.pumpAndSettle();

      // Loading kalktı
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('5. Ağ bağlantısı yokken misafir butonuna basılırsa işlem yapılmaz ve ağ uyarısı gösterilir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo();

      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
        isOnline: false,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      // İşlem başlamamalı
      expect(authRepo.signInAnonymouslyCalled, isFalse);
      expect(find.text(AppStrings.noInternetActionError), findsOneWidget);
    });

    testWidgets('6. Google ile Giriş Yap akışı: Başarılı girişte adı olan kullanıcı doğrudan tamamlanır', (tester) async {
      final authRepo = FakeWelcomeAuthRepo();
      final apiClient = FakeWelcomeProfileApiClient()
        ..mockProfile = const UserProfileModel(
          uid: 'google_user_1',
          nickname: 'GoogleKral',
          coins: 500,
          isGuest: false,
        );

      bool completedCalled = false;
      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
        apiClient: apiClient,
        onComplete: () => completedCalled = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(authRepo.signInWithGoogleCalled, isTrue);
      expect(completedCalled, isTrue);
    });

    testWidgets('7. Google ile Giriş Yap hata senaryosu: SnackBar gösterilir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo()
        ..googleResultToReturn = const AuthLinkError('Google servisine ulaşılamadı');

      await tester.pumpWidget(buildWelcomeScreen(authRepo: authRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.signInWithGoogle));
      await tester.pumpAndSettle();

      expect(find.text('Google servisine ulaşılamadı'), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('8. Sunucu profil yükleme hatasında (profil boş/senkron başarısız) serverProfileLoadError mesajı gösterilir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo();
      final apiClient = FakeWelcomeProfileApiClient()
        ..mockProfile = null; // Sunucudan profil gelmedi

      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
        apiClient: apiClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.serverProfileLoadError), findsOneWidget);
    });

    testWidgets('9. Ağ istisnasında (SocketException) networkError mesajı gösterilir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo()
        ..errorToThrowOnSignInAnonymously = const SocketException('Bağlantı koptu');

      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.networkError), findsOneWidget);
    });

    testWidgets('10. Auth servis hatasında (FirebaseAuthException) authServiceError mesajı gösterilir', (tester) async {
      final authRepo = FakeWelcomeAuthRepo()
        ..errorToThrowOnSignInAnonymously = FirebaseAuthException(
          code: 'service-unavailable',
          message: 'Auth service down',
        );

      await tester.pumpWidget(buildWelcomeScreen(
        authRepo: authRepo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.continueAsGuest));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authServiceError), findsOneWidget);
    });
  });
}
