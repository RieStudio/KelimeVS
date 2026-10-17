import 'package:firebase_auth/firebase_auth.dart';

/// Firebase kimlik jetonunu (ID token) sağlayan soyut arayüz.
///
/// Testlerde sahte sağlayıcılar ile taklit edilebilir.
/// Güvenlik Kuralı: Dönen jeton asla loglara veya kullanıcı arayüzüne yazdırılmaz.
abstract interface class AuthTokenProvider {
  /// Geçerli kullanıcının Firebase kimlik jetonunu döndürür.
  ///
  /// Oturum yoksa anonim giriş yapmayı dener.
  /// Jeton alınamazsa null dönebilir veya istisna fırlatabilir.
  Future<String?> getIdToken({bool forceRefresh = false});
}

/// [FirebaseAuth] üzerinden gerçek ID token sağlayan uygulama.
class FirebaseAuthTokenProvider implements AuthTokenProvider {
  final FirebaseAuth? _injectedAuth;

  const FirebaseAuthTokenProvider({FirebaseAuth? auth})
      : _injectedAuth = auth;

  FirebaseAuth? get _auth {
    try {
      return _injectedAuth ?? FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      final auth = _auth;
      if (auth == null) return null;
      User? user = auth.currentUser;
      if (user == null) {
        final userCredential = await auth.signInAnonymously();
        user = userCredential.user;
      }
      if (user == null) {
        return null;
      }
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }
}

/// Birim testler için sahte jeton sağlayıcı.
class FakeAuthTokenProvider implements AuthTokenProvider {
  String? token;
  Object? errorToThrow;

  FakeAuthTokenProvider({
    this.token = 'fake_firebase_token',
    this.errorToThrow,
  });

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (errorToThrow != null) {
      // ignore: only_throw_errors
      throw errorToThrow!;
    }
    return token;
  }
}

