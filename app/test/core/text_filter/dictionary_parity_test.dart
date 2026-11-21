import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/text_filter/app_text_filter.dart';
import 'package:app/features/game/domain/models.dart';

void main() {
  group('Dictionary Parity Test (Zero False Positives in questions.json)', () {
    late AppTextFilter filter;
    late List<Question> questions;

    setUpAll(() {
      File? blocklistFile;
      for (final p in [
        'assets/text_filter/blocklist.json',
        'app/assets/text_filter/blocklist.json',
        '../app/assets/text_filter/blocklist.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          blocklistFile = f;
          break;
        }
      }
      expect(blocklistFile, isNotNull);
      final blocklistJson = json.decode(blocklistFile!.readAsStringSync()) as Map<String, dynamic>;
      filter = AppTextFilter.fromJson(blocklistJson);

      File? questionsFile;
      for (final p in [
        'assets/questions/questions.json',
        'app/assets/questions/questions.json',
        'assets/dev/questions.json',
        'app/assets/dev/questions.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          questionsFile = f;
          break;
        }
      }
      expect(questionsFile, isNotNull);
      final dynamic decoded = json.decode(questionsFile!.readAsStringSync());
      questions = Question.parseQuestionsPool(decoded as Map<String, dynamic>);
    });

    test('Soru havuzundaki tüm meşru cevaplar maskelenmeden korunur (0 yanlış pozitif)', () {
      int totalAnswers = 0;
      final falsePositives = <String>[];

      for (final q in questions) {
        for (final answer in q.answers) {
          totalAnswers++;
          final display = answer.display;
          final masked = filter.apply(display);
          if (masked != display) {
            falsePositives.add('Soru "${q.id}": "$display" -> "$masked"');
          }
        }
      }

      // ignore: avoid_print
      print('Toplam denetlenen meşru sözlük cevabı: $totalAnswers');
      expect(totalAnswers, greaterThan(1000));
      expect(
        falsePositives,
        isEmpty,
        reason: 'Sözlükteki meşru cevaplar maskelenmemelidir:\n${falsePositives.join('\n')}',
      );
    });
  });
}
