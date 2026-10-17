// JSON Protokol Tanımları ve Ayrıştırıcıları
import { validateNickname } from './engine/nicknameValidator';

export type MatchmakerClientMessage =
  | { readonly t: 'queue'; readonly name: string }
  | { readonly t: 'cancel' };

export type MatchmakerServerMessage =
  | { readonly t: 'queued' }
  | { readonly t: 'cancelled' }
  | { readonly t: 'matched'; readonly matchId: string; readonly opponentName: string }
  | { readonly t: 'error'; readonly code: string };

export type MatchRoomClientMessage =
  | { readonly t: 'submit'; readonly text: string }
  | { readonly t: 'leave' }
  | { readonly t: 'sync' };

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
  readonly opponentConnected: boolean;
  readonly endedBy?: string;
  readonly winnerIsMe?: boolean;
  readonly lastRound?: {
    readonly winnerIsMe: boolean;
    readonly draw: boolean;
    readonly reason: string;
  };
  readonly nextRoundAtMs?: number;
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
}

export interface ClientFeedbackMessage {
  readonly t: 'feedback';
  readonly kind: 'wrong' | 'alreadySaid' | 'nearMiss' | 'ignored';
  readonly reason?: string;
}

export interface ClientVoidedMessage {
  readonly t: 'voided';
  readonly reason: 'opponent_absent';
}

export type MatchRoomServerMessage =
  | ClientStateMessage
  | ClientFinalMessage
  | ClientFeedbackMessage
  | ClientVoidedMessage;

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
      const text = data.text.trim().replace(/\s+/g, ' ').slice(0, 40);
      return { t: 'submit', text };
    }
    if (data.t === 'leave') {
      return { t: 'leave' };
    }
    if (data.t === 'sync') {
      return { t: 'sync' };
    }
  } catch {
    return null;
  }

  return null;
}

