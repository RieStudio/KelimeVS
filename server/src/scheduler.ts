// Tek Alarm Zamanlayıcı ve Yönetim Mantığı

export interface TimersSchedule {
  readonly connectTimeoutAtMs?: number;
  readonly turnDeadlineMs?: number;
  readonly nextRoundAtMs?: number;
  readonly disconnectTimeoutAtMs?: number;
  readonly cleanupAtMs?: number;
  readonly rewardRetryAtMs?: number;
  readonly leaderboardRetryAtMs?: number;
  readonly refundRetryAtMs?: number;
}

export type DueActionType =
  | 'connectTimeout'
  | 'disconnectForfeit'
  | 'turnTimeout'
  | 'startNextRound'
  | 'cleanup'
  | 'rewardRetry'
  | 'leaderboardRetry'
  | 'refundRetry';

export interface RoomDurations {
  readonly answerSeconds: number;
  readonly roundTransitionMs: number;
  readonly disconnectTimeoutMs: number;
  readonly connectTimeoutMs: number;
  readonly cleanupMs: number;
}

export function getRoomDurations(isFastTimers: boolean): RoomDurations {
  if (isFastTimers) {
    return {
      answerSeconds: 3,
      roundTransitionMs: 500,
      disconnectTimeoutMs: 3000,
      connectTimeoutMs: 3000,
      cleanupMs: 600000,
    };
  }
  return {
    answerSeconds: 15,
    roundTransitionMs: 3000,
    disconnectTimeoutMs: 30000,
    connectTimeoutMs: 10000,
    cleanupMs: 600000,
  };
}

/**
 * Bekleyen zamanlayıcılar arasından bir sonraki en yakın alarm vadesini hesaplar.
 */
export function computeNextAlarm(schedule: TimersSchedule): number | null {
  const times: number[] = [];
  if (schedule.connectTimeoutAtMs !== undefined) times.push(schedule.connectTimeoutAtMs);
  if (schedule.turnDeadlineMs !== undefined) times.push(schedule.turnDeadlineMs);
  if (schedule.nextRoundAtMs !== undefined) times.push(schedule.nextRoundAtMs);
  if (schedule.disconnectTimeoutAtMs !== undefined) times.push(schedule.disconnectTimeoutAtMs);
  if (schedule.cleanupAtMs !== undefined) times.push(schedule.cleanupAtMs);
  if (schedule.rewardRetryAtMs !== undefined) times.push(schedule.rewardRetryAtMs);
  if (schedule.leaderboardRetryAtMs !== undefined) times.push(schedule.leaderboardRetryAtMs);
  if (schedule.refundRetryAtMs !== undefined) times.push(schedule.refundRetryAtMs);

  if (times.length === 0) return null;
  return Math.min(...times);
}

/**
 * Mevcut zamana göre vadesi dolmuş olan aksiyonları ve güncellenmiş takvimi döndürür.
 */
export function processDueTimers(
  schedule: TimersSchedule,
  nowMs: number
): {
  readonly dueActions: readonly DueActionType[];
  readonly remainingSchedule: TimersSchedule;
} {
  const dueActions: DueActionType[] = [];
  let remaining: TimersSchedule = { ...schedule };

  if (schedule.connectTimeoutAtMs !== undefined && nowMs >= schedule.connectTimeoutAtMs) {
    dueActions.push('connectTimeout');
    const { connectTimeoutAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.disconnectTimeoutAtMs !== undefined && nowMs >= schedule.disconnectTimeoutAtMs) {
    dueActions.push('disconnectForfeit');
    const { disconnectTimeoutAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.turnDeadlineMs !== undefined && nowMs >= schedule.turnDeadlineMs) {
    dueActions.push('turnTimeout');
    const { turnDeadlineMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.nextRoundAtMs !== undefined && nowMs >= schedule.nextRoundAtMs) {
    dueActions.push('startNextRound');
    const { nextRoundAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.rewardRetryAtMs !== undefined && nowMs >= schedule.rewardRetryAtMs) {
    dueActions.push('rewardRetry');
    const { rewardRetryAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.leaderboardRetryAtMs !== undefined && nowMs >= schedule.leaderboardRetryAtMs) {
    dueActions.push('leaderboardRetry');
    const { leaderboardRetryAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.refundRetryAtMs !== undefined && nowMs >= schedule.refundRetryAtMs) {
    dueActions.push('refundRetry');
    const { refundRetryAtMs, ...rest } = remaining;
    remaining = rest;
  }

  if (schedule.cleanupAtMs !== undefined && nowMs >= schedule.cleanupAtMs) {
    dueActions.push('cleanup');
    const { cleanupAtMs, ...rest } = remaining;
    remaining = rest;
  }

  return { dueActions, remainingSchedule: remaining };
}

