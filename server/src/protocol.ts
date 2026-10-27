// JSON Protokol Tanımları ve Ayrıştırıcıları
import { validateNickname } from './engine/nicknameValidator';
import { AttemptTextSanitizer } from './engine/sanitizer';

export const FRIEND_CODE_ALPHABET = '23456789BCDFGHJKMNPQRSTVWXYZ';

export function generateFriendCode(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += FRIEND_CODE_ALPHABET[bytes[i] % FRIEND_CODE_ALPHABET.length];
  }
  return code;
}

export function sanitizeFriendCode(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const clean = raw.trim().toUpperCase();
  if (clean.length !== 6) return null;
  for (let i = 0; i < 6; i++) {
    if (!FRIEND_CODE_ALPHABET.includes(clean[i])) {
      return null;
    }
  }
  return clean;
}

export type MatchmakerClientMessage =
  | { readonly t: 'queue'; readonly name: string }
  | { readonly t: 'cancel' }
  | { readonly t: 'create_room'; readonly name?: string }
  | { readonly t: 'resume_room'; readonly code: string }
  | { readonly t: 'join_room'; readonly code: string; readonly name?: string }
  | { readonly t: 'cancel_room'; readonly code?: string };

export type MatchmakerServerMessage =
  | { readonly t: 'queued' }
  | { readonly t: 'cancelled' }
  | { readonly t: 'room_created'; readonly code: string; readonly expiresAt: number }
  | { readonly t: 'room_resumed'; readonly code: string; readonly expiresAt: number }
  | { readonly t: 'room_expired' }
  | {
      readonly t: 'matched';
      readonly matchId: string;
      readonly opponentName: string;
      readonly opponentFrame?: string;
      readonly isFriendly?: boolean;
      readonly serverNowMs?: number;
      readonly energy?: {
        readonly current: number;
        readonly max: number;
        readonly nextEnergyAtMs: number | null;
      };
    }
  | {
      readonly t: 'error';
      readonly code: string;
      readonly message?: string;
      readonly retryAfterSeconds?: number;
    };

export type MatchRoomClientMessage =
  | { readonly t: 'submit'; readonly text: string }
  | { readonly t: 'leave' }
  | { readonly t: 'sync' }
  | { readonly t: 'use_powerup'; readonly type: 'extra_time' };

export interface ClientAttempt {
  readonly mine: boolean;
  readonly text: string;
  readonly result: 'correct' | 'repeated' | 'wrong' | 'nearMiss' | 'timeout';
  readonly hintShown?: boolean;
}

export interface ClientStateMessage {
  readonly t: 'state';
  readonly serverNowMs: number;
  readonly phase: 'roundActive' | 'roundEnded' | 'matchFinished';
  readonly roundNumber: number;
  readonly scores: { readonly me: number; readonly opponent: number };
  readonly question: { readonly id: string; readonly text: string } | null;
  readonly turnIsMine: boolean;
  readonly deadlineMs: number;
  readonly myHintsLeft: number;
  readonly attempts: readonly ClientAttempt[];
  readonly opponentName: string;
  readonly opponentFrame?: string;
  readonly opponentConnected: boolean;
  readonly endedBy?: string;
  readonly winnerIsMe?: boolean;
  readonly lastRound?: {
    readonly winnerIsMe: boolean;
    readonly draw: boolean;
    readonly reason: string;
  };
  readonly nextRoundAtMs?: number;
  readonly answerSeconds?: number;
  readonly powerups?: {
    readonly extraTime?: {
      readonly cost: number;
      readonly seconds: number;
      readonly remainingUses: number;
    };
  };
}

export interface ClientRoundRecord {
  readonly questionId: string;
  readonly attempts: readonly ClientAttempt[];
  readonly winnerIsMe: boolean | null;
  readonly reason: string;
}

export interface ClientFinalMessage {
  readonly t: 'final';
  readonly rounds: readonly ClientRoundRecord[];
  readonly scores: { readonly me: number; readonly opponent: number };
  readonly winnerIsMe: boolean;
  readonly endedBy: string;
  readonly opponentName?: string;
  readonly opponentFrame?: string;
  readonly coinsAwarded?: number;
  readonly coins?: number;
}

export interface ClientFeedbackMessage {
  readonly t: 'feedback';
  readonly kind: 'wrong' | 'alreadySaid' | 'nearMiss' | 'ignored';
  readonly reason?: string;
}

export interface ClientVoidedMessage {
  readonly t: 'voided';
  readonly reason: 'opponent_absent' | 'both_disconnected' | 'draw_limit_reached';
}

export interface ClientPowerupAckMessage {
  readonly t: 'powerup_ack';
  readonly powerupType: 'extra_time';
  readonly success: boolean;
  readonly deadlineMs?: number;
  readonly coins?: number;
  readonly remainingUses?: number;
  readonly code?: string;
  readonly message?: string;
}

export interface ClientOpponentPowerupMessage {
  readonly t: 'opponent_powerup';
  readonly powerupType: 'extra_time';
  readonly seconds: number;
}

export type MatchRoomServerMessage =
  | ClientStateMessage
  | ClientFinalMessage
  | ClientFeedbackMessage
  | ClientVoidedMessage
  | ClientPowerupAckMessage
  | ClientOpponentPowerupMessage;

export function sanitizePlayerName(rawName?: unknown): string {
  if (typeof rawName !== 'string') return 'Oyuncu';
  const result = validateNickname(rawName);
  if (!result.isValid || result.normalized === null) {
    return 'Oyuncu';
  }
  return result.normalized;
}

export function parseMatchmakerMessage(raw: unknown): MatchmakerClientMessage | null {
  if (typeof raw !== 'string') return null;
  if (raw.length > 500) return null;

  try {
    const data = JSON.parse(raw);
    if (typeof data !== 'object' || data === null) return null;

    if (data.t === 'queue') {
      return {
        t: 'queue',
        name: sanitizePlayerName(data.name),
      };
    }
    if (data.t === 'cancel') {
      return { t: 'cancel' };
    }
    if (data.t === 'create_room') {
      return {
        t: 'create_room',
        name: typeof data.name === 'string' ? sanitizePlayerName(data.name) : undefined,
      };
    }
    if (data.t === 'resume_room') {
      const code = sanitizeFriendCode(data.code);
      if (!code) return null;
      return {
        t: 'resume_room',
        code,
      };
    }
    if (data.t === 'join_room') {
      const code = sanitizeFriendCode(data.code);
      if (!code) return null;
      return {
        t: 'join_room',
        code,
        name: typeof data.name === 'string' ? sanitizePlayerName(data.name) : undefined,
      };
    }
    if (data.t === 'cancel_room') {
      const code = typeof data.code === 'string' ? sanitizeFriendCode(data.code) : undefined;
      return {
        t: 'cancel_room',
        ...(code ? { code } : {}),
      };
    }
  } catch {
    return null;
  }

  return null;
}

export function parseMatchRoomMessage(
  raw: unknown,
  byteLength?: number
): MatchRoomClientMessage | null {
  if (typeof raw !== 'string') return null;
  const len = byteLength ?? new TextEncoder().encode(raw).length;
  if (len > 200) return null; // En fazla 200 baytlık mesaj

  try {
    const data = JSON.parse(raw);
    if (typeof data !== 'object' || data === null) return null;

    if (data.t === 'submit') {
      if (typeof data.text !== 'string') return null;
      const text = AttemptTextSanitizer.sanitize(data.text);
      return { t: 'submit', text };
    }
    if (data.t === 'leave') {
      return { t: 'leave' };
    }
    if (data.t === 'sync') {
      return { t: 'sync' };
    }
    if (data.t === 'use_powerup') {
      if (data.type === 'extra_time') {
        return { t: 'use_powerup', type: 'extra_time' };
      }
      return null;
    }
  } catch {
    return null;
  }

  return null;
}

