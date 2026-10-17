abstract final class AuthConfig {
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '487342637535-thrq6cg1vr2f6mro0kkpbsnabs8j0g30.apps.googleusercontent.com',
  );
}

