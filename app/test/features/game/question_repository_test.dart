import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/models.dart';

void main() {
  group('QuestionRepository data integrity tests', () {
    test('gerçek questions.json en az 1 kategori ve her soruda en az 1 cevap içerir', () {
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

      final categories = questions.map((q) => q.categoryId).toSet();
      expect(categories.length, greaterThanOrEqualTo(1));

      // ignore: avoid_print
      print('Yüklenen Kategori Sayısı: ${categories.length}, Toplam Soru Sayısı: ${questions.length}');

      for (final question in questions) {
        expect(
          question.answers.length,
          greaterThanOrEqualTo(1),
          reason: 'Soru (${question.id} - ${question.text}) en az 1 cevap içermelidir.',
        );
        expect(
          question.text.isNotEmpty,
          isTrue,
          reason: 'Soru (${question.id}) metni boş olamaz.',
        );
      }
    });
  });
}

