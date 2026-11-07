import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/main.dart';

class _SmokeAuthRepository implements AuthRepository {
  @override
  bool get isAuthenticated => true;

  @override
  bool get isGoogleLinked => false;

  @override
  String? get linkedEmail => null;

  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'smoke_token';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Oyuncu',
    });
  });

  testWidgets('KelimeVSApp smoke test - verifies navigation and gallery load', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SmokeAuthRepository()),
      ],
      child: const KelimeVSApp(),
    ));
    await tester.pumpAndSettle();

    // Ana ekrandaki Hızlı Maç butonu ve alt gezinme sekmelerinin varlığını doğrula
    expect(find.text(AppStrings.quickMatch), findsOneWidget);
    expect(find.text(AppStrings.navHome), findsOneWidget);
    expect(find.text(AppStrings.navLeaderboard), findsOneWidget);
    expect(find.text(AppStrings.navShop), findsOneWidget);
    expect(find.text(AppStrings.navProfile), findsOneWidget);
  });
}
