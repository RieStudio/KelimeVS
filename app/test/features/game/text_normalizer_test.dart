import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

void main() {
  group('TextNormalizer tests', () {
    test('Turkish I/ı letter normalization', () {
      expect(TextNormalizer.normalize('ISPANAK'), equals('ispanak'));
      expect(TextNormalizer.normalize('ıspanak'), equals('ispanak'));
      expect(TextNormalizer.normalize('Ispanak'), equals('ispanak'));
      expect(
        TextNormalizer.normalize('ISPANAK'),
        equals(TextNormalizer.normalize('ıspanak')),
      );
      expect(
        TextNormalizer.normalize('ISPANAK'),
        equals(TextNormalizer.normalize('Ispanak')),
      );
    });

    test('Turkish İ letter normalization', () {
      expect(TextNormalizer.normalize('İSTANBUL'), equals('istanbul'));
      expect(TextNormalizer.normalize('istanbul'), equals('istanbul'));
    });

    test('Accent folding (ç, ğ, ö, ş, ü, â, î, û)', () {
      expect(TextNormalizer.normalize('Türkiye'), equals('turkiye'));
      expect(TextNormalizer.normalize('hâlâ'), equals('hala'));
    });

    test('Whitespace and punctuation cleaning', () {
      expect(TextNormalizer.normalize('  güney   KORE '), equals('guney kore'));
      expect(TextNormalizer.normalize('dr. pepper'), equals('dr pepper'));
    });

    test('Empty and only-punctuation strings return empty string', () {
      expect(TextNormalizer.normalize(''), equals(''));
      expect(TextNormalizer.normalize('...'), equals(''));
      expect(TextNormalizer.normalize('   !?,.  '), equals(''));
    });

    test('Preserves + and # characters (c, c++, c# distinct)', () {
      expect(
        TextNormalizer.normalize('c++'),
        isNot(equals(TextNormalizer.normalize('c'))),
      );
      expect(
        TextNormalizer.normalize('c#'),
        isNot(equals(TextNormalizer.normalize('c'))),
      );
      expect(
        TextNormalizer.normalize('c++'),
        isNot(equals(TextNormalizer.normalize('c#'))),
      );
      expect(TextNormalizer.normalize('C++'), equals('c++'));
      expect(TextNormalizer.normalize('C#'), equals('c#'));
    });
  });
}


