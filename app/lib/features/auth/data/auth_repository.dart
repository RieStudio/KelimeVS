import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/strings/app_strings.dart';
import '../domain/auth_link_result.dart';
import 'google_auth_service.dart';

import 'package:firebase_core/firebase_core.dart';

abstract interface class AuthRepository {
  User? get currentUser;
  Stream<User?> authStateChanges();
  bool get isGoogleLinked;
  String? get linkedEmail;

  Future<AuthLinkResult> linkWithGoogle();
  Future<void> signInWithConflictCredential(AuthCredential credential);
  Future<void> signOutAndResetToAnonymous();

  Future<AuthLinkResult> reauthenticateGoogle();
  Future<void> deleteFirebaseUser();
  Future<void> completeAccountDeletionAndReset();
}

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth? _injectedAuth;
  final GoogleAuthService _googleAuthService;

  FirebaseAuthRepository({
    FirebaseAuth? auth,
    GoogleAuthService? googleAuthService,
  })  : _injectedAuth = auth,
        _googleAuthService = googleAuthService ?? const DefaultGoogleAuthService();

  FirebaseAuth? get _auth {
    if (_injectedAuth != null) return _injectedAuth;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance;
      }
    } catch (_) {}
    return null;
  }

  @override
  User? get currentUser => _auth?.currentUser;

  @override
  Stream<User?> authStateChanges() {
    final a = _auth;
    return a != null ? a.authStateChanges() : const Stream.empty();
  }

  @override
  bool get isGoogleLinked {
    final user = currentUser;
    if (user == null || user.isAnonymous) return false;
    return user.providerData.any((p) => p.providerId == 'google.com');
  }

  @override
  String? get linkedEmail {
    final user = currentUser;
    if (user == null) return null;
    for (final profile in user.providerData) {
      if (profile.providerId == 'google.com' && profile.email != null) {
        return profile.email;
      }
    }
    return user.email;
  }

  @override
  Future<AuthLinkResult> linkWithGoogle() async {
    final user = currentUser;
    if (user == null) {
      return const AuthLinkError('Kullanıcı oturumu bulunamadı.');
    }

    final AuthCredential? credential;
    try {
      credential = await _googleAuthService.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthLinkCanceled();
      }
      return AuthLinkError('Google girişi başarısız oldu (${e.code}).');
    } catch (_) {
      return const AuthLinkError(AppStrings.authGenericError);
    }

    if (credential == null) {
      return const AuthLinkCanceled();
    }

    try {
      final userCredential = await user.linkWithCredential(credential);
      return AuthLinkSuccess(email: userCredential.user?.email ?? linkedEmail);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        // Çakışma akışında hazır credential'ı kullan
        return AuthLinkConflict(e.credential ?? credential);
      }
      if (e.code == 'network-request-failed') {
        return const AuthLinkError(AppStrings.networkError, isNetworkError: true);
      }
      return AuthLinkError(e.message ?? AppStrings.authGenericError);
    } catch (_) {
      return const AuthLinkError(AppStrings.authGenericError);
    }
  }

  @override
  Future<void> signInWithConflictCredential(AuthCredential credential) async {
    final a = _auth;
    if (a == null) throw StateError('Firebase henüz başlatılmadı.');
    await a.signInWithCredential(credential);
  }

  @override
  Future<void> signOutAndResetToAnonymous() async {
    final a = _auth;
    if (a == null) throw StateError('Firebase henüz başlatılmadı.');
    await a.signOut();
    await _googleAuthService.signOut();
    await a.signInAnonymously();
  }

  @override
  Future<AuthLinkResult> reauthenticateGoogle() async {
    final user = currentUser;
    if (user == null) {
      return const AuthLinkError('Kullanıcı oturumu bulunamadı.');
    }

    final AuthCredential? credential;
    try {
      credential = await _googleAuthService.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthLinkCanceled();
      }
      return AuthLinkError('Google doğrulaması başarısız oldu (${e.code}).');
    } catch (_) {
      return const AuthLinkError(AppStrings.authGenericError);
    }

    if (credential == null) {
      return const AuthLinkCanceled();
    }

    try {
      await user.reauthenticateWithCredential(credential);
      return const AuthLinkSuccess();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch' ||
          e.code == 'wrong-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential') {
        return const AuthLinkError(AppStrings.reauthWrongAccountError);
      }
      if (e.code == 'network-request-failed') {
        return const AuthLinkError(AppStrings.networkError, isNetworkError: true);
      }
      return AuthLinkError(e.message ?? AppStrings.authGenericError);
    } catch (_) {
      return const AuthLinkError(AppStrings.authGenericError);
    }
  }

  @override
  Future<void> deleteFirebaseUser() async {
    final user = currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // 3. Kural: Anonim hesapta user.delete() requires-recent-login verirse yoksay
      if (user.isAnonymous && e.code == 'requires-recent-login') {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> completeAccountDeletionAndReset() async {
    final a = _auth;
    final user = a?.currentUser;
    if (user != null) {
      try {
        await user.delete();
      } catch (_) {
        // Hata olursa yoksay
      }
    }

    try {
      await _googleAuthService.signOut();
    } catch (_) {}

    if (a != null) {
      try {
        await a.signOut();
      } catch (_) {}
      await a.signInAnonymously();
    }
  }
}

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return const DefaultGoogleAuthService();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final googleService = ref.watch(googleAuthServiceProvider);
  return FirebaseAuthRepository(googleAuthService: googleService);
});
