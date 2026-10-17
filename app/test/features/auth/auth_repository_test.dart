import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:app/features/auth/data/google_auth_service.dart';
import 'package:app/features/auth/domain/auth_link_result.dart';

class FakeGoogleAuthService implements GoogleAuthService {
  AuthCredential? credentialToReturn;
  Object? errorToThrow;
  bool signOutCalled = false;

  @override
  Future<AuthCredential?> authenticate() async {
    if (errorToThrow != null) {
      // ignore: only_throw_errors
      throw errorToThrow!;
    }
    return credentialToReturn;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleAuthService & AuthLinkResult Tests', () {
    test('FakeGoogleAuthService returns credential or handles cancellation', () async {
      final fakeGoogle = FakeGoogleAuthService();
      expect(await fakeGoogle.authenticate(), isNull);

      fakeGoogle.credentialToReturn = GoogleAuthProvider.credential(idToken: 'token_123');
      final cred = await fakeGoogle.authenticate();
      expect(cred, isNotNull);
      expect(cred?.signInMethod, 'google.com');

      await fakeGoogle.signOut();
      expect(fakeGoogle.signOutCalled, isTrue);
    });

    test('GoogleSignInException with canceled code is treated as cancellation', () {
      const canceledException = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'Canceled by user',
      );
      expect(canceledException.code, GoogleSignInExceptionCode.canceled);
    });

    test('AuthLinkResult sealed classes instantiate correctly', () {
      const success = AuthLinkSuccess(email: 'test@example.com');
      expect(success.email, 'test@example.com');

      const canceled = AuthLinkCanceled();
      expect(canceled, isA<AuthLinkResult>());

      final cred = GoogleAuthProvider.credential(idToken: 'tok');
      final conflict = AuthLinkConflict(cred);
      expect(conflict.credential, cred);

      const error = AuthLinkError('hata', isNetworkError: true);
      expect(error.isNetworkError, isTrue);
      expect(error.message, 'hata');
    });
  });
}
