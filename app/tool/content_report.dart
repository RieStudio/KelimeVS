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
}

