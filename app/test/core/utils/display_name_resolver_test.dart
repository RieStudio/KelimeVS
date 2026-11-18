import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/utils/display_name_resolver.dart';
import 'package:app/core/utils/opponent_name_sanitizer.dart';

void main() {
  group('DisplayNameResolver Tests', () {
    group('1. Sunucu ile Birebir Parite (Test Vektörleri)', () {
      test('Sunucu generateGuestNickname ile bit-for-bit aynı sonucu üretir', () {
        expect(DisplayNameResolver.generateGuestNickname('guest_12345'), 'M-8716');
        expect(DisplayNameResolver.generateGuestNickname('user_xyz_999'), 'M-2239');
        expect(DisplayNameResolver.generateGuestNickname('firebase_anon_abc'), 'M-6223');
        expect(DisplayNameResolver.generateGuestNickname('guest_user_abc_123'), 'M-1360');
        expect(DisplayNameResolver.generateGuestNickname('guest_opponent_789'), 'M-3669');
      });

      test('Format daima M-[1000-9999] aralığındadır', () {
        final regex = RegExp(r'^M-[1-9]\d{3}$');
        for (final uid in [
          'u1',
          'a_very_long_firebase_uid_string_1234567890',
          'special_!@#\$%^&*()',
          'turkish_çığöşü',
        ]) {
          final res = DisplayNameResolver.generateGuestNickname(uid);
          expect(regex.hasMatch(res), isTrue, reason: 'UID: $uid -> $res');
        }
      });
    });

    group('2. Misafir Kullanıcı Çözümleme (isGuest: true)', () {
      const uid = 'guest_12345'; // M-8716

      test('Takma ad null, boş veya sadece boşluksa M-XXXX döner', () {
        expect(DisplayNameResolver.resolve(uid: uid, isGuest: true), 'M-8716');
        expect(DisplayNameResolver.resolve(nickname: null, uid: uid, isGuest: true), 'M-8716');
        expect(DisplayNameResolver.resolve(nickname: '', uid: uid, isGuest: true), 'M-8716');
        expect(DisplayNameResolver.resolve(nickname: '   ', uid: uid, isGuest: true), 'M-8716');
      });

      test('Takma ad hatalı olarak "Oyuncu" gelmişse M-XXXX olarak düzeltilir', () {
        expect(DisplayNameResolver.resolve(nickname: 'Oyuncu', uid: uid, isGuest: true), 'M-8716');
      });

      test('Takma ad zaten geçerli M-XXXX ise korunur', () {
        expect(DisplayNameResolver.resolve(nickname: 'M-5432', uid: uid, isGuest: true), 'M-5432');
      });
    });

    group('3. Kayıtlı Kullanıcı Çözümleme (isGuest: false)', () {
      const uid = 'user_xyz_999';

      test('Geçerli takma adı aynen korur', () {
        expect(DisplayNameResolver.resolve(nickname: 'Zeynep', uid: uid, isGuest: false), 'Zeynep');
      });

      test('Kayıtlı kullanıcının adı yoksa "Oyuncu" döner', () {
        expect(DisplayNameResolver.resolve(nickname: null, uid: uid, isGuest: false), AppStrings.defaultPlayerName);
        expect(DisplayNameResolver.resolve(nickname: '', uid: uid, isGuest: false), AppStrings.defaultPlayerName);
        expect(DisplayNameResolver.resolve(nickname: '  ', uid: uid, isGuest: false), AppStrings.defaultPlayerName);
      });
    });

    group('4. isGuest Belirsiz Olduğunda Akıllı Fallback', () {
      const uid = 'guest_opponent_789'; // M-3669

      test('UID varsa ve nickname null/boş/"Oyuncu" ise deterministik M-XXXX üretilir', () {
        expect(DisplayNameResolver.resolve(nickname: null, uid: uid), 'M-3669');
        expect(DisplayNameResolver.resolve(nickname: '', uid: uid), 'M-3669');
        expect(DisplayNameResolver.resolve(nickname: 'Oyuncu', uid: uid), 'M-3669');
      });

      test('UID yoksa ve nickname yoksa "Oyuncu" döner', () {
        expect(DisplayNameResolver.resolve(nickname: null, uid: null), AppStrings.defaultPlayerName);
        expect(DisplayNameResolver.resolve(nickname: '', uid: ''), AppStrings.defaultPlayerName);
        expect(DisplayNameResolver.resolve(nickname: '   ', uid: null), AppStrings.defaultPlayerName);
      });

      test('Geçerli bir ad varsa korunur', () {
        expect(DisplayNameResolver.resolve(nickname: 'Berk', uid: uid), 'Berk');
        expect(DisplayNameResolver.resolve(nickname: 'M-7777', uid: uid), 'M-7777');
      });
    });

    group('5. OpponentNameSanitizer Entegrasyonu', () {
      const oppUid = 'firebase_anon_abc'; // M-6223

      test('raw null ve opponentUid varsa M-XXXX döner', () {
        expect(OpponentNameSanitizer.sanitize(null, opponentUid: oppUid), 'M-6223');
      });

      test('raw "Oyuncu" ve opponentUid varsa M-XXXX döner', () {
        expect(OpponentNameSanitizer.sanitize('Oyuncu', opponentUid: oppUid), 'M-6223');
      });

      test('opponentUid yoksa ve raw null ise AppStrings.opponent ("Rakip") döner', () {
        expect(OpponentNameSanitizer.sanitize(null), AppStrings.opponent);
      });

      test('Geçerli ad verilmişse aynen korunur', () {
        expect(OpponentNameSanitizer.sanitize('M-6223', opponentUid: oppUid), 'M-6223');
        expect(OpponentNameSanitizer.sanitize('Selim', opponentUid: oppUid), 'Selim');
      });
    });
  });
}
