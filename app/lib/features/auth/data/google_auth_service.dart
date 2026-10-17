import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/auth_config.dart';

abstract interface class GoogleAuthService {
  Future<AuthCredential?> authenticate();
  Future<void> signOut();
}

class DefaultGoogleAuthService implements GoogleAuthService {
  static Future<void>? _initFuture;

  const DefaultGoogleAuthService();

  Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: AuthConfig.googleServerClientId,
    );
  }

  @override
  Future<AuthCredential?> authenticate() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        return null;
      }
      return GoogleAuthProvider.credential(
        idToken: idToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Çıkış hatası uygulamanın akışını bozmamalı
    }
  }
}

