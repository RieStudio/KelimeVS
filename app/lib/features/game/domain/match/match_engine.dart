// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'dart:math' as math;

import '../answer_matcher.dart';
import '../models.dart';
import '../text_normalizer.dart';
import 'match_config.dart';
import 'match_events.dart';
import 'match_state.dart';
import 'near_miss.dart';

class EngineResult {
  final MatchState state;
  final List<MatchEvent> events;

  const EngineResult(this.state, this.events);
}

abstract final class MatchEngine {
  /// Yeni bir maç başlatır.
  static EngineResult start({
    required MatchConfig config,
    required List<String> playerIds,
    required List<Question> questions,
    required math.Random random,
    required int nowMs,
  }) {
    if (playerIds.length != 2) {
      throw ArgumentError('Maç tam olarak 2 oyuncu ile başlatılmalıdır.');
    }
    if (questions.isEmpty) {
      throw ArgumentError('Soru havuzu boş olamaz.');
    }

    final initialScores = {
      playerIds[0]: 0,
      playerIds[1]: 0,
    };

    final eligibleQuestions = _filterQuestions(questions, config.minAnswersPerQuestion);
    if (eligibleQuestions.isEmpty) {
      throw ArgumentError(
        'Eşik (${config.minAnswersPerQuestion} cevap) sonrası havuzda yeterli soru bulunamadı.',
      );
    }

    final question = _pickNextQuestion(
      questions: eligibleQuestions,
      usedQuestionIds: {},
      random: random,
    );

    final starterPlayerId = playerIds[0]; // Tur 0: ilk oyuncu başlar

    final state = MatchState(
      config: config,
      playerIds: List.unmodifiable(playerIds),
      scores: Map.unmodifiable(initialScores),
      decisiveRounds: 0,
      totalRoundsPlayed: 0,
      phase: MatchPhase.roundActive,
      currentQuestion: question,
      usedAnswerIds: const {},
      turnPlayerId: starterPlayerId,
      deadlineMs: nowMs + config.answerSeconds * 1000,
      remainingNearMisses: {
        playerIds[0]: config.nearMissPerRound,
        playerIds[1]: config.nearMissPerRound,
      },
      usedQuestionIds: {question.id},
      roundHistory: const [],
      currentRoundAttempts: const [],
      winnerId: null,
    );

    return EngineResult(state, const []);
  }

  /// Aktif turda oyuncunun cevabını işler.
  static EngineResult submit({
    required MatchState state,
    required String playerId,
    required String rawInput,
    required int nowMs,
    List<Question>? questionsPool,
    math.Random? random,
  }) {
    if (state.phase != MatchPhase.roundActive) {
      return EngineResult(state, [const Ignored('round_not_active')]);
    }

    // 1. Sırası olmayan oyuncunun cevabı yoksayılır
    if (playerId != state.turnPlayerId) {
      return EngineResult(state, [const Ignored('not_player_turn')]);
    }

    // 2. Süre kontrolü (Süre dolmuşsa cevap ne olursa olsun timeout)
    if (_isTimedOut(state, nowMs)) {
      final timedOutPlayerId = state.turnPlayerId!;
      final winnerId = state.opponentOf(timedOutPlayerId);
      final attempt = TurnAttempt(
        playerId: timedOutPlayerId,
        rawInput: rawInput,
        resultType: AttemptResultType.timeout,
        nowMs: nowMs,
      );
      return _endRound(
        state: state,
        winnerId: winnerId,
        reason: RoundEndReason.timeout,
        attempt: attempt,
      );
    }

    // 3. Normalizasyon ve boşluk kontrolü
    final normalized = TextNormalizer.normalize(rawInput);
    if (normalized.isEmpty) {
      return EngineResult(state, [const Ignored('empty_input')]);
    }

    final question = state.currentQuestion!;
    final matcher = AnswerMatcher(question);
    final matchResult = matcher.check(rawInput, state.usedAnswerIds);

    switch (matchResult) {
      case MatchResultCorrect(:final answer):
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: rawInput,
          resultType: AttemptResultType.correct,
          answerId: answer.id,
          nowMs: nowMs,
        );

        final updatedUsedAnswerIds = {...state.usedAnswerIds, answer.id};
        final updatedAttempts = [...state.currentRoundAttempts, attempt];

        // Soru cevapları tükendi mi kontrolü
        if (matcher.isExhausted(updatedUsedAnswerIds)) {
          // Tüm cevaplar tükendi -> Tur BERABERE biter
          final intermediateState = state.copyWith(
            usedAnswerIds: updatedUsedAnswerIds,
            currentRoundAttempts: updatedAttempts,
          );
          return _endRound(
            state: intermediateState,
            winnerId: null, // Berabere
            reason: RoundEndReason.exhausted,
            attempt: attempt,
            alreadyAppendedAttempt: true,
            prefixEvents: [AnswerAccepted(playerId, answer.display)],
          );
        }

        // Sıra rakibe geçer, süre sıfırlanır
        final opponentId = state.opponentOf(playerId);
        final nextDeadlineMs = nowMs + state.config.answerSeconds * 1000;

        final nextState = state.copyWith(
          usedAnswerIds: updatedUsedAnswerIds,
          turnPlayerId: opponentId,
          deadlineMs: nextDeadlineMs,
          currentRoundAttempts: updatedAttempts,
        );

        return EngineResult(nextState, [
          AnswerAccepted(playerId, answer.display),
        ]);

      case MatchResultRepeated(:final answer):
        // Daha önce söylenmiş cevap -> Oyuncu turu kaybeder
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: rawInput,
          resultType: AttemptResultType.repeated,
          answerId: answer.id,
          nowMs: nowMs,
        );
        final winnerId = state.opponentOf(playerId);
        return _endRound(
          state: state,
          winnerId: winnerId,
          reason: RoundEndReason.repeated,
          attempt: attempt,
        );

      case MatchResultWrong():
        // Önce "Çok Yakın" kontrolü yapılır
        final playerQuota = state.remainingNearMisses[playerId] ?? 0;

        if (playerQuota > 0) {
          final unusedAliases = question.answers
              .where((a) => !state.usedAnswerIds.contains(a.id))
              .map((a) => a.aliases);

          final nearMissFound = NearMissCalculator.isNearMiss(
            normalizedInput: normalized,
            unusedAnswerAliases: unusedAliases,
          );

          if (nearMissFound) {
            // Sonuç NearMiss: hak düşer, tur kaybedilmez, sıra ve süre DEĞİŞMEZ
            final updatedNearMisses = Map<String, int>.from(state.remainingNearMisses);
            updatedNearMisses[playerId] = playerQuota - 1;

            final attempt = TurnAttempt(
              playerId: playerId,
              rawInput: rawInput,
              resultType: AttemptResultType.nearMiss,
              nowMs: nowMs,
            );

            final nextState = state.copyWith(
              remainingNearMisses: updatedNearMisses,
              currentRoundAttempts: [...state.currentRoundAttempts, attempt],
            );

            return EngineResult(nextState, [NearMiss(playerId)]);
          }
        }

        // Çok yakın değil veya hakkı bitti -> Oyuncu turu kaybeder
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: rawInput,
          resultType: AttemptResultType.wrong,
          nowMs: nowMs,
        );
        final winnerId = state.opponentOf(playerId);
        return _endRound(
          state: state,
          winnerId: winnerId,
          reason: RoundEndReason.wrong,
          attempt: attempt,
        );

      case MatchResultEmpty():
        return EngineResult(state, [const Ignored('empty_input')]);
    }
  }

  /// Süre aşımını kontrol eder (arayüz periyodik çağırır).
  static EngineResult checkTimeout({
    required MatchState state,
    required int nowMs,
  }) {
    if (state.phase != MatchPhase.roundActive) {
      return EngineResult(state, const []);
    }

    if (_isTimedOut(state, nowMs)) {
      final timedOutPlayerId = state.turnPlayerId!;
      final winnerId = state.opponentOf(timedOutPlayerId);
      final attempt = TurnAttempt(
        playerId: timedOutPlayerId,
        rawInput: '',
        resultType: AttemptResultType.timeout,
        nowMs: nowMs,
      );
      return _endRound(
        state: state,
        winnerId: winnerId,
        reason: RoundEndReason.timeout,
        attempt: attempt,
      );
    }

    return EngineResult(state, const []);
  }

  /// Tur bittikten sonra (roundEnded fazında) bir sonraki turu başlatır.
  static EngineResult startNextRound({
    required MatchState state,
    required List<Question> questions,
    required math.Random random,
    required int nowMs,
  }) {
    if (state.phase != MatchPhase.roundEnded) {
      return EngineResult(state, [const Ignored('round_not_ended')]);
    }

    final eligibleQuestions = _filterQuestions(questions, state.config.minAnswersPerQuestion);
    if (eligibleQuestions.isEmpty) {
      throw StateError(
        'Eşik (${state.config.minAnswersPerQuestion} cevap) sonrası havuzda yeterli soru bulunamadı.',
      );
    }

    final nextQuestion = _pickNextQuestion(
      questions: eligibleQuestions,
      usedQuestionIds: state.usedQuestionIds,
      roundHistory: state.roundHistory,
      random: random,
    );

    // Turu başlatan oyuncu toplam oynanan tur sayısına göre sırayla değişir
    final starterIndex = state.totalRoundsPlayed % 2;
    final starterPlayerId = state.playerIds[starterIndex];

    final updatedNearMisses = {
      state.playerIds[0]: state.config.nearMissPerRound,
      state.playerIds[1]: state.config.nearMissPerRound,
    };

    final nextState = state.copyWith(
      phase: MatchPhase.roundActive,
      currentQuestion: nextQuestion,
      usedAnswerIds: const {},
      turnPlayerId: starterPlayerId,
      deadlineMs: nowMs + state.config.answerSeconds * 1000,
      remainingNearMisses: updatedNearMisses,
      usedQuestionIds: {...state.usedQuestionIds, nextQuestion.id},
      currentRoundAttempts: const [],
    );

    return EngineResult(nextState, const []);
  }

  // --- Yardımcı Metodlar ---

  static bool _isTimedOut(MatchState state, int nowMs) {
    return nowMs > state.deadlineMs + state.config.graceMs;
  }

  static EngineResult _endRound({
    required MatchState state,
    required String? winnerId,
    required RoundEndReason reason,
    required TurnAttempt attempt,
    bool alreadyAppendedAttempt = false,
    List<MatchEvent> prefixEvents = const [],
  }) {
    final attempts = alreadyAppendedAttempt
        ? state.currentRoundAttempts
        : [...state.currentRoundAttempts, attempt];

    final starterIndex = state.totalRoundsPlayed % 2;
    final starterPlayerId = state.playerIds[starterIndex];

    final roundRecord = RoundRecord(
      questionId: state.currentQuestion!.id,
      starterPlayerId: starterPlayerId,
      attempts: attempts,
      winnerId: winnerId,
      reason: reason,
    );

    final updatedScores = Map<String, int>.from(state.scores);
    var updatedDecisiveRounds = state.decisiveRounds;

    final List<MatchEvent> events = [...prefixEvents];

    if (winnerId != null) {
      updatedScores[winnerId] = (updatedScores[winnerId] ?? 0) + 1;
      updatedDecisiveRounds++;
      events.add(RoundWon(winnerId, reason));
    } else {
      events.add(RoundDrawn(reason));
    }

    final updatedTotalRoundsPlayed = state.totalRoundsPlayed + 1;
    final updatedRoundHistory = [...state.roundHistory, roundRecord];

    // 3 sonuçlanan tur bitti mi?
    if (updatedDecisiveRounds >= state.config.totalDecisiveRounds) {
      final p1 = state.playerIds[0];
      final p2 = state.playerIds[1];
      final s1 = updatedScores[p1] ?? 0;
      final s2 = updatedScores[p2] ?? 0;

      final matchWinnerId = s1 > s2 ? p1 : p2;

      events.add(MatchFinished(matchWinnerId));

      final finishedState = state.copyWith(
        scores: Map.unmodifiable(updatedScores),
        decisiveRounds: updatedDecisiveRounds,
        totalRoundsPlayed: updatedTotalRoundsPlayed,
        phase: MatchPhase.matchFinished,
        roundHistory: updatedRoundHistory,
        currentRoundAttempts: attempts,
        winnerId: matchWinnerId,
      );

      return EngineResult(finishedState, events);
    }

    // Henüz maç bitmedi, ara tur bitti
    final endedState = state.copyWith(
      scores: Map.unmodifiable(updatedScores),
      decisiveRounds: updatedDecisiveRounds,
      totalRoundsPlayed: updatedTotalRoundsPlayed,
      phase: MatchPhase.roundEnded,
      roundHistory: updatedRoundHistory,
      currentRoundAttempts: attempts,
    );

    return EngineResult(endedState, events);
  }

  static Question _pickNextQuestion({
    required List<Question> questions,
    required Set<String> usedQuestionIds,
    List<RoundRecord> roundHistory = const [],
    required math.Random random,
  }) {
    final unused = questions.where((q) => !usedQuestionIds.contains(q.id)).toList();
    if (unused.isNotEmpty) {
      return unused[random.nextInt(unused.length)];
    }
    // Soru havuzu biterse en az kullanılandan devam et
    final counts = <String, int>{};
    for (final q in questions) {
      counts[q.id] = 0;
    }
    for (final r in roundHistory) {
      counts[r.questionId] = (counts[r.questionId] ?? 0) + 1;
    }
    final minCount = counts.values.isEmpty ? 0 : counts.values.reduce(math.min);
    final leastUsed = questions.where((q) => (counts[q.id] ?? 0) == minCount).toList();
    return leastUsed[random.nextInt(leastUsed.length)];
  }

  static List<Question> _filterQuestions(List<Question> questions, int minAnswers) {
    if (minAnswers <= 0) return questions;
    return questions.where((q) => q.answers.length >= minAnswers).toList();
  }
}
