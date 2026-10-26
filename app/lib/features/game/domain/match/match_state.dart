// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import '../models.dart';
import 'match_config.dart';
import 'match_events.dart';

enum MatchPhase {
  roundActive,
  roundEnded,
  matchFinished,
}

enum AttemptResultType {
  correct,
  repeated,
  wrong,
  nearMiss,
  timeout,
}

class TurnAttempt {
  final String playerId;
  final String rawInput;
  final AttemptResultType resultType;
  final String? answerId;
  final int nowMs;
  final bool isClose;
  final bool hintShown;

  const TurnAttempt({
    required this.playerId,
    required this.rawInput,
    required this.resultType,
    this.answerId,
    required this.nowMs,
    this.isClose = false,
    this.hintShown = false,
  });
}

class RoundRecord {
  final String questionId;
  final String starterPlayerId;
  final List<TurnAttempt> attempts;
  final String? winnerId; // Beraberlik durumunda null
  final RoundEndReason reason;

  const RoundRecord({
    required this.questionId,
    required this.starterPlayerId,
    required this.attempts,
    required this.winnerId,
    required this.reason,
  });
}

/// Saf fonksiyon: Tur aktifken (`roundActive == true`):
/// - Tekrarlanan deneme (`resultType == AttemptResultType.repeated`): HERKESE gizlidir (ne rakip ne sahibi balon olarak görür).
/// - İpucu verilen yakın deneme (`hintShown == true`): HERKESE gizlidir (ne rakip ne sahibi balon olarak görür).
/// - İpucu verilmemiş yakın deneme (`isClose == true, hintShown == false`): rakibe gizlidir, sahibine normal kırmızı balon olarak görünür.
/// - Yakın olmayan yanlış denemeler (`isClose == false`): herkese görünür.
/// Tur bitince (`roundActive == false`) tüm denemeler herkese görünür.
List<TurnAttempt> visibleAttempts(
  RoundRecord round,
  String viewerId,
  bool roundActive,
) {
  if (!roundActive) {
    return round.attempts;
  }
  return round.attempts.where((attempt) {
    if (attempt.resultType == AttemptResultType.repeated) {
      return false; // Tekrarlanan cevap aktif turda chat akışına girmez (herkese gizli)
    }
    if (attempt.hintShown) {
      return false; // İpucu verilen yakın deneme aktif turda HERKESE gizli
    }
    if (attempt.playerId == viewerId) {
      return true; // Sahibi görür (hintShown false olan yakın veya normal denemeler)
    }
    return !attempt.isClose; // Rakibe isClose denemeleri gizli
  }).toList();
}

class MatchState {
  final MatchConfig config;
  final List<String> playerIds;
  final Map<String, int> scores;
  final int decisiveRounds;
  final int totalRoundsPlayed;
  final MatchPhase phase;
  final Question? currentQuestion;
  final Set<String> usedAnswerIds;
  final String? turnPlayerId;
  final int deadlineMs;
  final Map<String, int> remainingNearMisses;
  final Set<String> usedQuestionIds;
  final List<RoundRecord> roundHistory;
  final List<TurnAttempt> currentRoundAttempts;
  final String? winnerId;
  final Map<String, int> lastSubmitTimes;
  final int currentTurnAttempts;
  final String? endedBy;

  const MatchState({
    required this.config,
    required this.playerIds,
    required this.scores,
    required this.decisiveRounds,
    required this.totalRoundsPlayed,
    required this.phase,
    required this.currentQuestion,
    required this.usedAnswerIds,
    required this.turnPlayerId,
    required this.deadlineMs,
    required this.remainingNearMisses,
    required this.usedQuestionIds,
    required this.roundHistory,
    required this.currentRoundAttempts,
    this.winnerId,
    this.lastSubmitTimes = const {},
    this.currentTurnAttempts = 0,
    this.endedBy,
    this.questionOrder,
  });

  final List<String>? questionOrder;

  String opponentOf(String playerId) {
    if (playerIds.length != 2) {
      throw StateError('Maçta tam olarak 2 oyuncu olmalıdır');
    }
    return playerIds[0] == playerId ? playerIds[1] : playerIds[0];
  }

  RoundRecord get currentRoundRecord => RoundRecord(
        questionId: currentQuestion?.id ?? '',
        starterPlayerId:
            playerIds.isNotEmpty ? playerIds[totalRoundsPlayed % 2] : '',
        attempts: currentRoundAttempts,
        winnerId: winnerId,
        reason: RoundEndReason.timeout,
      );

  MatchState copyWith({
    MatchConfig? config,
    List<String>? playerIds,
    Map<String, int>? scores,
    int? decisiveRounds,
    int? totalRoundsPlayed,
    MatchPhase? phase,
    Question? currentQuestion,
    Set<String>? usedAnswerIds,
    String? turnPlayerId,
    int? deadlineMs,
    Map<String, int>? remainingNearMisses,
    Set<String>? usedQuestionIds,
    List<RoundRecord>? roundHistory,
    List<TurnAttempt>? currentRoundAttempts,
    String? winnerId,
    Map<String, int>? lastSubmitTimes,
    int? currentTurnAttempts,
    String? endedBy,
    List<String>? questionOrder,
  }) {
    return MatchState(
      config: config ?? this.config,
      playerIds: playerIds ?? this.playerIds,
      scores: scores ?? this.scores,
      decisiveRounds: decisiveRounds ?? this.decisiveRounds,
      totalRoundsPlayed: totalRoundsPlayed ?? this.totalRoundsPlayed,
      phase: phase ?? this.phase,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      usedAnswerIds: usedAnswerIds ?? this.usedAnswerIds,
      turnPlayerId: turnPlayerId ?? this.turnPlayerId,
      deadlineMs: deadlineMs ?? this.deadlineMs,
      remainingNearMisses: remainingNearMisses ?? this.remainingNearMisses,
      usedQuestionIds: usedQuestionIds ?? this.usedQuestionIds,
      roundHistory: roundHistory ?? this.roundHistory,
      currentRoundAttempts: currentRoundAttempts ?? this.currentRoundAttempts,
      winnerId: winnerId ?? this.winnerId,
      lastSubmitTimes: lastSubmitTimes ?? this.lastSubmitTimes,
      currentTurnAttempts: currentTurnAttempts ?? this.currentTurnAttempts,
      endedBy: endedBy ?? this.endedBy,
      questionOrder: questionOrder ?? this.questionOrder,
    );
  }
}
