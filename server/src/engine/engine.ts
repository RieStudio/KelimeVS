// Saf JavaScript / TypeScript - Harici bağımlılık veya ortam (Node/Worker) API'si yoktur.

import { AnswerMatcher } from './matcher';
import type { Question } from './models';
import { isNearMiss } from './nearMiss';
import { normalize } from './normalizer';
import { AttemptTextSanitizer } from './sanitizer';
import type {
  EngineResult,
  MatchConfig,
  MatchEvent,
  MatchState,
  RoundEndReason,
  RoundRecord,
  TurnAttempt,
} from './types';

export function opponentOf(state: MatchState, playerId: string): string {
  return state.playerIds[0] === playerId ? state.playerIds[1] : state.playerIds[0];
}

function isTimedOut(state: MatchState, nowMs: number): boolean {
  return nowMs > state.deadlineMs + state.config.graceMs;
}

function filterQuestions(questions: readonly Question[], minAnswers: number): Question[] {
  if (minAnswers <= 0) return [...questions];
  return questions.filter((q) => q.answers.length >= minAnswers);
}

function pickNextQuestion(params: {
  readonly questions: readonly Question[];
  readonly usedQuestionIds: ReadonlySet<string>;
  readonly questionOrder?: readonly string[];
  readonly roundIndex: number;
}): Question {
  const { questions, usedQuestionIds, questionOrder, roundIndex } = params;

  if (questionOrder && questionOrder.length > 0) {
    const targetId =
      roundIndex < questionOrder.length
        ? questionOrder[roundIndex]
        : questionOrder[roundIndex % questionOrder.length];
    const match = questions.find((q) => q.id === targetId);
    if (match) return match;
  }

  const unused = questions.filter((q) => !usedQuestionIds.has(q.id));
  if (unused.length > 0) {
    return unused[0];
  }

  return questions[0];
}

function endRound(params: {
  readonly state: MatchState;
  readonly winnerId: string | null;
  readonly reason: RoundEndReason;
  readonly attempt?: TurnAttempt;
  readonly alreadyAppendedAttempt?: boolean;
  readonly prefixEvents?: readonly MatchEvent[];
}): EngineResult {
  const {
    state,
    winnerId,
    reason,
    attempt,
    alreadyAppendedAttempt = false,
    prefixEvents = [],
  } = params;

  const attempts: readonly TurnAttempt[] = alreadyAppendedAttempt
    ? state.currentRoundAttempts
    : attempt
      ? [...state.currentRoundAttempts, attempt]
      : state.currentRoundAttempts;

  const starterIndex = state.totalRoundsPlayed % 2;
  const starterPlayerId = state.playerIds[starterIndex];

  const roundRecord: RoundRecord = {
    questionId: state.currentQuestion?.id ?? '',
    starterPlayerId,
    attempts,
    winnerId,
    reason,
  };

  const updatedScores: Record<string, number> = { ...state.scores };
  let updatedDecisiveRounds = state.decisiveRounds;

  const events: MatchEvent[] = [...prefixEvents];

  if (winnerId !== null) {
    updatedScores[winnerId] = (updatedScores[winnerId] ?? 0) + 1;
    updatedDecisiveRounds++;
    events.push({ type: 'RoundWon', winnerId, reason });
  } else {
    events.push({ type: 'RoundDrawn', reason });
  }

  const updatedTotalRoundsPlayed = state.totalRoundsPlayed + 1;
  const updatedRoundHistory = [...state.roundHistory, roundRecord];

  const maxDecisiveRounds = 2 * state.config.roundsToWin - 1;
  const hasWinner =
    winnerId !== null && (updatedScores[winnerId] ?? 0) >= state.config.roundsToWin;
  const isDecisiveLimitReached = updatedDecisiveRounds >= maxDecisiveRounds;
  const maxTotalRounds = state.config.maxTotalRounds ?? 5;
  const isTotalLimitReached = updatedTotalRoundsPlayed >= maxTotalRounds;

  if (hasWinner || isDecisiveLimitReached || isTotalLimitReached) {
    const p1 = state.playerIds[0];
    const p2 = state.playerIds[1];
    const s1 = updatedScores[p1] ?? 0;
    const s2 = updatedScores[p2] ?? 0;

    if (isTotalLimitReached && s1 === s2 && !hasWinner) {
      events.push({ type: 'MatchFinished', winnerId: '', reason: 'draw_limit_reached' });

      const finishedState: MatchState = {
        ...state,
        scores: updatedScores,
        decisiveRounds: updatedDecisiveRounds,
        totalRoundsPlayed: updatedTotalRoundsPlayed,
        phase: 'matchFinished',
        roundHistory: updatedRoundHistory,
        currentRoundAttempts: attempts,
        winnerId: null,
        endedBy: 'draw_limit_reached',
      };

      return { state: finishedState, events };
    }

    const matchWinnerId = winnerId ?? (s1 > s2 ? p1 : p2);

    events.push({ type: 'MatchFinished', winnerId: matchWinnerId, reason: 'normal' });

    const finishedState: MatchState = {
      ...state,
      scores: updatedScores,
      decisiveRounds: updatedDecisiveRounds,
      totalRoundsPlayed: updatedTotalRoundsPlayed,
      phase: 'matchFinished',
      roundHistory: updatedRoundHistory,
      currentRoundAttempts: attempts,
      winnerId: matchWinnerId,
      endedBy: 'normal',
    };

    return { state: finishedState, events };
  }

  const endedState: MatchState = {
    ...state,
    scores: updatedScores,
    decisiveRounds: updatedDecisiveRounds,
    totalRoundsPlayed: updatedTotalRoundsPlayed,
    phase: 'roundEnded',
    roundHistory: updatedRoundHistory,
    currentRoundAttempts: attempts,
  };

  return { state: endedState, events };
}

export abstract class MatchEngine {
  /** Yeni bir maç başlatır. */
  static start(params: {
    readonly config: MatchConfig;
    readonly playerIds: readonly [string, string];
    readonly questions: readonly Question[];
    readonly nowMs: number;
    readonly questionOrder?: readonly string[];
  }): EngineResult {
    const { config, playerIds, questions, nowMs, questionOrder } = params;

    if (playerIds.length !== 2) {
      throw new Error('Maç tam olarak 2 oyuncu ile başlatılmalıdır.');
    }
    if (questions.length === 0) {
      throw new Error('Soru havuzu boş olamaz.');
    }

    const eligibleQuestions = filterQuestions(questions, config.minAnswersPerQuestion);
    if (eligibleQuestions.length === 0) {
      throw new Error(
        `Eşik (${config.minAnswersPerQuestion} cevap) sonrası havuzda yeterli soru bulunamadı.`
      );
    }

    const question = pickNextQuestion({
      questions: eligibleQuestions,
      usedQuestionIds: new Set(),
      questionOrder,
      roundIndex: 0,
    });

    const starterPlayerId = playerIds[0]; // Tur 0: ilk oyuncu başlar

    const state: MatchState = {
      config,
      playerIds,
      scores: {
        [playerIds[0]]: 0,
        [playerIds[1]]: 0,
      },
      decisiveRounds: 0,
      totalRoundsPlayed: 0,
      phase: 'roundActive',
      currentQuestion: question,
      usedAnswerIds: new Set(),
      turnPlayerId: starterPlayerId,
      deadlineMs: nowMs + config.answerSeconds * 1000,
      remainingNearMisses: {
        [playerIds[0]]: config.nearMissPerRound,
        [playerIds[1]]: config.nearMissPerRound,
      },
      usedQuestionIds: new Set([question.id]),
      roundHistory: [],
      currentRoundAttempts: [],
      winnerId: null,
      lastSubmitTimes: {},
      currentTurnAttempts: 0,
      endedBy: null,
      questionOrder,
    };

    return { state, events: [] };
  }

  /** Aktif turda oyuncunun cevabını işler. */
  static submit(params: {
    readonly state: MatchState;
    readonly playerId: string;
    readonly rawInput: string;
    readonly nowMs: number;
    readonly questionsPool?: readonly Question[];
  }): EngineResult {
    const { state, playerId, rawInput, nowMs } = params;

    if (state.phase !== 'roundActive') {
      return { state, events: [{ type: 'Ignored', reason: 'round_not_active' }] };
    }

    // 1. Sırası olmayan oyuncunun cevabı yoksayılır
    if (playerId !== state.turnPlayerId) {
      return { state, events: [{ type: 'Ignored', reason: 'not_player_turn' }] };
    }

    // 2. Süre kontrolü
    if (isTimedOut(state, nowMs)) {
      const timedOutPlayerId = state.turnPlayerId!;
      const winnerId = opponentOf(state, timedOutPlayerId);
      return endRound({
        state,
        winnerId,
        reason: 'timeout',
      });
    }

    // 3. Kötüye kullanım: minSubmitIntervalMs (600 ms) kontrolü
    const lastSubmit = state.lastSubmitTimes[playerId];
    if (lastSubmit !== undefined && nowMs - lastSubmit < state.config.minSubmitIntervalMs) {
      return { state, events: [{ type: 'Ignored', reason: 'tooFast' }] };
    }

    // 4. Kötüye kullanım: maxAttemptsPerTurn (25 deneme) kontrolü
    if (state.currentTurnAttempts >= state.config.maxAttemptsPerTurn) {
      return { state, events: [{ type: 'Ignored', reason: 'tooManyAttempts' }] };
    }

    // 5. Metin temizliği (sanitization), normalizasyon ve boşluk kontrolü
    const sanitizedInput = AttemptTextSanitizer.sanitize(rawInput);
    if (sanitizedInput.length === 0) {
      return { state, events: [{ type: 'Ignored', reason: 'empty_input' }] };
    }

    const normalized = normalize(sanitizedInput);
    if (normalized.length === 0) {
      return { state, events: [{ type: 'Ignored', reason: 'empty_input' }] };
    }

    const updatedLastSubmitTimes = {
      ...state.lastSubmitTimes,
      [playerId]: nowMs,
    };
    const updatedTurnAttempts = state.currentTurnAttempts + 1;

    const question = state.currentQuestion!;
    const matcher = new AnswerMatcher(question);
    const matchResult = matcher.check(sanitizedInput, state.usedAnswerIds);

    switch (matchResult.type) {
      case 'correct': {
        const attempt: TurnAttempt = {
          playerId,
          rawInput: sanitizedInput,
          resultType: 'correct',
          answerId: matchResult.answer.id,
          displayText: matchResult.answer.display,
          nowMs,
          isClose: false,
          hintShown: false,
        };

        const updatedUsedAnswerIds = new Set([...state.usedAnswerIds, matchResult.answer.id]);
        const updatedAttempts = [...state.currentRoundAttempts, attempt];

        if (matcher.isExhausted(updatedUsedAnswerIds)) {
          // Tüm cevaplar tükendi -> Tur BERABERE biter
          const intermediateState: MatchState = {
            ...state,
            usedAnswerIds: updatedUsedAnswerIds,
            currentRoundAttempts: updatedAttempts,
            currentTurnAttempts: updatedTurnAttempts,
            lastSubmitTimes: updatedLastSubmitTimes,
          };
          return endRound({
            state: intermediateState,
            winnerId: null,
            reason: 'exhausted',
            attempt,
            alreadyAppendedAttempt: true,
            prefixEvents: [
              {
                type: 'AnswerAccepted',
                playerId,
                answerDisplay: matchResult.answer.display,
              },
            ],
          });
        }

        const opponentId = opponentOf(state, playerId);
        const nextDeadlineMs = nowMs + state.config.answerSeconds * 1000;

        const nextState: MatchState = {
          ...state,
          usedAnswerIds: updatedUsedAnswerIds,
          turnPlayerId: opponentId,
          deadlineMs: nextDeadlineMs,
          currentRoundAttempts: updatedAttempts,
          currentTurnAttempts: 0,
          lastSubmitTimes: updatedLastSubmitTimes,
        };

        return {
          state: nextState,
          events: [
            {
              type: 'AnswerAccepted',
              playerId,
              answerDisplay: matchResult.answer.display,
            },
          ],
        };
      }

      case 'repeated': {
        const attempt: TurnAttempt = {
          playerId,
          rawInput: sanitizedInput,
          resultType: 'repeated',
          answerId: matchResult.answer.id,
          nowMs,
          isClose: false,
          hintShown: false,
        };

        const nextState: MatchState = {
          ...state,
          currentRoundAttempts: [...state.currentRoundAttempts, attempt],
          currentTurnAttempts: updatedTurnAttempts,
          lastSubmitTimes: updatedLastSubmitTimes,
        };

        return {
          state: nextState,
          events: [
            {
              type: 'AlreadySaid',
              playerId,
              answerDisplay: matchResult.answer.display,
            },
          ],
        };
      }

      case 'wrong': {
        const unusedAliases = question.answers
          .filter((a) => !state.usedAnswerIds.has(a.id))
          .map((a) => a.aliases);

        const isClose = isNearMiss(normalized, unusedAliases);
        const playerQuota = state.remainingNearMisses[playerId] ?? 0;

        if (isClose && playerQuota > 0) {
          const updatedNearMisses = {
            ...state.remainingNearMisses,
            [playerId]: playerQuota - 1,
          };

          const attempt: TurnAttempt = {
            playerId,
            rawInput: sanitizedInput,
            resultType: 'nearMiss',
            nowMs,
            isClose: true,
            hintShown: true,
          };

          const nextState: MatchState = {
            ...state,
            remainingNearMisses: updatedNearMisses,
            currentRoundAttempts: [...state.currentRoundAttempts, attempt],
            currentTurnAttempts: updatedTurnAttempts,
            lastSubmitTimes: updatedLastSubmitTimes,
          };

          return {
            state: nextState,
            events: [{ type: 'NearMiss', playerId }],
          };
        }

        const attempt: TurnAttempt = {
          playerId,
          rawInput: sanitizedInput,
          resultType: 'wrong',
          nowMs,
          isClose,
          hintShown: false,
        };

        const nextState: MatchState = {
          ...state,
          currentRoundAttempts: [...state.currentRoundAttempts, attempt],
          currentTurnAttempts: updatedTurnAttempts,
          lastSubmitTimes: updatedLastSubmitTimes,
        };

        return {
          state: nextState,
          events: [{ type: 'WrongAnswer', playerId, rawInput: sanitizedInput }],
        };
      }

      case 'empty': {
        return { state, events: [{ type: 'Ignored', reason: 'empty_input' }] };
      }
    }
  }

  /** Süre aşımını kontrol eder. */
  static checkTimeout(params: {
    readonly state: MatchState;
    readonly nowMs: number;
  }): EngineResult {
    const { state, nowMs } = params;

    if (state.phase !== 'roundActive') {
      return { state, events: [] };
    }

    if (isTimedOut(state, nowMs)) {
      const timedOutPlayerId = state.turnPlayerId!;
      const winnerId = opponentOf(state, timedOutPlayerId);
      return endRound({
        state,
        winnerId,
        reason: 'timeout',
      });
    }

    return { state, events: [] };
  }

  /** Oyuncu maçı terk ettiğinde maçı hemen bitirir. */
  static forfeit(params: {
    readonly state: MatchState;
    readonly playerId: string;
    readonly nowMs: number;
  }): EngineResult {
    const { state, playerId } = params;

    if (state.phase === 'matchFinished') {
      return { state, events: [{ type: 'Ignored', reason: 'already_finished' }] };
    }

    const opponentId = opponentOf(state, playerId);

    const starterIndex = state.totalRoundsPlayed % 2;
    const starterPlayerId = state.playerIds[starterIndex];

    const currentRoundRecord: RoundRecord = {
      questionId: state.currentQuestion?.id ?? '',
      starterPlayerId,
      attempts: state.currentRoundAttempts,
      winnerId: opponentId,
      reason: 'forfeit',
    };

    const updatedRoundHistory = [...state.roundHistory, currentRoundRecord];

    const finishedState: MatchState = {
      ...state,
      phase: 'matchFinished',
      roundHistory: updatedRoundHistory,
      winnerId: opponentId,
      endedBy: 'forfeit',
    };

    return {
      state: finishedState,
      events: [{ type: 'MatchFinished', winnerId: opponentId, reason: 'forfeit' }],
    };
  }

  /** Tur bittikten sonra (roundEnded fazında) bir sonraki turu başlatır. */
  static startNextRound(params: {
    readonly state: MatchState;
    readonly questions: readonly Question[];
    readonly nowMs: number;
    readonly questionOrder?: readonly string[];
  }): EngineResult {
    const { state, questions, nowMs, questionOrder } = params;

    if (state.phase !== 'roundEnded') {
      return { state, events: [{ type: 'Ignored', reason: 'round_not_ended' }] };
    }

    const eligibleQuestions = filterQuestions(questions, state.config.minAnswersPerQuestion);
    if (eligibleQuestions.length === 0) {
      throw new Error(
        `Eşik (${state.config.minAnswersPerQuestion} cevap) sonrası havuzda yeterli soru bulunamadı.`
      );
    }

    const effectiveOrder = questionOrder ?? state.questionOrder;
    const nextQuestion = pickNextQuestion({
      questions: eligibleQuestions,
      usedQuestionIds: state.usedQuestionIds,
      questionOrder: effectiveOrder,
      roundIndex: state.totalRoundsPlayed,
    });

    const starterIndex = state.totalRoundsPlayed % 2;
    const starterPlayerId = state.playerIds[starterIndex];

    const updatedNearMisses = {
      [state.playerIds[0]]: state.config.nearMissPerRound,
      [state.playerIds[1]]: state.config.nearMissPerRound,
    };

    const nextState: MatchState = {
      ...state,
      phase: 'roundActive',
      currentQuestion: nextQuestion,
      usedAnswerIds: new Set(),
      turnPlayerId: starterPlayerId,
      deadlineMs: nowMs + state.config.answerSeconds * 1000,
      remainingNearMisses: updatedNearMisses,
      usedQuestionIds: new Set([...state.usedQuestionIds, nextQuestion.id]),
      currentRoundAttempts: [],
      currentTurnAttempts: 0,
      questionOrder: effectiveOrder,
    };

    return { state: nextState, events: [] };
  }
}

