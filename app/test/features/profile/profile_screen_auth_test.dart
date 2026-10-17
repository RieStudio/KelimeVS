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
import 'package:app/features/profile/presentation/profile_screen.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  bool isGoogleLinked;

  @override
  String? linkedEmail;

  AuthLinkResult linkResultToReturn;
  bool signInWithConflictCalled = false;
  bool signOutCalled = false;

  final _controller = StreamController<User?>.broadcast();

  FakeAuthRepository({
    this.isGoogleLinked = false,
    this.linkedEmail,
    this.linkResultToReturn = const AuthLinkCanceled(),
  });

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Ahmet',
    });
  });

  Widget buildTestScreen(FakeAuthRepository repo) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: ProfileScreen(),
      ),
    );
  }

  testWidgets('1. Bağlı değilken: Google ile Bağla butonu görünür, çıkış butonu görünmez', (tester) async {
    final repo = FakeAuthRepository(isGoogleLinked: false);
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle), findsOneWidget);
    expect(find.text(AppStrings.linkedAccount), findsNothing);
    expect(find.widgetWithText(SecondaryButton, AppStrings.signOut), findsNothing);
  });

  testWidgets('2. Kullanıcı Google penceresini kapattığında: sessizce döner ve hata görünmez', (tester) async {
    final repo = FakeAuthRepository(
      isGoogleLinked: false,
      linkResultToReturn: const AuthLinkCanceled(),
    );
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('3. Başarılı bağlama: Google ile Bağla kaybolur, bağlı kartı ve e-posta görünür', (tester) async {
    final repo = FakeAuthRepository(
      isGoogleLinked: false,
      linkResultToReturn: const AuthLinkSuccess(email: 'ahmet@gmail.com'),
    );
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle), findsNothing);
    expect(find.text(AppStrings.linkedAccount), findsOneWidget);
    expect(find.text('ahmet@gmail.com'), findsOneWidget);
    expect(find.widgetWithText(SecondaryButton, AppStrings.signOut), findsOneWidget);
  });

  testWidgets('4. Çakışma (credential-already-in-use) - vazgeçilirse durum değişmez', (tester) async {
    final fakeCred = GoogleAuthProvider.credential(idToken: 'conflict_token');
    final repo = FakeAuthRepository(
      isGoogleLinked: false,
      linkResultToReturn: AuthLinkConflict(fakeCred),
    );
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle));
    await tester.pumpAndSettle();

    // Diyalog görünmeli
    expect(find.text(AppStrings.linkConflictDialogTitle), findsOneWidget);
    expect(find.text(AppStrings.linkConflictDialogMessage), findsOneWidget);

    // Vazgeç'e bas
    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.linkConflictDialogTitle), findsNothing);
    expect(repo.signInWithConflictCalled, isFalse);
    expect(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle), findsOneWidget);
  });

  testWidgets('5. Çakışma (credential-already-in-use) - devam edilirse hesaba geçilir ve yerel ad sıfırlanır', (tester) async {
    final fakeCred = GoogleAuthProvider.credential(idToken: 'conflict_token');
    final repo = FakeAuthRepository(
      isGoogleLinked: false,
      linkResultToReturn: AuthLinkConflict(fakeCred),
    );
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.linkGoogle));
    await tester.pumpAndSettle();

    // Devam'a bas
    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.continueAction));
    await tester.pumpAndSettle();

    expect(repo.signInWithConflictCalled, isTrue);

    // Yerel depodaki takma ad silinmiş olmalı
    const profileRepo = LocalProfileRepository();
    final nick = await profileRepo.getNickname();
    expect(nick, isNull);
  });

  testWidgets('6. Çıkış yap akışı: onay diyaloğunda çıkış seçilirse oturum ve yerel veri sıfırlanır', (tester) async {
    final repo = FakeAuthRepository(
      isGoogleLinked: true,
      linkedEmail: 'mehmet@gmail.com',
    );
    await tester.pumpWidget(buildTestScreen(repo));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SecondaryButton, AppStrings.signOut), findsOneWidget);

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.signOut));
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
  });
}
