import { isValidBotMatchId } from './powerup';

export const MIN_SOLO_WIN_SECONDS = 20;
export const SOLO_DAILY_SAFETY_CAP = 1000;
export const SOLO_VOID_DAILY_REFUND_CAP = 5;
export const MAX_SOLO_CORRECT_ANSWERS = 50;
export const ROUNDS_TO_WIN = 2;

export interface SoloMatchResultBody {
  readonly matchId?: string;
  readonly ticketId: string;
  readonly outcome: 'win' | 'loss' | 'void';
  readonly myScore?: number;
  readonly oppScore?: number;
  readonly correctAnswers?: number;
  readonly durationSeconds?: number;
  readonly endedBy?: 'normal' | 'forfeit' | 'draw_limit_reached';
}

export type SoloValidationError =
  | 'bad_request'
  | 'ticket_required'
  | 'ticket_invalid'
  | 'invalid_score'
  | 'invalid_answers';

export function validateSoloMatchResult(body: unknown): {
  readonly isValid: boolean;
  readonly error?: SoloValidationError;
  readonly data?: SoloMatchResultBody;
} {
  if (!body || typeof body !== 'object') {
    return { isValid: false, error: 'bad_request' };
  }

  const b = body as Record<string, unknown>;

  // 1. ticketId zorunludur
  if (typeof b.ticketId !== 'string' || b.ticketId.trim().length === 0) {
    return { isValid: false, error: 'ticket_required' };
  }
  const trimmedTicket = b.ticketId.trim();
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(trimmedTicket)) {
    return { isValid: false, error: 'ticket_invalid' };
  }

  // 2. outcome: 'win' | 'loss' | 'void'
  if (b.outcome !== 'win' && b.outcome !== 'loss' && b.outcome !== 'void') {
    return { isValid: false, error: 'bad_request' };
  }

  // 3. durationSeconds (opsiyonel; istemcinin beyanı süre doğrulamasında kullanılmaz)
  let durationSeconds: number | undefined;
  if (b.durationSeconds !== undefined) {
    if (typeof b.durationSeconds !== 'number' || !Number.isFinite(b.durationSeconds) || b.durationSeconds < 0) {
      return { isValid: false, error: 'bad_request' };
    }
    durationSeconds = b.durationSeconds;
  }

  // 4. 'void' sonucu: ticketId zorunlu, diğer alanlar opsiyonel (verilirse tip/format doğrulanır)
  if (b.outcome === 'void') {
    let matchId: string | undefined;
    if (b.matchId !== undefined) {
      if (!isValidBotMatchId(b.matchId)) {
        return { isValid: false, error: 'bad_request' };
      }
      matchId = b.matchId;
    }

    let endedBy: 'normal' | 'forfeit' | 'draw_limit_reached' | undefined;
    if (b.endedBy !== undefined) {
      if (
        b.endedBy !== 'normal' &&
        b.endedBy !== 'forfeit' &&
        b.endedBy !== 'draw_limit_reached'
      ) {
        return { isValid: false, error: 'bad_request' };
      }
      endedBy = b.endedBy;
    }

    let myScore: number | undefined;
    if (b.myScore !== undefined) {
      if (typeof b.myScore !== 'number' || !Number.isInteger(b.myScore) || b.myScore < 0) {
        return { isValid: false, error: 'bad_request' };
      }
      myScore = b.myScore;
    }

    let oppScore: number | undefined;
    if (b.oppScore !== undefined) {
      if (typeof b.oppScore !== 'number' || !Number.isInteger(b.oppScore) || b.oppScore < 0) {
        return { isValid: false, error: 'bad_request' };
      }
      oppScore = b.oppScore;
    }

    let correctAnswers: number | undefined;
    if (b.correctAnswers !== undefined) {
      if (
        typeof b.correctAnswers !== 'number' ||
        !Number.isInteger(b.correctAnswers) ||
        b.correctAnswers < 0 ||
        b.correctAnswers > MAX_SOLO_CORRECT_ANSWERS
      ) {
        return { isValid: false, error: 'invalid_answers' };
      }
      correctAnswers = b.correctAnswers;
    }

    return {
      isValid: true,
      data: {
        ticketId: trimmedTicket,
        outcome: 'void',
        ...(matchId !== undefined ? { matchId } : {}),
        ...(myScore !== undefined ? { myScore } : {}),
        ...(oppScore !== undefined ? { oppScore } : {}),
        ...(correctAnswers !== undefined ? { correctAnswers } : {}),
        ...(durationSeconds !== undefined ? { durationSeconds } : {}),
        ...(endedBy !== undefined ? { endedBy } : {}),
      },
    };
  }

  // 5. 'win' | 'loss' için matchId formatı (^bot:[A-Za-z0-9_-]{8,64}$) zorunlu
  if (!isValidBotMatchId(b.matchId)) {
    return { isValid: false, error: 'bad_request' };
  }

  // 6. endedBy: 'normal' | 'forfeit'
  if (b.endedBy !== 'normal' && b.endedBy !== 'forfeit') {
    return { isValid: false, error: 'bad_request' };
  }

  // 7. Skor sayısal kontrolleri
  if (typeof b.myScore !== 'number' || !Number.isInteger(b.myScore) || b.myScore < 0) {
    return { isValid: false, error: 'bad_request' };
  }
  if (typeof b.oppScore !== 'number' || !Number.isInteger(b.oppScore) || b.oppScore < 0) {
    return { isValid: false, error: 'bad_request' };
  }

  // 8. correctAnswers sayısal kontrolleri (0 <= x <= MAX_SOLO_CORRECT_ANSWERS)
  if (
    typeof b.correctAnswers !== 'number' ||
    !Number.isInteger(b.correctAnswers) ||
    b.correctAnswers < 0 ||
    b.correctAnswers > MAX_SOLO_CORRECT_ANSWERS
  ) {
    return { isValid: false, error: 'invalid_answers' };
  }

  // 9. Skor tutarlılığı
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

  return {
    isValid: true,
    data: {
      matchId: b.matchId as string,
      ticketId: trimmedTicket,
      outcome: b.outcome as 'win' | 'loss',
      myScore: b.myScore as number,
      oppScore: b.oppScore as number,
      correctAnswers: b.correctAnswers as number,
      ...(durationSeconds !== undefined ? { durationSeconds } : {}),
      endedBy: b.endedBy as 'normal' | 'forfeit',
    },
  };
}
