import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/attempt_text_sanitizer.dart';

Directory _resolveSharedVectorsDir() {
  final candidate1 = Directory('../shared/test-vectors');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = Directory('shared/test-vectors');
  if (candidate2.existsSync()) return candidate2;

  final candidate3 = Directory('../../shared/test-vectors');
  if (candidate3.existsSync()) return candidate3;

  throw StateError('shared/test-vectors dizini bulunamadı!');
}

void main() {
  group('AttemptTextSanitizer', () {
    test('baştaki ve sondaki boşlukları siler (trim)', () {
      expect(AttemptTextSanitizer.sanitize('  elma  '), 'elma');
      expect(AttemptTextSanitizer.sanitize('\t\n armut \r\n'), 'armut');
    });

    test('ardışık boşlukları tek boşluğa indirir', () {
      expect(AttemptTextSanitizer.sanitize('kırmızı   elma'), 'kırmızı elma');
      expect(
        AttemptTextSanitizer.sanitize('bir    iki   üç   dört'),
        'bir iki üç dört',
      );
      expect(
        AttemptTextSanitizer.sanitize('boşluk \t\t\n ayırma'),
        'boşluk ayırma',
      );
    });

    test('40 karakteri aşan metinleri 40 karaktere kırpar', () {
      final longText = 'a' * 50;
      final sanitized = AttemptTextSanitizer.sanitize(longText);
      expect(sanitized.length, 40);
      expect(sanitized, 'a' * 40);
    });

    test('ardışık boşluklar daraltıldıktan sonra 40 karakter sınırını kontrol eder', () {
      final textWithSpaces = '${'a' * 30}          ${'b' * 30}';
      final sanitized = AttemptTextSanitizer.sanitize(textWithSpaces);
      expect(sanitized.length, 40);
      expect(sanitized, '${'a' * 30} ${'b' * 9}');
    });

    test('boş metin veya yalnızca boşluk içeren metin boş döner', () {
      expect(AttemptTextSanitizer.sanitize(''), '');
      expect(AttemptTextSanitizer.sanitize('   '), '');
      expect(AttemptTextSanitizer.sanitize('\n\t  \r'), '');
    });

    test('40 karakter veya altındaki metinler olduğu gibi korunur', () {
      expect(AttemptTextSanitizer.sanitize('kara kartal'), 'kara kartal');
      final exactly40 = 'x' * 40;
      expect(AttemptTextSanitizer.sanitize(exactly40), exactly40);
    });

    test('shared/test-vectors/sanitizer.json test vektörlerinin tamamı geçer', () {
      final dir = _resolveSharedVectorsDir();
      final file = File('${dir.path}/sanitizer.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();

      expect(cases.length, greaterThanOrEqualTo(15));

      for (final tc in cases) {
        final id = tc['id'] as String;
        final input = tc['input'] as String;
        final expected = tc['expected'] as String;
        final actual = AttemptTextSanitizer.sanitize(input);
        expect(actual, expected, reason: 'Test case $id failed for input "$input"');
      }
    });
  });
}

