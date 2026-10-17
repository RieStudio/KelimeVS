import 'package:firebase_auth/firebase_auth.dart';

sealed class AuthLinkResult {
  const AuthLinkResult();
}

class AuthLinkSuccess extends AuthLinkResult {
  final String? email;
  const AuthLinkSuccess({this.email});
}

class AuthLinkCanceled extends AuthLinkResult {
  const AuthLinkCanceled();
}

class AuthLinkConflict extends AuthLinkResult {
  final AuthCredential credential;
  const AuthLinkConflict(this.credential);
}

class AuthLinkError extends AuthLinkResult {
  final String message;
  final bool isNetworkError;

  const AuthLinkError(
    this.message, {
    this.isNetworkError = false,
  });
}

