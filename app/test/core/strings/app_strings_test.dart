import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';

void main() {
  group('AppStrings Block Strings Tests', () {
    group('blockDialogMessage', () {
      test('geçerli bir ad verildiğinde oyuncu adını içerir ve " adlı" ile başlamaz', () {
        final message = AppStrings.blockDialogMessage('Kılars');
        expect(message, contains('Kılars adlı oyuncuyu engellemek istediğinden emin misin?'));
        expect(message.startsWith(' adlı'), isFalse);
      });

      test('ad boş, whitespace veya null ise güvenli yedek metin döner', () {
        final fallback = 'Bu oyuncuyu engellemek istediğinden emin misin?\nBir daha bu oyuncuyla eşleştirilmeyeceksin.';

        expect(AppStrings.blockDialogMessage(''), equals(fallback));
        expect(AppStrings.blockDialogMessage('   '), equals(fallback));
        expect(AppStrings.blockDialogMessage(null), equals(fallback));
        expect(AppStrings.blockDialogMessage(), equals(fallback));
        expect(AppStrings.blockDialogMessage('').startsWith(' adlı'), isFalse);
      });
    });

    group('blockSuccess', () {
      test('geçerli bir ad verildiğinde adı içerir ve " engellendi." ile başlamaz', () {
        final msg = AppStrings.blockSuccess('Kılars');
        expect(msg, equals('Kılars engellendi.'));
      });

      test('ad boş, whitespace veya null ise "Oyuncu engellendi." döner', () {
        expect(AppStrings.blockSuccess(''), equals('Oyuncu engellendi.'));
        expect(AppStrings.blockSuccess('   '), equals('Oyuncu engellendi.'));
        expect(AppStrings.blockSuccess(null), equals('Oyuncu engellendi.'));
        expect(AppStrings.blockSuccess(), equals('Oyuncu engellendi.'));
      });
    });
  });
}
