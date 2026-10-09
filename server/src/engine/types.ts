import type { Question } from './models';

export type MatchPhase = 'roundActive' | 'roundEnded' | 'matchFinished';

export type AttemptResultType =
  | 'correct'
  | 'repeated'
  | 'wrong'
  | 'nearMiss'
  | 'timeout';

export type RoundEndReason = 'timeout' | 'exhausted' | 'forfeit';

export interface TurnAttempt {
  readonly playerId: string;
  readonly rawInput: string;
  readonly resultType: AttemptResultType;
  readonly answerId?: string;
  readonly nowMs: number;
  readonly isClose: boolean;
  readonly hintShown: boolean;
}

export interface RoundRecord {
  readonly questionId: string;
  readonly starterPlayerId: string;
  readonly attempts: readonly TurnAttempt[];
  readonly winnerId: string | null;
  readonly reason: RoundEndReason;
}

export interface MatchConfig {
  readonly roundsToWin: number;
  readonly answerSeconds: number;
  readonly graceMs: number;
  readonly nearMissPerRound: number;
  readonly minAnswersPerQuestion: number;
  readonly minSubmitIntervalMs: number;
  readonly maxAttemptsPerTurn: number;
}

export type MatchEvent =
  | { readonly type: 'AnswerAccepted'; readonly playerId: string; readonly answerDisplay: string }
  | { readonly type: 'NearMiss'; readonly playerId: string }
  | { readonly type: 'WrongAnswer'; readonly playerId: string; readonly rawInput: string }
  | { readonly type: 'AlreadySaid'; readonly playerId: string; readonly answerDisplay: string }
  | { readonly type: 'RoundWon'; readonly winnerId: string; readonly reason: RoundEndReason }
  | { readonly type: 'RoundDrawn'; readonly reason: RoundEndReason }
  | { readonly type: 'MatchFinished'; readonly winnerId: string; readonly reason: string }
  | { readonly type: 'Ignored'; readonly reason: string };

export interface MatchState {
  readonly config: MatchConfig;
  readonly playerIds: readonly [string, string];
  readonly scores: Readonly<Record<string, number>>;
  readonly decisiveRounds: number;
  readonly totalRoundsPlayed: number;
  readonly phase: MatchPhase;
  readonly currentQuestion: Question | null;
  readonly usedAnswerIds: ReadonlySet<string>;
  readonly turnPlayerId: string | null;
  readonly deadlineMs: number;
  readonly remainingNearMisses: Readonly<Record<string, number>>;
  readonly usedQuestionIds: ReadonlySet<string>;
  readonly roundHistory: readonly RoundRecord[];
  readonly currentRoundAttempts: readonly TurnAttempt[];
  readonly winnerId: string | null;
  readonly lastSubmitTimes: Readonly<Record<string, number>>;
  readonly currentTurnAttempts: number;
  readonly endedBy: string | null;
  readonly questionOrder?: readonly string[];
}

export interface EngineResult {
  readonly state: MatchState;
  readonly events: readonly MatchEvent[];
}

