// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'models.dart';
import 'text_normalizer.dart';

sealed class MatchResult {
  const MatchResult();

  const factory MatchResult.correct(Answer answer) = MatchResultCorrect;
  const factory MatchResult.repeated(Answer answer) = MatchResultRepeated;
  const factory MatchResult.wrong() = MatchResultWrong;
  const factory MatchResult.empty() = MatchResultEmpty;

  bool get isCorrect => this is MatchResultCorrect;
  bool get isRepeated => this is MatchResultRepeated;
  bool get isWrong => this is MatchResultWrong;
  bool get isEmpty => this is MatchResultEmpty;

  Answer? get answer => switch (this) {
        MatchResultCorrect(:final answer) => answer,
        MatchResultRepeated(:final answer) => answer,
        _ => null,
      };
}

class MatchResultCorrect extends MatchResult {
  @override
  final Answer answer;

  const MatchResultCorrect(this.answer);

  @override
  String toString() => 'MatchResult.correct(${answer.display})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchResultCorrect && other.answer == answer);

  @override
  int get hashCode => answer.hashCode;
}

class MatchResultRepeated extends MatchResult {
  @override
  final Answer answer;

  const MatchResultRepeated(this.answer);

  @override
  String toString() => 'MatchResult.repeated(${answer.display})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchResultRepeated && other.answer == answer);

  @override
  int get hashCode => answer.hashCode;
}

class MatchResultWrong extends MatchResult {
  const MatchResultWrong();

  @override
  String toString() => 'MatchResult.wrong()';

  @override
  bool operator ==(Object other) => other is MatchResultWrong;

  @override
  int get hashCode => 0;
}

class MatchResultEmpty extends MatchResult {
  const MatchResultEmpty();

  @override
  String toString() => 'MatchResult.empty()';

  @override
  bool operator ==(Object other) => other is MatchResultEmpty;

  @override
  int get hashCode => 1;
}

class AnswerMatcher {
  final Question question;
  final Map<String, Answer> _aliasIndex = {};

  AnswerMatcher(this.question) {
    for (final answer in question.answers) {
      // Ana cevap
      if (answer.id.isNotEmpty && !_aliasIndex.containsKey(answer.id)) {
        _aliasIndex[answer.id] = answer;
      }
      // Alias listesi
      for (final alias in answer.aliases) {
        if (alias.isNotEmpty && !_aliasIndex.containsKey(alias)) {
          _aliasIndex[alias] = answer;
        }
      }
    }
  }

  /// Girdiyi kontrol eder.
  /// Boş girdi -> empty
  /// Bulunamazsa -> wrong
  /// usedAnswerIds içinde varsa -> repeated
  /// İlk kez söyleniyorsa -> correct
  MatchResult check(String input, Set<String> usedAnswerIds) {
    final normalized = TextNormalizer.normalize(input);
    if (normalized.isEmpty) {
      return const MatchResult.empty();
    }

    final answer = _aliasIndex[normalized];
    if (answer == null) {
      return const MatchResult.wrong();
    }

    if (usedAnswerIds.contains(answer.id)) {
      return MatchResult.repeated(answer);
    }

    return MatchResult.correct(answer);
  }

  /// Henüz söylenmemiş cevap sayısı
  int remaining(Set<String> usedAnswerIds) {
    int count = 0;
    for (final answer in question.answers) {
      if (!usedAnswerIds.contains(answer.id)) {
        count++;
      }
    }
    return count;
  }

  /// Tüm cevaplar tükendi mi?
  bool isExhausted(Set<String> usedAnswerIds) {
    return remaining(usedAnswerIds) == 0;
  }
}

