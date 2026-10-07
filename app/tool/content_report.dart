import 'dart:convert';
import 'dart:io';

import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/question_validator.dart';

class WarningEntry {
  final String category;
  final String questionText;
  final String warningType;
  final String detail;

  const WarningEntry({
    required this.category,
    required this.questionText,
    required this.warningType,
    required this.detail,
  });

  String format() {
    return '[$category] "$questionText" | $warningType | $detail';
  }
}

void main() {
  // 1. questions.json dosyasını dosya sisteminden oku
  File? questionsFile;
  const candidates = [
    'assets/dev/questions.json',
    'app/assets/dev/questions.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      questionsFile = file;
      break;
    }
  }

  if (questionsFile == null) {
    stderr.writeln('Hata: assets/dev/questions.json dosyası bulunamadı!');
    exit(1);
  }

  final jsonString = questionsFile.readAsStringSync();
  final Map<String, dynamic> jsonData = json.decode(jsonString) as Map<String, dynamic>;
  final List<Question> questions = Question.parseQuestionsPool(jsonData);

  // 2. QuestionValidator kullanarak her soru için uyarıları topla
  final List<WarningEntry> entries = [];
  final conflictRegex = RegExp(r'Olası aynı cevap / kelime sınırı çakışması: "(.*?)" ve "(.*?)"\.');
  final aliasRegex = RegExp(r'Aynı alias \("(.*?)"\) hem "(.*?)" hem de "(.*?)" cevaplarında geçiyor\.');
  final duplicateIdRegex = RegExp(
    r'İki farklı ana cevap aynı normalleştirilmiş kimliğe \("(.*?)"\) sahip: "(.*?)" ve "(.*?)"\.',
  );

  for (final question in questions) {
    final warnings = QuestionValidator.validate(question);
    for (final warning in warnings) {
      String detail;
      switch (warning.type) {
        case QuestionWarningType.duplicateId:
          final match = duplicateIdRegex.firstMatch(warning.message);
          if (match != null) {
            detail = '"${match.group(2)}" <-> "${match.group(3)}"';
          } else {
            detail = warning.message;
          }
          break;

        case QuestionWarningType.subwordConflict:
          final match = conflictRegex.firstMatch(warning.message);
          if (match != null) {
            detail = '"${match.group(1)}" <-> "${match.group(2)}"';
          } else {
            detail = warning.message;
          }
          break;

        case QuestionWarningType.duplicateAlias:
          final match = aliasRegex.firstMatch(warning.message);
          if (match != null) {
            detail = '"${match.group(2)}" <-> "${match.group(3)}" (alias: "${match.group(1)}")';
          } else {
            detail = warning.message;
          }
          break;

        case QuestionWarningType.fewAnswers:
          detail = 'Cevap sayısı: ${question.answers.length} < 3';
          break;
      }

      entries.add(WarningEntry(
        category: question.categoryId,
        questionText: question.text,
        warningType: warning.type.name,
        detail: detail,
      ));
    }
  }

  // 3. Satırları soru metnine göre sırala
  entries.sort((a, b) {
    final cmp = a.questionText.compareTo(b.questionText);
    if (cmp != 0) return cmp;
    return a.detail.compareTo(b.detail);
  });

  // 4. Çıktı dosyasını hazırla ve yaz
  final outputDir = Directory(
    Directory.current.path.endsWith('app') ? 'tool/output' : 'app/tool/output',
  );
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final outputFile = File('${outputDir.path}/content_warnings.txt');
  final buffer = StringBuffer();
  buffer.writeln('Toplam: ${entries.length}');
  for (final entry in entries) {
    buffer.writeln(entry.format());
  }

  outputFile.writeAsStringSync(buffer.toString());

  stdout.writeln('Rapor hazırlandı: ${outputFile.path}');
  stdout.writeln('Toplam Soru: ${questions.length}');
  stdout.writeln('Toplam Uyarı: ${entries.length}');

  // 5. Cevap sayısı (ana cevap sayısı) dağılımı
  final counts = questions.map((q) => q.answers.length).toList()..sort();
  final minCount = counts.isEmpty ? 0 : counts.first;
  final maxCount = counts.isEmpty ? 0 : counts.last;
  final sum = counts.fold<int>(0, (a, b) => a + b);
  final mean = counts.isEmpty ? 0.0 : sum / counts.length;
  final median = counts.isEmpty
      ? 0.0
      : (counts.length % 2 == 1
          ? counts[counts.length ~/ 2].toDouble()
          : (counts[(counts.length ~/ 2) - 1] + counts[counts.length ~/ 2]) / 2.0);

  int b0_4 = 0;
  int b5_9 = 0;
  int b10_14 = 0;
  int b15_19 = 0;
  int b20_29 = 0;
  int b30plus = 0;

  for (final c in counts) {
    if (c <= 4) {
      b0_4++;
    } else if (c <= 9) {
      b5_9++;
    } else if (c <= 14) {
      b10_14++;
    } else if (c <= 19) {
      b15_19++;
    } else if (c <= 29) {
      b20_29++;
    } else {
      b30plus++;
    }
  }

  final fewAnswerQuestions = questions.where((q) => q.answers.length < 10).toList()
    ..sort((a, b) {
      final cmp = a.answers.length.compareTo(b.answers.length);
      if (cmp != 0) return cmp;
      return a.text.compareTo(b.text);
    });

  stdout.writeln('\n========================================');
  stdout.writeln('    CEVAP SAYISI DAĞILIMI (${questions.length} Soru)    ');
  stdout.writeln('========================================');
  stdout.writeln('min      : $minCount');
  stdout.writeln('ortanca  : ${median.toStringAsFixed(1)}');
  stdout.writeln('ortalama : ${mean.toStringAsFixed(2)}');
  stdout.writeln('en büyük : $maxCount');
  stdout.writeln('\nHistogram (5\'lik aralıklar):');
  stdout.writeln('  0-4   : $b0_4 (%${(b0_4 / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('  5-9   : $b5_9 (%${(b5_9 / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('  10-14 : $b10_14 (%${(b10_14 / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('  15-19 : $b15_19 (%${(b15_19 / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('  20-29 : $b20_29 (%${(b20_29 / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('  30+   : $b30plus (%${(b30plus / questions.length * 100).toStringAsFixed(1)})');
  stdout.writeln('\nCevap Sayısı 10\'dan Az Olan Sorular (${fewAnswerQuestions.length} adet):');
  for (final q in fewAnswerQuestions) {
    stdout.writeln('[${q.categoryId}] "${q.text}" | ${q.answers.length}');
  }
  stdout.writeln('========================================');
}

