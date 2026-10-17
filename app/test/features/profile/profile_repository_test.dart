import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/features/profile/data/profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalProfileRepository Tests', () {
    test('getNickname returns null when not set', () async {
      SharedPreferences.setMockInitialValues({});
      const repo = LocalProfileRepository();

      final nickname = await repo.getNickname();
      expect(nickname, isNull);

      final hasNick = await repo.hasNickname();
      expect(hasNick, isFalse);
    });

    test('getNickname returns null when empty or whitespace', () async {
      SharedPreferences.setMockInitialValues({
        LocalProfileRepository.keyNickname: '   ',
      });
      const repo = LocalProfileRepository();

      final nickname = await repo.getNickname();
      expect(nickname, isNull);

      final hasNick = await repo.hasNickname();
      expect(hasNick, isFalse);
    });

    test('setNickname stores trimmed string and hasNickname becomes true', () async {
      SharedPreferences.setMockInitialValues({});
      const repo = LocalProfileRepository();

      await repo.setNickname('  Ahmet_10  ');

      final nickname = await repo.getNickname();
      expect(nickname, 'Ahmet_10');

      final hasNick = await repo.hasNickname();
      expect(hasNick, isTrue);
    });
  });
}

