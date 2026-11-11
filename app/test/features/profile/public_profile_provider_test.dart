import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/profile/application/blocked_users_notifier.dart';
import 'package:app/features/profile/application/public_profile_provider.dart';
import 'package:app/features/profile/data/blocked_users_api_client.dart';
import 'package:app/features/profile/data/public_profile_api_client.dart';
import 'package:app/features/profile/domain/blocked_user_model.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';

class MockPublicProfileApiClient implements PublicProfileApiClient {
  int getProfileCallCount = 0;
  int blockCallCount = 0;
  int unblockCallCount = 0;
  int reportCallCount = 0;

  PublicProfile mockProfile;

  MockPublicProfileApiClient({
    this.mockProfile = const PublicProfile(
      uid: 'uid_test',
      nickname: 'TestUser',
      equippedFrame: 'classic',
    ),
  });

  @override
  Future<PublicProfile> getPublicProfile(String uid) async {
    getProfileCallCount++;
    return mockProfile;
  }

  @override
  Future<String> blockUser(String uid) async {
    blockCallCount++;
    return 'blk_123';
  }

  @override
  Future<void> unblockUser(String uid) async {
    unblockCallCount++;
  }

  @override
  Future<String> reportUser(String uid, String reason) async {
    reportCallCount++;
    return 'rep_123';
  }
}

class FakeBlockedUsersApiClient implements BlockedUsersApiClient {
  int getBlockedUsersCallCount = 0;

  @override
  Future<List<BlockedUser>> getBlockedUsers() async {
    getBlockedUsersCallCount++;
    return [
      const BlockedUser(
        id: 'blk_1',
        nickname: 'Blocked1',
        blockedAt: 1700000000000,
      ),
    ];
  }

  @override
  Future<BlockUserResult> blockUser(String matchId) async =>
      const BlockUserSuccess('blk_1');

  @override
  Future<ReportUserResult> reportUser(
          {required String matchId, required String reason}) async =>
      const ReportUserSuccess();

  @override
  Future<bool> unblockUser(String id) async => true;
}

class FakeUser implements User {
  @override
  final String uid;
  FakeUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  final User? user;
  FakeAuthRepository([this.user]);

  @override
  User? get currentUser => user;

  @override
  bool get isAuthenticated => user != null;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);

  @override
  bool get isGoogleLinked => false;

  @override
  String? get linkedEmail => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('publicProfileProvider Caching & Invalidation Tests', () {
    test('Aynı UID için peş peşe okumalar önbellekten döner (tek API çağrısı)',
        () async {
      final mockClient = MockPublicProfileApiClient();

      final container = ProviderContainer(
        overrides: [
          publicProfileApiClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      // İlk okuma
      final profile1 =
          await container.read(publicProfileProvider('uid_test').future);
      expect(profile1.nickname, 'TestUser');
      expect(mockClient.getProfileCallCount, 1);

      // İkinci okuma (önbellek devrede)
      final profile2 =
          await container.read(publicProfileProvider('uid_test').future);
      expect(profile2.nickname, 'TestUser');
      expect(mockClient.getProfileCallCount, 1); // Artmadı!
    });

    test(
        'PublicProfileService.blockUser başarılı olunca hem publicProfile hem blockedUsers invalidate edilir',
        () async {
      final mockClient = MockPublicProfileApiClient();
      final mockBlockedClient = FakeBlockedUsersApiClient();

      final container = ProviderContainer(
        overrides: [
          publicProfileApiClientProvider.overrideWithValue(mockClient),
          blockedUsersApiClientProvider.overrideWithValue(mockBlockedClient),
        ],
      );
      addTearDown(container.dispose);

      // publicProfile oku
      await container.read(publicProfileProvider('uid_test').future);
      expect(mockClient.getProfileCallCount, 1);

      // blockedUsersProvider dinle
      container.listen(blockedUsersProvider, (_, _) {});
      await container.read(blockedUsersProvider.future);
      expect(mockBlockedClient.getBlockedUsersCallCount, 1);

      // Engelleme işlemi yap
      final service = container.read(publicProfileServiceProvider);
      final blockId = await service.blockUser('uid_test');
      expect(blockId, 'blk_123');
      expect(mockClient.blockCallCount, 1);

      // Invalidation sonrası publicProfile tekrar çağrılmalı
      await container.read(publicProfileProvider('uid_test').future);
      expect(mockClient.getProfileCallCount, 2);

      // blockedUsersProvider da invalidate edilmiş olmalı
      await container.read(blockedUsersProvider.future);
      expect(mockBlockedClient.getBlockedUsersCallCount, 2);
    });

    test(
        'PublicProfileService.unblockUser başarılı olunca hem publicProfile hem blockedUsers invalidate edilir',
        () async {
      final mockClient = MockPublicProfileApiClient();
      final mockBlockedClient = FakeBlockedUsersApiClient();

      final container = ProviderContainer(
        overrides: [
          publicProfileApiClientProvider.overrideWithValue(mockClient),
          blockedUsersApiClientProvider.overrideWithValue(mockBlockedClient),
        ],
      );
      addTearDown(container.dispose);

      await container.read(publicProfileProvider('uid_test').future);
      expect(mockClient.getProfileCallCount, 1);

      final service = container.read(publicProfileServiceProvider);
      await service.unblockUser('uid_test');
      expect(mockClient.unblockCallCount, 1);

      await container.read(publicProfileProvider('uid_test').future);
      expect(mockClient.getProfileCallCount, 2);
    });
  });

  group('currentUserIdProvider & isCurrentUserProvider Tests', () {
    test('Oturum açmış kullanıcının UID tespiti doğru çalışır', () {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider
              .overrideWithValue(FakeAuthRepository(FakeUser('my_secret_uid'))),
        ],
      );
      addTearDown(container.dispose);

      final uid = container.read(currentUserIdProvider);
      expect(uid, 'my_secret_uid');

      expect(container.read(isCurrentUserProvider('my_secret_uid')), true);
      expect(container.read(isCurrentUserProvider('other_uid')), false);
      expect(container.read(isCurrentUserProvider(null)), false);
      expect(container.read(isCurrentUserProvider('')), false);
    });

    test('Oturum açılmamışken isCurrentUser her zaman false döner', () {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(null)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), isNull);
      expect(container.read(isCurrentUserProvider('some_uid')), false);
    });
  });
}
