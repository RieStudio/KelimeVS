// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'dart:math' as math;

import '../answer_matcher.dart';
import '../attempt_text_sanitizer.dart';
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
    List<String>? questionOrder,
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
      questionOrder: questionOrder,
      roundIndex: 0,
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
      lastSubmitTimes: const {},
      currentTurnAttempts: 0,
      endedBy: null,
      questionOrder: questionOrder,
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
    // 0. Girdi temizleme (sanitization)
    final sanitizedInput = AttemptTextSanitizer.sanitize(rawInput);
    if (sanitizedInput.isEmpty) {
      return EngineResult(state, const [Ignored('empty_input')]);
    }

    if (state.phase != MatchPhase.roundActive) {
      return EngineResult(state, const [Ignored('round_not_active')]);
    }

    // 1. Sırası olmayan oyuncunun cevabı yoksayılır
    if (playerId != state.turnPlayerId) {
      return EngineResult(state, const [Ignored('not_player_turn')]);
    }

    // 2. Süre kontrolü (Süre dolmuşsa cevap ne olursa olsun timeout)
    if (_isTimedOut(state, nowMs)) {
      final timedOutPlayerId = state.turnPlayerId!;
      final winnerId = state.opponentOf(timedOutPlayerId);
      return _endRound(
        state: state,
        winnerId: winnerId,
        reason: RoundEndReason.timeout,
      );
    }

    // 3. Kötüye kullanım: minSubmitIntervalMs (600 ms) kontrolü
    final lastSubmit = state.lastSubmitTimes[playerId];
    if (lastSubmit != null && (nowMs - lastSubmit) < state.config.minSubmitIntervalMs) {
      return EngineResult(state, const [Ignored('tooFast')]);
    }

    // 4. Kötüye kullanım: maxAttemptsPerTurn (25 deneme) kontrolü
    if (state.currentTurnAttempts >= state.config.maxAttemptsPerTurn) {
      return EngineResult(state, const [Ignored('tooManyAttempts')]);
    }

    // 5. Normalizasyon ve boşluk kontrolü
    final normalized = TextNormalizer.normalize(sanitizedInput);
    if (normalized.isEmpty) {
      return EngineResult(state, const [Ignored('empty_input')]);
    }

    // Geçerli bir deneme yapılıyor -> zamanı ve deneme sayısını güncelle
    final updatedLastSubmitTimes = Map<String, int>.from(state.lastSubmitTimes)..[playerId] = nowMs;
    final updatedTurnAttempts = state.currentTurnAttempts + 1;

    final question = state.currentQuestion!;
    final matcher = AnswerMatcher(question);
    final matchResult = matcher.check(sanitizedInput, state.usedAnswerIds);

    switch (matchResult) {
      case MatchResultCorrect(:final answer):
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: sanitizedInput,
          resultType: AttemptResultType.correct,
          answerId: answer.id,
          displayText: answer.display,
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
            currentTurnAttempts: updatedTurnAttempts,
            lastSubmitTimes: updatedLastSubmitTimes,
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

        // Sıra rakibe geçer, süre sıfırlanır, rakip için sıra deneme sayacı 0 olur
        final opponentId = state.opponentOf(playerId);
        final nextDeadlineMs = nowMs + state.config.answerSeconds * 1000;

        final nextState = state.copyWith(
          usedAnswerIds: updatedUsedAnswerIds,
          turnPlayerId: opponentId,
          deadlineMs: nextDeadlineMs,
          currentRoundAttempts: updatedAttempts,
          currentTurnAttempts: 0,
          lastSubmitTimes: updatedLastSubmitTimes,
        );

        return EngineResult(nextState, [
          AnswerAccepted(playerId, answer.display),
        ]);

      case MatchResultRepeated(:final answer):
        // Tekrar cevap turu kaybettirmez: cevap kabul edilmez, sıra ve deadline aynı kalır
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: sanitizedInput,
          resultType: AttemptResultType.repeated,
          answerId: answer.id,
          nowMs: nowMs,
        );

        final nextState = state.copyWith(
          currentRoundAttempts: [...state.currentRoundAttempts, attempt],
          currentTurnAttempts: updatedTurnAttempts,
          lastSubmitTimes: updatedLastSubmitTimes,
        );

        return EngineResult(nextState, [
          AlreadySaid(playerId, answer.display),
        ]);

      case MatchResultWrong():
        final unusedAliases = question.answers
            .where((a) => !state.usedAnswerIds.contains(a.id))
            .map((a) => a.aliases);

        final isClose = NearMissCalculator.isNearMiss(
            normalizedInput: normalized,
            unusedAnswerAliases: unusedAliases,
        );

        final playerQuota = state.remainingNearMisses[playerId] ?? 0;

        if (isClose && playerQuota > 0) {
          // İpucu hakkı var: hak düşer, nearMiss kaydedilir, event NearMiss
          final updatedNearMisses =
              Map<String, int>.from(state.remainingNearMisses);
          updatedNearMisses[playerId] = playerQuota - 1;

          final attempt = TurnAttempt(
            playerId: playerId,
            rawInput: sanitizedInput,
            resultType: AttemptResultType.nearMiss,
            nowMs: nowMs,
            isClose: true,
            hintShown: true,
          );

          final nextState = state.copyWith(
            remainingNearMisses: updatedNearMisses,
            currentRoundAttempts: [...state.currentRoundAttempts, attempt],
            currentTurnAttempts: updatedTurnAttempts,
            lastSubmitTimes: updatedLastSubmitTimes,
          );

          return EngineResult(nextState, [NearMiss(playerId)]);
        }

        // İpucu hakkı bitti ya da yakın değil: wrong kaydedilir, event WrongAnswer
        // Ancak isClose değeri hesaplandığı gibi (yakınsa true) saklanır
        final attempt = TurnAttempt(
          playerId: playerId,
          rawInput: sanitizedInput,
          resultType: AttemptResultType.wrong,
          nowMs: nowMs,
          isClose: isClose,
          hintShown: false,
        );

        final nextState = state.copyWith(
          currentRoundAttempts: [...state.currentRoundAttempts, attempt],
          currentTurnAttempts: updatedTurnAttempts,
          lastSubmitTimes: updatedLastSubmitTimes,
        );

        return EngineResult(nextState, [WrongAnswer(playerId, sanitizedInput)]);

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
      return _endRound(
        state: state,
        winnerId: winnerId,
        reason: RoundEndReason.timeout,
      );
    }

    return EngineResult(state, const []);
  }

  /// Oyuncu maçı terk ettiğinde maçı hemen bitirir.
  static EngineResult forfeit({
    required MatchState state,
    required String playerId,
    required int nowMs,
  }) {
    if (state.phase == MatchPhase.matchFinished) {
      return EngineResult(state, const [Ignored('already_finished')]);
    }

    final opponentId = state.opponentOf(playerId);

    final starterIndex = state.totalRoundsPlayed % 2;
    final starterPlayerId = state.playerIds[starterIndex];

    final currentRoundRecord = RoundRecord(
      questionId: state.currentQuestion?.id ?? '',
      starterPlayerId: starterPlayerId,
      attempts: state.currentRoundAttempts,
      winnerId: opponentId,
      reason: RoundEndReason.forfeit,
    );

    final updatedRoundHistory = [...state.roundHistory, currentRoundRecord];

    final finishedState = state.copyWith(
      phase: MatchPhase.matchFinished,
      roundHistory: updatedRoundHistory,
      winnerId: opponentId,
      endedBy: 'forfeit',
    );

    return EngineResult(finishedState, [MatchFinished(opponentId, 'forfeit')]);
  }

  /// Tur bittikten sonra (roundEnded fazında) bir sonraki turu başlatır.
  static EngineResult startNextRound({
    required MatchState state,
    required List<Question> questions,
    required math.Random random,
    required int nowMs,
    List<String>? questionOrder,
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

    final effectiveOrder = questionOrder ?? state.questionOrder;
    final nextQuestion = _pickNextQuestion(
      questions: eligibleQuestions,
      usedQuestionIds: state.usedQuestionIds,
      roundHistory: state.roundHistory,
      random: random,
      questionOrder: effectiveOrder,
      roundIndex: state.totalRoundsPlayed,
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
      currentTurnAttempts: 0,
      questionOrder: effectiveOrder,
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
    TurnAttempt? attempt,
    bool alreadyAppendedAttempt = false,
    List<MatchEvent> prefixEvents = const [],
  }) {
    final attempts = alreadyAppendedAttempt
        ? state.currentRoundAttempts
        : (attempt != null
            ? [...state.currentRoundAttempts, attempt]
            : state.currentRoundAttempts);

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

    // Bir oyuncu roundsToWin galibiyete ulaştı mı ya da maksimum karar turu / tavan tur doldu mu?
    final p1 = state.playerIds[0];
    final p2 = state.playerIds[1];
    final s1 = updatedScores[p1] ?? 0;
    final s2 = updatedScores[p2] ?? 0;

    final hasWinner = (s1 >= state.config.roundsToWin && s1 > s2) ||
        (s2 >= state.config.roundsToWin && s2 > s1);
    final isDecisiveLimitReached =
        updatedDecisiveRounds >= state.config.maxDecisiveRounds;
    final isTotalLimitReached =
        updatedTotalRoundsPlayed >= state.config.maxTotalRounds;

    if (hasWinner || isDecisiveLimitReached || isTotalLimitReached) {
      final String? matchWinnerId;
      final String endedBy;

      if (hasWinner) {
        matchWinnerId = s1 > s2 ? p1 : p2;
        endedBy = 'normal';
      } else if (isTotalLimitReached && s1 == s2) {
        matchWinnerId = null;
        endedBy = 'draw_limit_reached';
      } else {
        // isDecisiveLimitReached veya (isTotalLimitReached && s1 != s2)
        matchWinnerId = s1 > s2 ? p1 : (s2 > s1 ? p2 : null);
        endedBy = 'normal';
      }

      events.add(MatchFinished(matchWinnerId, endedBy));

      final finishedState = state.copyWith(
        scores: Map.unmodifiable(updatedScores),
        decisiveRounds: updatedDecisiveRounds,
        totalRoundsPlayed: updatedTotalRoundsPlayed,
        phase: MatchPhase.matchFinished,
        roundHistory: updatedRoundHistory,
        currentRoundAttempts: attempts,
        winnerId: matchWinnerId,
        endedBy: endedBy,
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
    List<String>? questionOrder,
    int roundIndex = 0,
  }) {
    if (questionOrder != null && questionOrder.isNotEmpty) {
      final targetId = roundIndex < questionOrder.length
          ? questionOrder[roundIndex]
          : questionOrder[roundIndex % questionOrder.length];
      for (final q in questions) {
        if (q.id == targetId) {
          return q;
        }
      }
    }
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
