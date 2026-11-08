import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/utils/opponent_name_sanitizer.dart';

void main() {
  group('OpponentNameSanitizer Tests', () {
    test('null girdi için fallback "Rakip" döner', () {
      expect(OpponentNameSanitizer.sanitize(null), AppStrings.opponent);
    });

    test('boş dize için fallback "Rakip" döner', () {
      expect(OpponentNameSanitizer.sanitize(''), AppStrings.opponent);
    });

    test('yalnızca boşluklardan oluşan dize için fallback "Rakip" döner', () {
      expect(OpponentNameSanitizer.sanitize('   '), AppStrings.opponent);
    });

    test('kontrol karakterlerini siler', () {
      expect(OpponentNameSanitizer.sanitize('Ahmet\x00\x1F\x7F'), 'Ahmet');
      expect(OpponentNameSanitizer.sanitize('M-\n9999\r\t'), 'M-9999');
    });

    test('ardışık boşlukları teke indirir ve baştaki/sondaki boşlukları kırpar', () {
      expect(OpponentNameSanitizer.sanitize('   Ali    Veli   '), 'Ali Veli');
    });

    test('24 karakterden uzun metinleri 24 karaktere sınırlar', () {
      const longInput = 'BirIkiUcDortBesAltiYediSekizDokuzOn';
      final sanitized = OpponentNameSanitizer.sanitize(longInput);
      expect(sanitized.length, 24);
      expect(sanitized, longInput.substring(0, 24));
    });

    test('geçerli adları ve bot adlarını aynen korur', () {
      expect(OpponentNameSanitizer.sanitize('M-1234'), 'M-1234');
      expect(OpponentNameSanitizer.sanitize('M-9999'), 'M-9999');
      expect(OpponentNameSanitizer.sanitize('MustafaKemalettin123'), 'MustafaKemalettin123');
    });
  });
}
