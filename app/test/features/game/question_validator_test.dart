import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/question_validator.dart';

void main() {
  group('QuestionValidator tests', () {
    test('yapay bir soruda "kore" + "güney kore" için uyarı üretir', () {
      const question = Question(
        id: 'mock_q',
        categoryId: 'c1',
        text: 'Uzak Doğu ülkeleri',
        answers: [
          Answer(
            id: 'kore',
            display: 'Kore',
            aliases: ['kore'],
          ),
          Answer(
            id: 'guney kore',
            display: 'Güney Kore',
            aliases: ['guney kore'],
          ),
          Answer(
            id: 'japonya',
            display: 'Japonya',
            aliases: ['japonya'],
          ),
        ],
      );

      final warnings = QuestionValidator.validate(question);
      expect(warnings, isNotEmpty);
      expect(
        warnings.any((w) => w.type == QuestionWarningType.subwordConflict),
        isTrue,
      );
    });

    test('3\'ten az cevap için uyarı üretir', () {
      const question = Question(
        id: 'few_answers_q',
        categoryId: 'c1',
        text: 'Az cevaplı soru',
        answers: [
          Answer(id: 'a', display: 'A', aliases: ['a']),
          Answer(id: 'b', display: 'B', aliases: ['b']),
        ],
      );

      final warnings = QuestionValidator.validate(question);
      expect(
        warnings.any((w) => w.type == QuestionWarningType.fewAnswers),
        isTrue,
      );
    });

    test('Aynı alias iki farklı cevapta geçince uyarı üretir', () {
      const question = Question(
        id: 'dup_alias_q',
        categoryId: 'c1',
        text: 'Alias çakışmalı soru',
        answers: [
          Answer(id: 'hollanda', display: 'Hollanda', aliases: ['flemenk']),
          Answer(id: 'belcika', display: 'Belçika', aliases: ['flemenk']),
          Answer(id: 'almanya', display: 'Almanya', aliases: ['almanya']),
        ],
      );

      final warnings = QuestionValidator.validate(question);
      expect(
        warnings.any((w) => w.type == QuestionWarningType.duplicateAlias),
        isTrue,
      );
    });

    test('gerçek questions.json üzerinde çalışır ve uyarıları konsola yazdırır', () {
      File? file;
      for (final p in [
        'assets/dev/questions.json',
        'app/assets/dev/questions.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          file = f;
          break;
        }
      }

      expect(file, isNotNull, reason: 'questions.json dosyası mevcut olmalıdır.');

      final jsonContent = json.decode(file!.readAsStringSync()) as Map<String, dynamic>;
      final questions = Question.parseQuestionsPool(jsonContent);

      expect(questions, isNotEmpty);

      final warnings = QuestionValidator.validateAll(questions);

      // Uyarıları konsola yazdır (test başarısız edilmez)
      // ignore: avoid_print
      print('\n========================================');
      // ignore: avoid_print
      print('CMS İÇERİK DOĞRULAMA RAPORU');
      // ignore: avoid_print
      print('Toplam Soru Sayısı: ${questions.length}');
      // ignore: avoid_print
      print('Tespit Edilen Uyarı Sayısı: ${warnings.length}');
      // ignore: avoid_print
      print('----------------------------------------');
      for (final w in warnings) {
        // ignore: avoid_print
        print(w.toString());
      }
      // ignore: avoid_print
      print('========================================');
      // ignore: avoid_print
      print('OZET: Toplam Soru: ${questions.length}, Toplam Uyari: ${warnings.length}');
      // ignore: avoid_print
      print('========================================\n');
    });
  });
}

