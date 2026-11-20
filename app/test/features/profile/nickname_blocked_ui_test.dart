import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/onboarding_nickname_screen.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';

class BlockedFakeProfileApiClient implements ProfileApiClient {
  @override
  void Function()? onAccountDeleted;

  @override
  Future<UserProfileModel?> getProfile() async => UserProfileModel(
        uid: 'user_test_blocked',
        nickname: 'EskiAd',
        coins: 100,
        stats: const UserStats(
          played: 1,
          won: 1,
          lost: 0,
          correctAnswers: 5,
        ),
        equippedFrame: 'classic',
        isGuest: false,
      );

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async {
    return const ProfileUpdateBlockedNickname(AppStrings.nicknameBlockedError);
  }

  @override
  Future<bool> deleteProfile() async => true;

  @override
  Future<bool> updateAllowMatchRequests(bool allow) async => true;
}

class FakeProfileRepository implements ProfileRepository {
  String? _nickname;
  int _coins = 100;
  bool _syncPending = false;
  String _equippedFrame = 'classic';
  bool _allowMatchRequests = true;

  FakeProfileRepository({String? initialNickname, int initialCoins = 100})
      : _nickname = initialNickname,
        _coins = initialCoins;

  @override
  Future<String?> getNickname() async => _nickname;

  @override
  Future<void> setNickname(String nickname) async {
    _nickname = nickname.trim();
  }

  @override
  Future<bool> hasNickname() async => _nickname != null && _nickname!.isNotEmpty;

  @override
  Future<int> getCoins({int defaultCoins = 100}) async => _coins;

  @override
  Future<void> setCoins(int coins) async {
    _coins = coins;
  }

  @override
  Future<bool> isNicknameSyncPending() async => _syncPending;

  @override
  Future<void> setNicknameSyncPending(bool pending) async {
    _syncPending = pending;
  }

  @override
  Future<String> getEquippedFrame({String defaultFrame = 'classic'}) async =>
      _equippedFrame;

  @override
  Future<void> setEquippedFrame(String frameId) async {
    _equippedFrame = frameId;
  }

  @override
  Future<bool> getAllowMatchRequests({bool defaultValue = true}) async =>
      _allowMatchRequests;

  @override
  Future<void> setAllowMatchRequests(bool allow) async {
    _allowMatchRequests = allow;
  }

  @override
  Future<void> clearAll() async {
    _nickname = null;
    _syncPending = false;
  }

  @override
  Future<void> clear({String? uid}) async {
    _nickname = null;
    _syncPending = false;
  }

  @override
  Future<UserStats> getStats({String? uid}) async => const UserStats(
        played: 1,
        won: 1,
        lost: 0,
        correctAnswers: 5,
      );

  @override
  Future<void> setStats(String uid, UserStats stats) async {}
}

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked = true;

  @override
  bool isAuthenticated = true;

  @override
  String? linkedEmail = 'test@example.com';

  final _controller = StreamController<User?>.broadcast();

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'dummy_token';

  @override
  Future<AuthLinkResult> linkWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<AuthLinkResult> signInWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<void> signInAnonymously() async {}

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

  group('Nickname Blocked - UI & Notifier Tests', () {
    testWidgets('1. OnboardingNicknameScreen: Sunucu nickname_blocked döndüğünde ekranda satır içi "Bu takma ad kullanılamaz" uyarısı gösterilir ve sayfa kapanmaz', (tester) async {
      bool completedCalled = false;
      final fakeApiClient = BlockedFakeProfileApiClient();
      final fakeAuth = FakeAuthRepository();
      final fakeRepo = FakeProfileRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            profileApiClientProvider.overrideWithValue(fakeApiClient),
            profileRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: OnboardingNicknameScreen(
              onComplete: () {
                completedCalled = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Takma ad gir
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, 'Kotukelime');
      await tester.pumpAndSettle();

      // Devam butonuna tıkla
      final continueButton = find.widgetWithText(PrimaryButton, AppStrings.continueAction);
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Ekran tamamlanmamalı (onComplete çağrılmamalı)
      expect(completedCalled, isFalse);

      // Ekranda satır içi "Bu takma ad kullanılamaz" uyarısı görünmeli
      expect(find.text(AppStrings.nicknameBlockedError), findsOneWidget);
    });

    testWidgets('2. ProfileScreen Dialog: Takma ad değiştirme sırasında sunucu nickname_blocked döndüğünde pencere açık kalır ve "Bu takma ad kullanılamaz" uyarısı gösterilir', (tester) async {
      final fakeApiClient = BlockedFakeProfileApiClient();
      final fakeAuth = FakeAuthRepository();
      final fakeRepo = FakeProfileRepository(initialNickname: 'EskiAd');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            profileApiClientProvider.overrideWithValue(fakeApiClient),
            profileRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Adı Değiştir" butonuna tıkla
      final changeNickButton = find.text('Adı Değiştir');
      expect(changeNickButton, findsOneWidget);
      await tester.tap(changeNickButton);
      await tester.pumpAndSettle();

      // Dialog açık
      expect(find.byType(Dialog), findsOneWidget);

      // Yeni ad gir
      final dialogInput = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogInput, 'Kotukelime');
      await tester.pumpAndSettle();

      // Kaydet butonuna tıkla
      final saveButton = find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(PrimaryButton, AppStrings.save),
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Dialog açık kalmalı
      expect(find.byType(Dialog), findsOneWidget);

      // Dialog içinde satır içi "Bu takma ad kullanılamaz" uyarısı görünmeli
      expect(find.text(AppStrings.nicknameBlockedError), findsOneWidget);
    });

    test('3. ProfileNotifier: ProfileUpdateBlockedNickname alındığında yerel ad eski haline döner, pending sync false kalır ve hata fırlatılır', () async {
      final fakeRepo = FakeProfileRepository(initialNickname: 'EskiAd');
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          profileApiClientProvider.overrideWithValue(BlockedFakeProfileApiClient()),
          profileRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).syncWithServer();
      expect(container.read(profileProvider).nickname, 'EskiAd');

      // Uygunsuz takma ad güncellemesi çağrısı
      expect(
        () => container.read(profileProvider.notifier).setNickname('UygunsuzKelime'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains(AppStrings.nicknameBlockedError),
        )),
      );

      // Takma ad önceki geçerli haline döndürülmüş olmalı
      expect(container.read(profileProvider).nickname, 'EskiAd');

      // Bekleyen eşitleme bayrağı false olmalı
      expect(await fakeRepo.isNicknameSyncPending(), isFalse);
    });
  });
}
