// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'text_normalizer.dart';

class Answer {
  /// Ana cevabın normalleştirilmiş hâli (kararlı, dahili kimlik)
  final String id;

  /// Ana cevap metni olduğu gibi
  final String display;

  /// Normalleştirilmiş alias listesi (ana cevap da dahil)
  final List<String> aliases;

  const Answer({
    required this.id,
    required this.display,
    required this.aliases,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Answer &&
          other.id == id &&
          other.display == display);

  @override
  int get hashCode => Object.hash(id, display);

  @override
  String toString() => 'Answer(id: $id, display: $display, aliases: $aliases)';
}

class Question {
  final String id;
  final String categoryId;
  final String text;
  final List<Answer> answers;

  const Question({
    required this.id,
    required this.categoryId,
    required this.text,
    required this.answers,
  });

  /// CMS havuz JSON verisini ayrıştırır.
  /// Üst düzeyde "questions_pool" varsa onu, yoksa verinin kendisini havuz kabul eder.
  /// "app", "version", "cms_categories" gibi harici alanları yok sayar.
  static List<Question> parseQuestionsPool(Map<String, dynamic> json) {
    final Map<String, dynamic> pool =
        json.containsKey('questions_pool') && json['questions_pool'] is Map<String, dynamic>
            ? json['questions_pool'] as Map<String, dynamic>
            : json;

    final List<Question> questions = [];

    pool.forEach((categoryId, categoryData) {
      if (categoryData is! Map<String, dynamic>) return;

      categoryData.forEach((questionId, questionData) {
        if (questionData is! Map<String, dynamic>) return;

        final rawQuestion = questionData['question'];
        if (rawQuestion == null) return;

        // Baştaki/sondaki ve ardışık boşlukları temizle
        final cleanText =
            rawQuestion.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

        final rawAnswers = questionData['acceptable_answers'];
        final List<Answer> answers = [];

        if (rawAnswers is Map<String, dynamic>) {
          rawAnswers.forEach((mainAnswerKey, rawAliases) {
            final display = mainAnswerKey.toString();
            final id = TextNormalizer.normalize(display);

            final List<String> normalizedAliases = [];

            // Ana cevap da alias indeksine dahil
            if (id.isNotEmpty) {
              normalizedAliases.add(id);
            }

            if (rawAliases is List) {
              for (final aliasItem in rawAliases) {
                final norm = TextNormalizer.normalize(aliasItem.toString());
                if (norm.isNotEmpty && !normalizedAliases.contains(norm)) {
                  normalizedAliases.add(norm);
                }
              }
            }

            answers.add(Answer(
              id: id,
              display: display,
              aliases: normalizedAliases,
            ));
          });
        }

        questions.add(Question(
          id: questionId,
          categoryId: categoryId,
          text: cleanText,
          answers: answers,
        ));
      });
    });

    return questions;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Question &&
          other.id == id &&
          other.categoryId == categoryId &&
          other.text == text);

  @override
  int get hashCode => Object.hash(id, categoryId, text);

  @override
  String toString() =>
      'Question(id: $id, categoryId: $categoryId, text: $text, answers: ${answers.length})';
}

