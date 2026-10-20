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

enum MatchEndReason {
  normal,
  terk,
  baglantiKoptu,
  rakipTerk,
  rakipBaglantiKoptu,
}

class MatchHistoryEntry {
  final String id;
  final String? matchId;
  final String opponentName;
  final int finishedAtMs;
  final int myScore;
  final int opponentScore;
  final MatchResult result;
  final MatchEndType endType;
  final MatchEndReason endReason;
  final String? forfeitedPlayerId;
  final List<RoundRecord> roundRecords;
  final List<String> roundQuestionTexts;
  final bool botlaOynandi;
  final bool isFinal;
  final bool isFriendly;

  const MatchHistoryEntry({
    required this.id,
    this.matchId,
    required this.opponentName,
    required this.finishedAtMs,
    required this.myScore,
    required this.opponentScore,
    required this.result,
    required this.endType,
    MatchEndReason? endReason,
    this.forfeitedPlayerId,
    required this.roundRecords,
    this.roundQuestionTexts = const [],
    this.botlaOynandi = false,
    this.isFinal = true,
    this.isFriendly = false,
  }) : endReason = endReason ??
            (endType == MatchEndType.forfeit
                ? (result == MatchResult.win
                    ? MatchEndReason.rakipTerk
                    : MatchEndReason.terk)
                : MatchEndReason.normal);

  String questionTextForRound(int index, {String fallback = 'Soru'}) {
    if (index >= 0 && index < roundQuestionTexts.length) {
      final text = roundQuestionTexts[index].trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}

