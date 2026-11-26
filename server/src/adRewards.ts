export type AdRewardType = 'energy' | 'coins';

export interface AdRewardsEnv {
  readonly AD_REWARDS_ENABLED?: string;
  readonly AD_REWARD_ENERGY_AMOUNT?: string;
  readonly AD_REWARD_ENERGY_DAILY_CAP?: string;
  readonly AD_REWARD_COINS_AMOUNT?: string;
  readonly AD_REWARD_COINS_DAILY_CAP?: string;
  readonly AD_REWARD_MIN_INTERVAL_SECONDS?: string;
}

export interface AdRewardsStatus {
  readonly enabled: boolean;
  readonly energy: { readonly remaining: number; readonly cap: number };
  readonly coins: { readonly remaining: number; readonly cap: number };
  readonly nextClaimAtMs: number | null;
  readonly energyAmount: number;
  readonly coinsAmount: number;
}

export function isAdRewardsEnabled(env: AdRewardsEnv): boolean {
  const raw = env.AD_REWARDS_ENABLED;
  if (raw === undefined) return true;
  return raw.trim().toLowerCase() === 'true';
}

export function getAdRewardEnergyAmount(env: AdRewardsEnv): number {
  const parsed = parseInt(env.AD_REWARD_ENERGY_AMOUNT ?? '1', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

export function getAdRewardEnergyDailyCap(env: AdRewardsEnv): number {
  const parsed = parseInt(env.AD_REWARD_ENERGY_DAILY_CAP ?? '3', 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 3;
}

export function getAdRewardCoinsAmount(env: AdRewardsEnv): number {
  const parsed = parseInt(env.AD_REWARD_COINS_AMOUNT ?? '15', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 15;
}

export function getAdRewardCoinsDailyCap(env: AdRewardsEnv): number {
  const parsed = parseInt(env.AD_REWARD_COINS_DAILY_CAP ?? '3', 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 3;
}

export function getAdRewardMinIntervalSeconds(env: AdRewardsEnv): number {
  const parsed = parseInt(env.AD_REWARD_MIN_INTERVAL_SECONDS ?? '60', 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 60;
}

export function isValidAdClaimId(claimId: unknown): claimId is string {
  return typeof claimId === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(claimId);
}

/**
 * Günlük reklam ödülü ve günlük jeton limitleri için ortak UTC gün anahtarı (`YYYY-MM-DD`).
 */
export function getAdRewardDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}
