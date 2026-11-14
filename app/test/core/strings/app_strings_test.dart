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

    group('emptyBlockedUsersSubtitle', () {
      test('profil ekranı yönlendirmesini içerir', () {
        expect(
          AppStrings.emptyBlockedUsersSubtitle,
          equals('Oyuncunun profilinden uygunsuz oyuncuları engelleyebilirsin.'),
        );
      });
    });
  });

  group('AppStrings Coin Reward Tests', () {
    test('pozitif jeton miktarları için +N jeton formatında döner', () {
      expect(AppStrings.coinReward(30), equals('+30 jeton'));
      expect(AppStrings.coinReward(10), equals('+10 jeton'));
      expect(AppStrings.coinReward(1), equals('+1 jeton'));
      expect(AppStrings.formatCoinReward(30), equals('+30 jeton'));
    });

    test('0 ve negatif jeton miktarları için 0 jeton formatında döner (+ işareti olmaz)', () {
      expect(AppStrings.coinReward(0), equals('0 jeton'));
      expect(AppStrings.coinReward(-5), equals('0 jeton'));
      expect(AppStrings.formatCoinReward(0), equals('0 jeton'));
    });
  });
}
