// Saf Dart - Flutter, Riverpod veya SharedPreferences bağımlılığı yoktur.

import '../match/match_state.dart';

enum MatchResult {
  win,
  lose,
}

enum MatchEndType {
  normal,
  forfeit,
}

class MatchHistoryEntry {
  final String id;
  final String opponentName;
  final int finishedAtMs;
  final int myScore;
  final int opponentScore;
  final MatchResult result;
  final MatchEndType endType;
  final String? forfeitedPlayerId;
  final List<RoundRecord> roundRecords;
  final List<String> roundQuestionTexts;

  const MatchHistoryEntry({
    required this.id,
    required this.opponentName,
    required this.finishedAtMs,
    required this.myScore,
    required this.opponentScore,
    required this.result,
    required this.endType,
    this.forfeitedPlayerId,
    required this.roundRecords,
    this.roundQuestionTexts = const [],
  });

  String questionTextForRound(int index, {String fallback = 'Soru'}) {
    if (index >= 0 && index < roundQuestionTexts.length) {
      final text = roundQuestionTexts[index].trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}

