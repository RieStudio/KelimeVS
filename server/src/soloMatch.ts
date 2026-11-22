import { isValidBotMatchId } from './powerup';

export const MIN_SOLO_WIN_SECONDS = 20;
export const SOLO_DAILY_SAFETY_CAP = 200;
export const MAX_SOLO_CORRECT_ANSWERS = 50;
export const ROUNDS_TO_WIN = 2;

export interface SoloMatchResultBody {
  readonly matchId: string;
  readonly outcome: 'win' | 'loss';
  readonly myScore: number;
  readonly oppScore: number;
  readonly correctAnswers: number;
  readonly durationSeconds: number;
  readonly endedBy: 'normal' | 'forfeit';
}

export type SoloValidationError = 'bad_request' | 'invalid_score' | 'invalid_duration' | 'invalid_answers';

export function validateSoloMatchResult(body: unknown): {
  readonly isValid: boolean;
  readonly error?: SoloValidationError;
  readonly data?: SoloMatchResultBody;
} {
  if (!body || typeof body !== 'object') {
    return { isValid: false, error: 'bad_request' };
  }

  const b = body as Record<string, unknown>;

  // 1. matchId formatı (^bot:[A-Za-z0-9_-]{8,64}$)
  if (!isValidBotMatchId(b.matchId)) {
    return { isValid: false, error: 'bad_request' };
  }

  // 2. outcome: 'win' | 'loss'
  if (b.outcome !== 'win' && b.outcome !== 'loss') {
    return { isValid: false, error: 'bad_request' };
  }

  // 3. endedBy: 'normal' | 'forfeit'
  if (b.endedBy !== 'normal' && b.endedBy !== 'forfeit') {
    return { isValid: false, error: 'bad_request' };
  }

  // 4. Skor sayısal kontrolleri
  if (typeof b.myScore !== 'number' || !Number.isInteger(b.myScore) || b.myScore < 0) {
    return { isValid: false, error: 'bad_request' };
  }
  if (typeof b.oppScore !== 'number' || !Number.isInteger(b.oppScore) || b.oppScore < 0) {
    return { isValid: false, error: 'bad_request' };
  }

  // 5. correctAnswers sayısal kontrolleri (0 <= x <= MAX_SOLO_CORRECT_ANSWERS)
  if (
    typeof b.correctAnswers !== 'number' ||
    !Number.isInteger(b.correctAnswers) ||
    b.correctAnswers < 0 ||
    b.correctAnswers > MAX_SOLO_CORRECT_ANSWERS
  ) {
    return { isValid: false, error: 'invalid_answers' };
  }

  // 6. durationSeconds kontrolleri
  if (typeof b.durationSeconds !== 'number' || !Number.isFinite(b.durationSeconds) || b.durationSeconds < 0) {
    return { isValid: false, error: 'bad_request' };
  }

  // 7. Kural 2a: Skor tutarlılığı
  // roundsToWin sabiti: 2
  if (b.endedBy === 'forfeit') {
    // Forfeit durumunda outcome yalnızca 'loss' olabilir ve her iki skor da roundsToWin'in altındadır.
    if (b.outcome !== 'loss' || b.myScore >= ROUNDS_TO_WIN || b.oppScore >= ROUNDS_TO_WIN) {
      return { isValid: false, error: 'invalid_score' };
    }
  } else if (b.outcome === 'win') {
    // Galibiyette kazanan roundsToWin skoruna ulaşmış, kaybeden ise roundsToWin'in altında olmalıdır.
    if (b.myScore !== ROUNDS_TO_WIN || b.oppScore >= ROUNDS_TO_WIN) {
      return { isValid: false, error: 'invalid_score' };
    }
  } else {
    // outcome === 'loss' ve endedBy === 'normal'
    // Normal mağlubiyette rakip roundsToWin'e ulaşmış, kullanıcı altında olmalıdır.
    if (b.oppScore !== ROUNDS_TO_WIN || b.myScore >= ROUNDS_TO_WIN) {
      return { isValid: false, error: 'invalid_score' };
    }
  }

  // 8. Kural 2b: Minimum süre (YALNIZCA galibiyette)
  if (b.outcome === 'win' && b.durationSeconds < MIN_SOLO_WIN_SECONDS) {
    return { isValid: false, error: 'invalid_duration' };
  }

  return {
    isValid: true,
    data: {
      matchId: b.matchId as string,
      outcome: b.outcome as 'win' | 'loss',
      myScore: b.myScore as number,
      oppScore: b.oppScore as number,
      correctAnswers: b.correctAnswers as number,
      durationSeconds: b.durationSeconds as number,
      endedBy: b.endedBy as 'normal' | 'forfeit',
    },
  };
}
