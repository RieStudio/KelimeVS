import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';

class FakeRaceAuthRepo implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  String? linkedEmail;

  AuthLinkResult linkResultToReturn = const AuthLinkSuccess(email: 'google@test.com');
  AuthLinkResult signInResultToReturn = const AuthLinkSuccess(email: 'google@test.com');

  final _controller = StreamController<User?>.broadcast();

  FakeRaceAuthRepo({
    this.isGoogleLinked = false,
    this.linkedEmail,
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'test_token';

  @override
  Future<AuthLinkResult> linkWithGoogle() async {
    if (linkResultToReturn is AuthLinkSuccess) {
      isGoogleLinked = true;
      linkedEmail = (linkResultToReturn as AuthLinkSuccess).email ?? 'google@test.com';
      _controller.add(null);
    }
    return linkResultToReturn;
  }

  @override
  Future<AuthLinkResult> signInWithGoogle() async {
    if (signInResultToReturn is AuthLinkSuccess) {
      isGoogleLinked = true;
      linkedEmail = (signInResultToReturn as AuthLinkSuccess).email ?? 'google@test.com';
      _controller.add(null);
    }
    return signInResultToReturn;
  }

  @override
  Future<void> signInAnonymously() async {
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {
    isGoogleLinked = true;
    linkedEmail = 'conflict@test.com';
    _controller.add(null);
  }

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
  Future<void> completeAccountDeletionAndReset() async {
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }
}

class FakeRaceProfileApiClient implements ProfileApiClient {
  final List<Completer<UserProfileModel?>> pendingGetProfileCompleters = [];
  int getProfileCallCount = 0;

  @override
  Future<UserProfileModel?> getProfile() {
    getProfileCallCount++;
    final completer = Completer<UserProfileModel?>();
    pendingGetProfileCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);

  @override
  Future<bool> deleteProfile() async => true;
}

Future<void> waitForPendingRequests(FakeRaceProfileApiClient client, int targetCount) async {
  while (client.pendingGetProfileCompleters.length < targetCount) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthNotifier & ProfileNotifier Eşzamanlı Senkronizasyon (Race Condition) Testleri', () {
    test('1. linkGoogle: Arka planda devam eden misafir senkronu varken bile bağlama sonrası profil günceldir (isGuest=false)', () async {
      final authRepo = FakeRaceAuthRepo(isGoogleLinked: false);
      final apiClient = FakeRaceProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      // Başlangıç: Misafir profili
      const repo = LocalProfileRepository();
      await repo.setNickname('M-1234');
      await repo.setCoins(100);

      // ProfileProvider'ı yükle
      container.read(profileProvider);
      await waitForPendingRequests(apiClient, 1);
      apiClient.pendingGetProfileCompleters[0].complete(
        const UserProfileModel(
          uid: 'anon_uid_1',
          nickname: 'M-1234',
          coins: 100,
          isGuest: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(profileProvider).isGuest, isTrue);
      expect(container.read(profileProvider).nickname, 'M-1234');

      // 1. Yeni bir arka plan senkronizasyonu başlat (ör. periyodik kontrol) ve henüz yanıt dönme
      final bgSyncFuture = container.read(profileProvider.notifier).syncWithServer();
      await waitForPendingRequests(apiClient, 2);

      // 2. Kullanıcı bu sırada Google hesabını bağlıyor (linkGoogle çağrılıyor)
      final linkFuture = container.read(authNotifierProvider.notifier).linkGoogle();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 3. Arka plandaki eski misafir senkronunu tamamla (eski token ile isGuest=true dönüyor)
      apiClient.pendingGetProfileCompleters[1].complete(
        const UserProfileModel(
          uid: 'anon_uid_1',
          nickname: 'M-1234',
          coins: 100,
          isGuest: true,
        ),
      );
      await bgSyncFuture;

      // 4. Eski senkron biter bitmez, force: true olan yeni senkron tetiklenir
      await waitForPendingRequests(apiClient, 3);

      // Yeni Google token'ı ile sunucudan dönen profil (isGuest=false)
      apiClient.pendingGetProfileCompleters[2].complete(
        const UserProfileModel(
          uid: 'anon_uid_1',
          nickname: 'M-1234',
          coins: 100,
          isGuest: false,
        ),
      );

      final linkResult = await linkFuture;

      // 5. Doğrulama: Bağlama başarılı, hesap bağlı ve profil kesinlikle isGuest=false!
      expect(linkResult, isA<AuthLinkSuccess>());
      expect(container.read(authNotifierProvider).isGoogleLinked, isTrue);
      expect(container.read(profileProvider).isGuest, isFalse);
    });

    test('2. signInWithGoogle: Arka planda devam eden misafir senkronu varken bile giriş sonrası profil günceldir (isGuest=false)', () async {
      final authRepo = FakeRaceAuthRepo(isGoogleLinked: false);
      final apiClient = FakeRaceProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      // Başlangıç: Misafir profili
      const repo = LocalProfileRepository();
      await repo.setNickname('M-9999');
      await repo.setCoins(100);

      container.read(profileProvider);
      await waitForPendingRequests(apiClient, 1);
      apiClient.pendingGetProfileCompleters[0].complete(
        const UserProfileModel(
          uid: 'anon_uid_2',
          nickname: 'M-9999',
          coins: 100,
          isGuest: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Arka plan senkronunu başlat ve askıda tut
      final bgSyncFuture = container.read(profileProvider.notifier).syncWithServer();
      await waitForPendingRequests(apiClient, 2);

      // Kullanıcı Google ile Giriş Yapıyor
      authRepo.signInResultToReturn = const AuthLinkSuccess(email: 'player@gmail.com');
      final signInFuture = container.read(authNotifierProvider.notifier).signInWithGoogle();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Eski misafir senkronunu tamamla
      apiClient.pendingGetProfileCompleters[1].complete(
        const UserProfileModel(
          uid: 'anon_uid_2',
          nickname: 'M-9999',
          coins: 100,
          isGuest: true,
        ),
      );
      await bgSyncFuture;

      // loadProfileForSwitchedAccount isteğini yanıtla
      await waitForPendingRequests(apiClient, 3);
      apiClient.pendingGetProfileCompleters[2].complete(
        const UserProfileModel(
          uid: 'google_uid_99',
          nickname: 'GoogleHero',
          coins: 500,
          isGuest: false,
        ),
      );

      // syncWithServer(force: true) isteğini yanıtla
      await waitForPendingRequests(apiClient, 4);
      apiClient.pendingGetProfileCompleters[3].complete(
        const UserProfileModel(
          uid: 'google_uid_99',
          nickname: 'GoogleHero',
          coins: 500,
          isGuest: false,
        ),
      );

      final signInResult = await signInFuture;

      expect(signInResult, isA<AuthLinkSuccess>());
      expect(container.read(authNotifierProvider).isGoogleLinked, isTrue);
      expect(container.read(profileProvider).isGuest, isFalse);
      expect(container.read(profileProvider).nickname, 'GoogleHero');
      expect(container.read(profileProvider).coins, 500);
    });

    test('3. resolveConflict: Arka planda devam eden senkron varken çakışma çözümü sonrası profil günceldir (isGuest=false)', () async {
      final authRepo = FakeRaceAuthRepo(isGoogleLinked: false);
      final apiClient = FakeRaceProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      const repo = LocalProfileRepository();
      await repo.setNickname('M-7777');
      await repo.setCoins(100);

      container.read(profileProvider);
      await waitForPendingRequests(apiClient, 1);
      apiClient.pendingGetProfileCompleters[0].complete(
        const UserProfileModel(
          uid: 'anon_uid_3',
          nickname: 'M-7777',
          coins: 100,
          isGuest: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Arka plan senkronunu başlat ve askıda tut
      final bgSyncFuture = container.read(profileProvider.notifier).syncWithServer();
      await waitForPendingRequests(apiClient, 2);

      // Çakışma çözümü başlat (mevcut Google hesabına geçiş)
      final fakeCredential = GoogleAuthProvider.credential(
        idToken: 'token',
        accessToken: 'access',
      );
      final resolveFuture =
          container.read(authNotifierProvider.notifier).resolveConflict(fakeCredential);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Eski misafir senkronunu tamamla
      apiClient.pendingGetProfileCompleters[1].complete(
        const UserProfileModel(
          uid: 'anon_uid_3',
          nickname: 'M-7777',
          coins: 100,
          isGuest: true,
        ),
      );
      await bgSyncFuture;

      // loadProfileForSwitchedAccount isteğini yanıtla
      await waitForPendingRequests(apiClient, 3);
      apiClient.pendingGetProfileCompleters[2].complete(
        const UserProfileModel(
          uid: 'conflict_uid_77',
          nickname: 'ExistingMaster',
          coins: 350,
          isGuest: false,
        ),
      );

      // syncWithServer(force: true) isteğini yanıtla
      await waitForPendingRequests(apiClient, 4);
      apiClient.pendingGetProfileCompleters[3].complete(
        const UserProfileModel(
          uid: 'conflict_uid_77',
          nickname: 'ExistingMaster',
          coins: 350,
          isGuest: false,
        ),
      );

      await resolveFuture;

      expect(container.read(authNotifierProvider).isGoogleLinked, isTrue);
      expect(container.read(profileProvider).isGuest, isFalse);
      expect(container.read(profileProvider).nickname, 'ExistingMaster');
      expect(container.read(profileProvider).coins, 350);
    });

    test('4. signOut: Arka planda devam eden senkron varken çıkış yapıldığında eski profil verisi oturumu kapatılmış durumu ezmez', () async {
      final authRepo = FakeRaceAuthRepo(isGoogleLinked: true, linkedEmail: 'user@gmail.com');
      final apiClient = FakeRaceProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
          profileApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      const repo = LocalProfileRepository();
      await repo.setNickname('GooglePlayer');
      await repo.setCoins(800);

      container.read(profileProvider);
      await waitForPendingRequests(apiClient, 1);
      apiClient.pendingGetProfileCompleters[0].complete(
        const UserProfileModel(
          uid: 'google_user_1',
          nickname: 'GooglePlayer',
          coins: 800,
          isGuest: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(profileProvider).nickname, 'GooglePlayer');

      // Arka plan senkronu başlat ve askıda tut
      final bgSyncFuture = container.read(profileProvider.notifier).syncWithServer();
      await waitForPendingRequests(apiClient, 2);

      // Çıkış yapılıyor
      final signOutFuture = container.read(authNotifierProvider.notifier).signOut();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Eski senkron tamamlanıyor
      apiClient.pendingGetProfileCompleters[1].complete(
        const UserProfileModel(
          uid: 'google_user_1',
          nickname: 'GooglePlayer',
          coins: 800,
          isGuest: false,
        ),
      );
      await bgSyncFuture;
      await signOutFuture;

      // Çıkış sonrası: takma ad temizlenmiş, Google bağı kalkmış olmalı
      expect(container.read(authNotifierProvider).isGoogleLinked, isFalse);
      expect(container.read(profileProvider).hasNickname, isFalse);
      expect(container.read(profileProvider).nickname, isNull);
    });
  });
}
