// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'models.dart';

enum QuestionWarningType {
  duplicateAlias,
  subwordConflict,
  fewAnswers,
}

class QuestionValidationWarning {
  final String questionId;
  final String questionText;
  final QuestionWarningType type;
  final String message;

  const QuestionValidationWarning({
    required this.questionId,
    required this.questionText,
    required this.type,
    required this.message,
  });

  @override
  String toString() => '[$type] Soru ($questionId): $message';
}

class QuestionValidator {
  /// Bir soru için CMS içerik uyarılarını toplar.
  static List<QuestionValidationWarning> validate(Question question) {
    final List<QuestionValidationWarning> warnings = [];

    // 1. Bir soruda 3'ten az cevap var
    if (question.answers.length < 3) {
      warnings.add(QuestionValidationWarning(
        questionId: question.id,
        questionText: question.text,
        type: QuestionWarningType.fewAnswers,
        message:
            'Soruda 3\'ten az cevap var (Mevcut cevap sayısı: ${question.answers.length}).',
      ));
    }

    // 2. Aynı normalleştirilmiş alias iki farklı cevapta geçiyor
    final Map<String, Answer> seenAliases = {};
    for (final answer in question.answers) {
      final allAliases = {answer.id, ...answer.aliases};
      for (final alias in allAliases) {
        if (alias.isEmpty) continue;

        if (seenAliases.containsKey(alias)) {
          final firstAnswer = seenAliases[alias]!;
          if (firstAnswer.id != answer.id) {
            warnings.add(QuestionValidationWarning(
              questionId: question.id,
              questionText: question.text,
              type: QuestionWarningType.duplicateAlias,
              message:
                  'Aynı alias ("$alias") hem "${firstAnswer.display}" hem de "${answer.display}" cevaplarında geçiyor.',
            ));
          }
        } else {
          seenAliases[alias] = answer;
        }
      }
    }

    // 3. Bir cevabın normalleştirilmiş hâli başka bir cevabın kelime sınırında başı veya sonu
    // (örn. "kore" ve "güney kore"): olası aynı cevap.
    for (int i = 0; i < question.answers.length; i++) {
      for (int j = i + 1; j < question.answers.length; j++) {
        final a = question.answers[i];
        final b = question.answers[j];
        if (a.id == b.id || a.id.isEmpty || b.id.isEmpty) continue;

        final aIsPrefixOfB = b.id.startsWith('${a.id} ');
        final aIsSuffixOfB = b.id.endsWith(' ${a.id}');
        final bIsPrefixOfA = a.id.startsWith('${b.id} ');
        final bIsSuffixOfA = a.id.endsWith(' ${b.id}');

        if (aIsPrefixOfB || aIsSuffixOfB || bIsPrefixOfA || bIsSuffixOfA) {
          warnings.add(QuestionValidationWarning(
            questionId: question.id,
            questionText: question.text,
            type: QuestionWarningType.subwordConflict,
            message:
                'Olası aynı cevap / kelime sınırı çakışması: "${a.display}" ve "${b.display}".',
          ));
        }
      }
    }

    return warnings;
  }

  /// Tüm soruları doğrulayıp birleşik uyarı listesi döndürür.
  static List<QuestionValidationWarning> validateAll(List<Question> questions) {
    final List<QuestionValidationWarning> allWarnings = [];
    for (final q in questions) {
      allWarnings.addAll(validate(q));
    }
    return allWarnings;
  }
}

