import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/profile/domain/nickname_validator.dart';
import 'package:app/features/profile/domain/profanity_words.dart';

Directory _resolveSharedVectorsDir() {
  final candidate1 = Directory('../shared/test-vectors');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = Directory('shared/test-vectors');
  if (candidate2.existsSync()) return candidate2;

  final candidate3 = Directory('../../shared/test-vectors');
  if (candidate3.existsSync()) return candidate3;

  throw StateError('shared/test-vectors dizini bulunamadı!');
}

File _resolveSharedFile(String relativePath) {
  final candidate1 = File('../shared/$relativePath');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = File('shared/$relativePath');
  if (candidate2.existsSync()) return candidate2;

  final candidate3 = File('../../shared/$relativePath');
  if (candidate3.existsSync()) return candidate3;

  throw StateError('shared/$relativePath dosyası bulunamadı!');
}

void main() {
  group('NicknameValidator - Shared Test Vectors & Profanity List', () {
    test('shared/profanity_words.json istemcideki profanityWords ile birebir eşleşmeli', () {
      final file = _resolveSharedFile('profanity_words.json');
      final list = (jsonDecode(file.readAsStringSync()) as List).cast<String>();
      expect(profanityWords, equals(list));
    });

    test('shared/test-vectors/nickname.json en az 25 test vektörü içermeli ve tümü geçmeli', () {
      final dir = _resolveSharedVectorsDir();
      final file = File('${dir.path}/nickname.json');
      expect(file.existsSync(), isTrue);

      final rawList = jsonDecode(file.readAsStringSync()) as List;
      expect(rawList.length, greaterThanOrEqualTo(25));

      for (int i = 0; i < rawList.length; i++) {
        final tc = rawList[i] as Map<String, dynamic>;
        final input = tc['input'] as String;
        final expectedValid = tc['valid'] as bool;
        final expectedNormalized = tc['normalized'] as String?;

        final res = NicknameValidator.validate(input);
        expect(
          res.isValid,
          equals(expectedValid),
          reason: 'Case #$i "$input" validlik uyuşmadı',
        );
        expect(
          res.normalized,
          equals(expectedNormalized),
          reason: 'Case #$i "$input" normalizasyon uyuşmadı',
        );
      }
    });

    test('Geçersiz durumlarda kullanıcıya uygun Türkçe hata mesajları döner', () {
      expect(
        NicknameValidator.validate('').errorMessage,
        equals('Lütfen bir takma ad girin.'),
      );
      expect(
        NicknameValidator.validate('   ').errorMessage,
        equals('Lütfen bir takma ad girin.'),
      );
      expect(
        NicknameValidator.validate('ab').errorMessage,
        equals('Takma ad en az 3 karakter olmalıdır.'),
      );
      expect(
        NicknameValidator.validate('12345678901234567').errorMessage,
        equals('Takma ad en fazla 16 karakter olabilir.'),
      );
      expect(
        NicknameValidator.validate('Ahmet@123').errorMessage,
        equals('Yalnızca harf, rakam, boşluk ve alt çizgi (_) kullanabilirsin.'),
      );
      expect(
        NicknameValidator.validate('kufurlu_biri').errorMessage,
        equals('Bu takma ad uygunsuz ifadeler içeriyor.'),
      );
    });
  });
}
