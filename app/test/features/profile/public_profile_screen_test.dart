import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/profile/application/public_profile_provider.dart';
import 'package:app/features/profile/data/public_profile_api_client.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';
import 'package:app/features/profile/presentation/public_profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class FakePublicProfileApiClient implements PublicProfileApiClient {
  PublicProfile? profileToReturn;
  Object? errorToThrow;

  int getProfileCallCount = 0;
  int blockCallCount = 0;
  int unblockCallCount = 0;
  int reportCallCount = 0;
  String? lastReportReason;

  Object? blockErrorToThrow;
  Object? reportErrorToThrow;

  FakePublicProfileApiClient({
    this.profileToReturn,
    this.errorToThrow,
  });

  @override
  Future<PublicProfile> getPublicProfile(String uid) async {
    getProfileCallCount++;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return profileToReturn ??
        PublicProfile(
          uid: uid,
          nickname: 'Alice',
          equippedFrame: 'classic',
          stats: const PublicProfileStats(
            played: 10,
            won: 7,
            lost: 3,
            winRate: 70,
          ),
        );
  }

  @override
  Future<String> blockUser(String uid) async {
    blockCallCount++;
    if (blockErrorToThrow != null) {
      throw blockErrorToThrow!;
    }
    return 'blk_123';
  }

  @override
  Future<void> unblockUser(String uid) async {
    unblockCallCount++;
  }

  @override
  Future<String> reportUser(String uid, String reason) async {
    reportCallCount++;
    lastReportReason = reason;
    if (reportErrorToThrow != null) {
      throw reportErrorToThrow!;
    }
    return 'rep_123';
  }
}

void main() {
  Widget buildTestWidget({
    required Widget child,
    required List<dynamic> overrides,
  }) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('PublicProfileScreen Layout Tests', () {
    testWidgets(
        'Normal profil: ad, avatar, 3 istatistik kartı ve Engelle+Bildir butonları görünür',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const profile = PublicProfile(
        uid: 'user_bob',
        nickname: 'BobTheBuilder',
        equippedFrame: 'emerald',
        stats: PublicProfileStats(
          played: 142,
          won: 88,
          lost: 54,
          winRate: 62,
        ),
        isGuest: false,
        isBlocked: false,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_bob'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // Başlık ve İsim
      expect(find.text(AppStrings.publicProfileTitle), findsOneWidget);
      expect(find.text('BobTheBuilder'), findsOneWidget);

      // 3 İstatistik Kartı (Oynanan, Galibiyet, Kazanma)
      expect(find.text(AppStrings.statsPlayed), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
      expect(find.text(AppStrings.statsWon), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text(AppStrings.statsWinRate), findsOneWidget);
      expect(find.text('%62'), findsOneWidget);

      // Engelle ve Bildir butonları
      expect(find.text(AppStrings.blockAction), findsOneWidget);
      expect(find.text(AppStrings.reportAction), findsOneWidget);
      expect(find.text(AppStrings.profileBlockHelpText), findsOneWidget);

      // Kendi profiline ait alanlar bulunmamalı
      expect(find.text(AppStrings.linkedAccount), findsNothing);
      expect(find.text(AppStrings.changeNickname), findsNothing);
      expect(find.text(AppStrings.blockedUsersTitle), findsNothing);
    });

    testWidgets('Misafir kullanıcıda isim altında "Misafir" rozeti görünür',
        (tester) async {
      const profile = PublicProfile(
        uid: 'guest_999',
        nickname: 'M-4821',
        equippedFrame: 'classic',
        stats: PublicProfileStats(played: 0, won: 0, lost: 0, winRate: 0),
        isGuest: true,
        isBlocked: false,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'guest_999'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('M-4821'), findsOneWidget);
      expect(find.text(AppStrings.profileGuestBadge), findsOneWidget);
    });

    testWidgets(
        'Engellenmiş oyuncu: uyarı kartı ve "Engeli Kaldır" ile "Bildir" butonları görünür',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_bad',
        nickname: 'BadPlayer',
        equippedFrame: 'classic',
        stats: PublicProfileStats(played: 5, won: 1, lost: 4, winRate: 20),
        isGuest: false,
        isBlocked: true,
        blockId: 'blk_123',
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_bad'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // Engellendi banner'ı
      expect(find.text(AppStrings.profileBlockedBanner), findsOneWidget);

      // Engeli Kaldır ve Bildir görünmeli, Engelle görünmemeli
      expect(find.text(AppStrings.unblockAction), findsOneWidget);
      expect(find.text(AppStrings.reportAction), findsOneWidget);
      expect(find.text(AppStrings.blockAction), findsNothing);
    });
  });

  group('PublicProfileScreen Error & Tombstone States', () {
    testWidgets('notFound veya deleted durumunda silinmiş hesap ekranı açılır',
        (tester) async {
      final fakeClient = FakePublicProfileApiClient(
        errorToThrow: const PublicProfileException(
          kind: PublicProfileErrorKind.deleted,
          message: AppStrings.profileDeleted,
          statusCode: 410,
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'deleted_uid'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileDeletedTitle), findsOneWidget);
      expect(find.text(AppStrings.profileDeletedMessage), findsOneWidget);
      expect(find.text(AppStrings.backAction), findsOneWidget);

      // Geri Dön butonuna dokununca pop çağrılır
      await tester.tap(find.text(AppStrings.backAction));
      await tester.pumpAndSettle();
    });

    testWidgets('Ağ hatası durumunda hata mesajı ve "Tekrar Dene" butonu çıkar',
        (tester) async {
      final fakeClient = FakePublicProfileApiClient(
        errorToThrow: const PublicProfileException(
          kind: PublicProfileErrorKind.networkOrTimeout,
          message: AppStrings.profileConnectionError,
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'err_uid'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileConnectionError), findsOneWidget);
      expect(find.text(AppStrings.retry), findsOneWidget);

      // Tekrar Dene'ye basınca provider re-fetch tetiklenir
      fakeClient.errorToThrow = null; // Bir sonrakinde başarılı olsun
      await tester.tap(find.text(AppStrings.retry));
      await tester.pumpAndSettle();

      expect(fakeClient.getProfileCallCount, greaterThanOrEqualTo(2));
      expect(find.text('Alice'), findsOneWidget);
    });
  });

  group('PublicProfileScreen Actions Tests', () {
    testWidgets(
        'Engelle akışı: Onay diyaloğu açılır, onaylanınca blockUser çağrılır ve SnackBar gösterilir',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_target',
        nickname: 'TargetUser',
        equippedFrame: 'classic',
        stats: PublicProfileStats(played: 10, won: 5, lost: 5, winRate: 50),
        isBlocked: false,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_target'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // "Engelle" butonuna bas
      await tester.tap(find.text(AppStrings.blockAction));
      await tester.pumpAndSettle();

      // Onay diyaloğu görünür
      expect(find.text(AppStrings.blockDialogTitle), findsOneWidget);
      expect(
        find.text(AppStrings.blockDialogMessage('TargetUser')),
        findsOneWidget,
      );
      expect(
        find.textContaining('TargetUser adlı oyuncuyu engellemek istediğinden emin misin?'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'^\s*adlı')), findsNothing);

      // Diyalogda "Engelle"ye bas
      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.blockConfirm));
      await tester.pumpAndSettle();

      expect(fakeClient.blockCallCount, 1);
      expect(find.text(AppStrings.profileBlockedSuccess), findsOneWidget);
      // Ekran engelli durumuna geçer
      expect(find.text(AppStrings.profileBlockedBanner), findsOneWidget);
    });

    testWidgets('Engeli Kaldır akışı: Onaysız çalışır, unblockUser çağrılır',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_blocked',
        nickname: 'BlockedUser',
        equippedFrame: 'classic',
        isBlocked: true,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_blocked'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // "Engeli Kaldır"a bas (diyalog açılmaz, doğrudan çağrılır)
      await tester.tap(find.text(AppStrings.unblockAction));
      await tester.pumpAndSettle();

      expect(fakeClient.unblockCallCount, 1);
      expect(find.text(AppStrings.profileUnblockedSuccess), findsOneWidget);
      // Tekrar normal duruma geçer
      expect(find.text(AppStrings.blockAction), findsOneWidget);
    });

    testWidgets(
        'Bildir akışı: Bottom sheet açılır, 3 seçenek listelenir, gönderim başarılı olunca sheet kapanır',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_suspect',
        nickname: 'SuspectUser',
        equippedFrame: 'classic',
        isBlocked: false,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_suspect'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // "Bildir" butonuna bas
      await tester.tap(find.text(AppStrings.reportAction));
      await tester.pumpAndSettle();

      // Bottom sheet öğeleri
      expect(find.text(AppStrings.reportDialogTitle), findsOneWidget);
      expect(
        find.text(AppStrings.reportUserSubtitle('SuspectUser')),
        findsOneWidget,
      );
      expect(
        find.textContaining('SuspectUser için bildirim sebebini seç.'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'^\s*için')), findsNothing);
      expect(find.text(AppStrings.reasonInappropriateNickname), findsOneWidget);
      expect(find.text(AppStrings.reasonCheatingSuspicion), findsOneWidget);
      expect(find.text(AppStrings.reasonOther), findsOneWidget);

      // "Hile şüphesi" seç
      await tester.tap(find.text(AppStrings.reasonCheatingSuspicion));
      await tester.pumpAndSettle();

      // "Bildir"e bas
      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.reportAction));
      await tester.pumpAndSettle();

      expect(fakeClient.reportCallCount, 1);
      expect(fakeClient.lastReportReason, 'cheating');
      expect(find.text(AppStrings.profileReportedSuccess), findsOneWidget);
      // Bottom sheet kapanmış olmalı
      expect(find.text(AppStrings.reasonCheatingSuspicion), findsNothing);
    });

    testWidgets('Bildir akışı: alreadyReported hatasında sheet kapanır ve mesaj görünür',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_rep',
        nickname: 'RepUser',
        equippedFrame: 'classic',
      );

      final fakeClient = FakePublicProfileApiClient(
        profileToReturn: profile,
      );
      fakeClient.reportErrorToThrow = const PublicProfileException(
        kind: PublicProfileErrorKind.alreadyReported,
        message: AppStrings.profileAlreadyReported,
        statusCode: 409,
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_rep'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.reportAction));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.reportAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileAlreadyReported), findsOneWidget);
      expect(find.text(AppStrings.reasonInappropriateNickname), findsNothing);
    });

    testWidgets('Kendi UID ile açılmaya çalışılırsa ekran hemen kapanır (güvenlik kontrolü)',
        (tester) async {
      final fakeClient = FakePublicProfileApiClient();

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'my_self_uid'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pump();

      // Profil yükleme çağrısı yapılmamalı ve ekran boş kalmalı
      expect(fakeClient.getProfileCallCount, 0);
      expect(find.text(AppStrings.publicProfileTitle), findsNothing);
    });

    testWidgets(
        'Engelle akışı: Boş takma adlı profilde varsayılan adla diyalog açılır ve " adlı" ile başlamaz',
        (tester) async {
      const profile = PublicProfile(
        uid: 'user_empty_name',
        nickname: '',
        equippedFrame: 'classic',
        isBlocked: false,
      );

      final fakeClient = FakePublicProfileApiClient(profileToReturn: profile);

      await tester.pumpWidget(
        buildTestWidget(
          child: const PublicProfileScreen(uid: 'user_empty_name'),
          overrides: [
            publicProfileApiClientProvider.overrideWithValue(fakeClient),
            authRepositoryProvider
                .overrideWithValue(FakeAuthRepository(FakeUser('my_self_uid'))),
          ],
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.blockAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.blockDialogTitle), findsOneWidget);
      expect(
        find.textContaining('Oyuncu adlı oyuncuyu engellemek istediğinden emin misin?'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'^\s*adlı')), findsNothing);
    });
  });
}
