@Timeout(Duration(seconds: 30))
library;

import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthTokenProvider', () {
    test('FakeAuthTokenProvider geçerli token döndürür', () async {
      final provider = FakeAuthTokenProvider(token: 'test_token_abc');
      final token = await provider.getIdToken();
      expect(token, 'test_token_abc');
    });

    test('FakeAuthTokenProvider oturum yokken null döndürür', () async {
      final provider = FakeAuthTokenProvider(token: null);
      final token = await provider.getIdToken();
      expect(token, isNull);
    });

    test('FakeAuthTokenProvider hata durumunda istisna fırlatır', () async {
      final provider = FakeAuthTokenProvider(
        errorToThrow: Exception('Auth network error'),
      );
      expect(() => provider.getIdToken(), throwsA(isA<Exception>()));
    });
  });
}

