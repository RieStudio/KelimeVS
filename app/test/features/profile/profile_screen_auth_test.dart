import 'dart:io';

import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/auth/application/auth_notifier.dart';

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
import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/app_icon_button.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  String? linkedEmail;

  AuthLinkResult linkResultToReturn;
  AuthLinkResult reauthResultToReturn;
  bool signInWithConflictCalled = false;
  bool signOutCalled = false;

  final _controller = StreamController<User?>.broadcast();

  FakeAuthRepository({
    this.isGoogleLinked = false,
    this.linkedEmail,
    this.linkResultToReturn = const AuthLinkCanceled(),
    this.reauthResultToReturn = const AuthLinkSuccess(),
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  @override
  Future<AuthLinkResult> signInWithGoogle() async => const AuthLinkSuccess();

  @override
  Future<AuthLinkResult> linkWithGoogle() async {
    if (linkResultToReturn is AuthLinkSuccess) {
      isGoogleLinked = true;
      linkedEmail = (linkResultToReturn as AuthLinkSuccess).email;
      _controller.add(null);
    }
    return linkResultToReturn;
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

  bool reauthenticateCalled = false;
  bool deleteUserCalled = false;
  bool completeAccountDeletionCalled = false;

  @override
  Future<AuthLinkResult> reauthenticateGoogle() async {
    reauthenticateCalled = true;
    return reauthResultToReturn;
  }

  @override
  Future<void> deleteFirebaseUser() async {
    deleteUserCalled = true;
  }

  @override
  Future<void> completeAccountDeletionAndReset() async {
    completeAccountDeletionCalled = true;
    isGoogleLinked = false;
    linkedEmail = null;
    _controller.add(null);
  }
}

class FakeProfileApiClient implements ProfileApiClient {
  bool deleteCalled = false;
  bool shouldFailDelete = false;

  @override
  Future<UserProfileModel?> getProfile() async => null;

  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);

  @override
  Future<bool> deleteProfile() async {
    deleteCalled = true;
    if (shouldFailDelete) {
      throw const SocketException('Network error');
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Ahmet',
    });
  });

  Widget buildTestScreen(
    FakeAuthRepository repo, {
    ProfileApiClient? apiClient,
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        if (apiClient != null)
          profileApiClientProvider.overrideWithValue(apiClient),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );
  }

  Future<void> openMoreMenu(WidgetTester tester) async {
    final moreBtn = find.byWidgetPredicate(
      (w) => w is AppIconButton && w.icon == AppIcons.more,
    );
    await tester.tap(moreBtn);
    await tester.pumpAndSettle();
  }

  testWidgets(
    '1. Bağlı değilken: Google ile Bağla butonu görünür, çıkış butonu görünmez',
    (tester) async {
      final repo = FakeAuthRepository(isGoogleLinked: false);
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
        findsOneWidget,
      );
      expect(find.text(AppStrings.linkedAccount), findsNothing);
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.signOut),
        findsNothing,
      );
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.deleteAccount),
        findsNothing,
      );

      // Üç nokta menüsünde de Çıkış Yap yer almaz, yalnızca Hesabı Sil yer alır
      await openMoreMenu(tester);
      expect(find.text(AppStrings.signOut), findsNothing);
      expect(find.text(AppStrings.deleteAccount), findsOneWidget);
    },
  );

  testWidgets(
    '2. Kullanıcı Google penceresini kapattığında: sessizce döner ve hata görünmez',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: false,
        linkResultToReturn: const AuthLinkCanceled(),
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    '3. Başarılı bağlama: Google ile Bağla kaybolur, bağlı kartı ve e-posta görünür',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: false,
        linkResultToReturn: const AuthLinkSuccess(email: 'ahmet@gmail.com'),
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
        findsNothing,
      );
      expect(find.text(AppStrings.linkedAccount), findsOneWidget);
      expect(find.text('ahmet@gmail.com'), findsOneWidget);
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.signOut),
        findsNothing,
      );
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.deleteAccount),
        findsNothing,
      );

      // Başarılı bağlama sonrası üç nokta menüsünde hem Çıkış Yap hem Hesabı Sil görünür
      await openMoreMenu(tester);
      expect(find.text(AppStrings.signOut), findsOneWidget);
      expect(find.text(AppStrings.deleteAccount), findsOneWidget);
    },
  );

  testWidgets(
    '4. Çakışma (credential-already-in-use) - vazgeçilirse durum değişmez',
    (tester) async {
      final fakeCred = GoogleAuthProvider.credential(idToken: 'conflict_token');
      final repo = FakeAuthRepository(
        isGoogleLinked: false,
        linkResultToReturn: AuthLinkConflict(fakeCred),
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
      );
      await tester.pumpAndSettle();

      // Diyalog görünmeli
      expect(find.text(AppStrings.linkConflictDialogTitle), findsOneWidget);
      expect(find.text(AppStrings.linkConflictDialogMessage), findsOneWidget);

      // Vazgeç'e bas
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.linkConflictDialogTitle), findsNothing);
      expect(repo.signInWithConflictCalled, isFalse);
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '5. Çakışma (credential-already-in-use) - devam edilirse hesaba geçilir ve yerel ad sıfırlanır',
    (tester) async {
      final fakeCred = GoogleAuthProvider.credential(idToken: 'conflict_token');
      final repo = FakeAuthRepository(
        isGoogleLinked: false,
        linkResultToReturn: AuthLinkConflict(fakeCred),
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SecondaryButton, AppStrings.linkGoogle),
      );
      await tester.pumpAndSettle();

      // Devam'a bas
      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.continueAction),
      );
      await tester.pumpAndSettle();

      expect(repo.signInWithConflictCalled, isTrue);

      // Yerel depodaki takma ad silinmiş olmalı
      const profileRepo = LocalProfileRepository();
      final nick = await profileRepo.getNickname();
      expect(nick, isNull);
    },
  );

  testWidgets(
    '6. Çıkış yap akışı: onay diyaloğunda çıkış seçilirse oturum ve yerel veri sıfırlanır',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'mehmet@gmail.com',
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      expect(find.text(AppStrings.signOut), findsOneWidget);

      await tester.tap(find.text(AppStrings.signOut));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.signOutDialogMessage), findsOneWidget);

      // Diyalog içindeki "Çıkış Yap" (PrimaryButton) butonuna bas
      await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.signOut));
      await tester.pumpAndSettle();

      expect(repo.signOutCalled, isTrue);

      // Yerel depodaki takma ad silinmiş olmalı
      const profileRepo = LocalProfileRepository();
      final nick = await profileRepo.getNickname();
      expect(nick, isNull);
    },
  );

  testWidgets(
    '7. Hesabı Sil butonu menüde görünür ve basılınca onay penceresi açılır (anonim: re-auth notu yok)',
    (tester) async {
      final repo = FakeAuthRepository(isGoogleLinked: false);
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      expect(find.text(AppStrings.deleteAccount), findsOneWidget);

      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(AppStrings.deleteAccountDialogTitle),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.deleteAccountDialogMessage), findsOneWidget);
      expect(
        find.textContaining(AppStrings.deleteAccountGoogleReauthNote),
        findsNothing,
      );
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.cancel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrimaryButton, AppStrings.deleteAccountConfirm),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '7b. Google bağlı kullanıcıda onay penceresinde re-auth notu gösterilir',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining(AppStrings.deleteAccountGoogleReauthNote),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '8. Hesabı Sil onay penceresinde Vazgeç seçilirse işlem iptal edilir',
    (tester) async {
      final repo = FakeAuthRepository(isGoogleLinked: false);
      final fakeApi = FakeProfileApiClient();
      await tester.pumpWidget(buildTestScreen(repo, apiClient: fakeApi));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(fakeApi.deleteCalled, isFalse);
      expect(repo.completeAccountDeletionCalled, isFalse);
    },
  );

  testWidgets(
    '9. Anonim hesapta Hesabı Sil onaylandığında: sunucu silinir, Firebase silinir, yerel veri sıfırlanır',
    (tester) async {
      final repo = FakeAuthRepository(isGoogleLinked: false);
      final fakeApi = FakeProfileApiClient();
      await tester.pumpWidget(buildTestScreen(repo, apiClient: fakeApi));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.deleteAccountConfirm),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.deleteCalled, isTrue);
      expect(repo.deleteUserCalled, isTrue);
      expect(repo.completeAccountDeletionCalled, isTrue);

      // Yerel depodaki takma ad silinmiş olmalı
      const profileRepo = LocalProfileRepository();
      final nick = await profileRepo.getNickname();
      expect(nick, isNull);
    },
  );

  testWidgets(
    '10. Google bağlı hesapta Hesabı Sil onaylandığında re-auth çağrılır',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@gmail.com',
      );
      final fakeApi = FakeProfileApiClient();
      await tester.pumpWidget(buildTestScreen(repo, apiClient: fakeApi));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.deleteAccountConfirm),
      );
      await tester.pumpAndSettle();

      expect(repo.reauthenticateCalled, isTrue);
      expect(fakeApi.deleteCalled, isTrue);
      expect(repo.completeAccountDeletionCalled, isTrue);
    },
  );

  testWidgets(
    '11. handleAccountDeletedElsewhere çağrıldığında yerel veriler temizlenir ve sıfırlanır',
    (tester) async {
      final repo = FakeAuthRepository(isGoogleLinked: false);
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // Takma adın var olduğunu doğrula
      const profileRepo = LocalProfileRepository();
      await profileRepo.setNickname('TestUser');
      expect(await profileRepo.getNickname(), 'TestUser');

      // Sunucudan 410 geldiğinde tetiklenen akış
      await container
          .read(authNotifierProvider.notifier)
          .handleAccountDeletedElsewhere();

      expect(repo.completeAccountDeletionCalled, isTrue);
      expect(await profileRepo.getNickname(), isNull);
    },
  );

  testWidgets(
    '12. Re-auth sırasında farklı Google hesabı seçilirse (user-mismatch vb.) veri silinmez ve uyarı gösterilir',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
        reauthResultToReturn: const AuthLinkError(
          AppStrings.reauthWrongAccountError,
        ),
      );
      final fakeApi = FakeProfileApiClient();
      await tester.pumpWidget(buildTestScreen(repo, apiClient: fakeApi));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.deleteAccountConfirm),
      );
      await tester.pumpAndSettle();

      expect(repo.reauthenticateCalled, isTrue);
      expect(fakeApi.deleteCalled, isFalse);
      expect(repo.deleteUserCalled, isFalse);
      expect(repo.completeAccountDeletionCalled, isFalse);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(AppStrings.reauthWrongAccountError), findsOneWidget);
    },
  );

  testWidgets(
    '13. Re-auth sırasında kullanıcı pencereyi kapatır veya iptal ederse sessizce döner, veri silinmez',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
        reauthResultToReturn: const AuthLinkCanceled(),
      );
      final fakeApi = FakeProfileApiClient();
      await tester.pumpWidget(buildTestScreen(repo, apiClient: fakeApi));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text(AppStrings.deleteAccount));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.deleteAccountConfirm),
      );
      await tester.pumpAndSettle();

      expect(repo.reauthenticateCalled, isTrue);
      expect(fakeApi.deleteCalled, isFalse);
      expect(repo.deleteUserCalled, isFalse);
      expect(repo.completeAccountDeletionCalled, isFalse);

      // Sessizce dönmeli: SnackBar gösterilmez
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    '14. Üç nokta menüsü: dışarıya dokununca veya geri tuşuyla kapanır',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      expect(find.text(AppStrings.signOut), findsOneWidget);
      expect(find.text(AppStrings.deleteAccount), findsOneWidget);

      // Menü dışına (ekranın sol üstüne) dokun
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.signOut), findsNothing);
      expect(find.text(AppStrings.deleteAccount), findsNothing);
    },
  );

  testWidgets(
    '15. Üç nokta menüsü: ayırıcı çizgi ve Hesabı Sil tehlike rengi doğrulanır',
    (tester) async {
      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
      );
      await tester.pumpWidget(buildTestScreen(repo));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      expect(find.byType(Divider), findsOneWidget);

      final deleteText = tester.widget<Text>(
        find.text(AppStrings.deleteAccount),
      );
      expect(deleteText.style?.color, AppColors.dangerText);
    },
  );

  testWidgets(
    '16. 320 dp ve textScaler 1.5 iken Profil ekranında ve menüde taşma olmaz',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = FakeAuthRepository(
        isGoogleLinked: true,
        linkedEmail: 'user@example.com',
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: buildTestScreen(repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await openMoreMenu(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.signOut), findsOneWidget);
      expect(find.text(AppStrings.deleteAccount), findsOneWidget);
    },
  );
}
