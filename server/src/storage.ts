import {
  visibleAttempts,
  type MatchConfig,
  type MatchPhase,
  type MatchState,
  type Question,
  type RoundEndReason,
  type RoundRecord,
  type TurnAttempt,
} from './engine';
import type {
  ClientAttempt,
  ClientFinalMessage,
  ClientRoundRecord,
  ClientStateMessage,
} from './protocol';

export interface SerializedMatchState {
  readonly config: MatchConfig;
  readonly playerIds: [string, string];
  readonly scores: Record<string, number>;
  readonly decisiveRounds: number;
  readonly totalRoundsPlayed: number;
  readonly phase: MatchPhase;
  readonly currentQuestion: Question | null;
  readonly usedAnswerIds: string[];
  readonly turnPlayerId: string | null;
  readonly deadlineMs: number;
  readonly remainingNearMisses: Record<string, number>;
  readonly usedQuestionIds: string[];
  readonly roundHistory: RoundRecord[];
  readonly currentRoundAttempts: TurnAttempt[];
  readonly winnerId: string | null;
  readonly lastSubmitTimes: Record<string, number>;
  readonly currentTurnAttempts: number;
  readonly endedBy: string | null;
  readonly questionOrder?: string[];
}

export function serializeMatchState(state: MatchState): SerializedMatchState {
  return {
    config: state.config,
    playerIds: [state.playerIds[0], state.playerIds[1]],
    scores: { ...state.scores },
    decisiveRounds: state.decisiveRounds,
    totalRoundsPlayed: state.totalRoundsPlayed,
    phase: state.phase,
    currentQuestion: state.currentQuestion,
    usedAnswerIds: [...state.usedAnswerIds],
    turnPlayerId: state.turnPlayerId,
    deadlineMs: state.deadlineMs,
    remainingNearMisses: { ...state.remainingNearMisses },
    usedQuestionIds: [...state.usedQuestionIds],
    roundHistory: [...state.roundHistory],
    currentRoundAttempts: [...state.currentRoundAttempts],
    winnerId: state.winnerId,
    lastSubmitTimes: { ...state.lastSubmitTimes },
    currentTurnAttempts: state.currentTurnAttempts,
    endedBy: state.endedBy,
    questionOrder: state.questionOrder ? [...state.questionOrder] : undefined,
  };
}

export function deserializeMatchState(raw: SerializedMatchState): MatchState {
  return {
    config: raw.config,
    playerIds: [raw.playerIds[0], raw.playerIds[1]],
    scores: { ...raw.scores },
    decisiveRounds: raw.decisiveRounds,
    totalRoundsPlayed: raw.totalRoundsPlayed,
    phase: raw.phase,
    currentQuestion: raw.currentQuestion,
    usedAnswerIds: new Set(raw.usedAnswerIds),
    turnPlayerId: raw.turnPlayerId,
    deadlineMs: raw.deadlineMs,
    remainingNearMisses: { ...raw.remainingNearMisses },
    usedQuestionIds: new Set(raw.usedQuestionIds),
    roundHistory: raw.roundHistory,
    currentRoundAttempts: raw.currentRoundAttempts,
    winnerId: raw.winnerId,
    lastSubmitTimes: { ...raw.lastSubmitTimes },
    currentTurnAttempts: raw.currentTurnAttempts,
    endedBy: raw.endedBy,
    questionOrder: raw.questionOrder,
  };
}

export function filterStateForPlayer(params: {
  readonly state: MatchState;
  readonly playerUid: string;
  readonly opponentUid: string;
  readonly opponentName: string;
  readonly opponentConnected: boolean;
  readonly serverNowMs: number;
  readonly nextRoundAtMs?: number;
}): ClientStateMessage {
  const {
    state,
    playerUid,
    opponentUid,
    opponentName,
    opponentConnected,
    serverNowMs,
    nextRoundAtMs,
  } = params;

  // Aktif veya sonlanan turun deneme kayıtlarını visibleAttempts ile filtrele
  const starterIndex = state.totalRoundsPlayed % 2;
  const currentRecord: RoundRecord = {
    questionId: state.currentQuestion?.id ?? '',
    starterPlayerId: state.playerIds[starterIndex],
    attempts: state.currentRoundAttempts,
    winnerId: state.winnerId,
    reason: 'timeout',
  };

  const isRoundActive = state.phase === 'roundActive';
  const filteredAttempts = visibleAttempts(currentRecord, playerUid, isRoundActive);

  const clientAttempts: ClientAttempt[] = filteredAttempts.map((a) => ({
    mine: a.playerId === playerUid,
    text: a.rawInput,
    result: a.resultType,
    ...(a.hintShown ? { hintShown: true } : {}),
  }));

  let lastRound:
    | {
        readonly winnerIsMe: boolean;
        readonly draw: boolean;
        readonly reason: string;
      }
    | undefined;

  if (state.roundHistory.length > 0) {
    const last = state.roundHistory[state.roundHistory.length - 1];
    lastRound = {
      winnerIsMe: last.winnerId === playerUid,
      draw: last.winnerId === null,
      reason: last.reason,
    };
  }

  // Tur sayısı hesabı: roundActive iken sonuçlanan tur + 1, roundEnded iken sonuçlanan tur
  const roundNumber =
    state.phase === 'roundActive'
      ? state.decisiveRounds + 1
      : Math.max(1, state.decisiveRounds);

  return {
    t: 'state',
    serverNowMs,
    phase: state.phase,
    roundNumber,
    scores: {
      me: state.scores[playerUid] ?? 0,
      opponent: state.scores[opponentUid] ?? 0,
    },
    question: state.currentQuestion
      ? {
          id: state.currentQuestion.id,
          text: state.currentQuestion.text,
        }
      : null,
    turnIsMine: state.turnPlayerId === playerUid,
    deadlineMs: state.deadlineMs,
    myHintsLeft: state.remainingNearMisses[playerUid] ?? 0,
    attempts: clientAttempts,
    opponentName,
    opponentConnected,
    ...(state.endedBy ? { endedBy: state.endedBy } : {}),
    ...(state.winnerId ? { winnerIsMe: state.winnerId === playerUid } : {}),
    ...(lastRound ? { lastRound } : {}),
    ...(nextRoundAtMs ? { nextRoundAtMs } : {}),
  };
}

export function buildFinalMessage(params: {
  readonly state: MatchState;
  readonly playerUid: string;
  readonly opponentUid: string;
  readonly opponentName?: string;
  readonly coinsAwarded?: number;
  readonly coins?: number;
}): ClientFinalMessage {
  const { state, playerUid, opponentUid, opponentName, coinsAwarded, coins } = params;

  const rounds: ClientRoundRecord[] = state.roundHistory.map((r) => ({
    questionId: r.questionId,
    attempts: r.attempts.map((a) => ({
      mine: a.playerId === playerUid,
      text: a.rawInput,
      result: a.resultType,
      ...(a.hintShown ? { hintShown: true } : {}),
    })),
    winnerIsMe: r.winnerId === null ? null : r.winnerId === playerUid,
    reason: r.reason,
  }));

  return {
    t: 'final',
    rounds,
    scores: {
      me: state.scores[playerUid] ?? 0,
      opponent: state.scores[opponentUid] ?? 0,
    },
    winnerIsMe: state.winnerId === playerUid,
    endedBy: state.endedBy ?? 'normal',
    ...(opponentName ? { opponentName } : {}),
    ...(coinsAwarded !== undefined ? { coinsAwarded } : {}),
    ...(coins !== undefined ? { coins } : {}),
  };
}

