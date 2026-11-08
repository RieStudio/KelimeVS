export interface PowerupEnv {
  readonly EXTRA_TIME_COST?: string;
  readonly EXTRA_TIME_SECONDS?: string;
  readonly GIVE_ANSWER_COST?: string;
}

export interface ExtraTimeConfig {
  readonly cost: number;
  readonly seconds: number;
}

export interface GiveAnswerConfig {
  readonly cost: number;
}

export const BOT_MATCH_ID_REGEX = /^bot:[A-Za-z0-9_-]{8,64}$/;

export function isValidBotMatchId(matchId: unknown): matchId is string {
  return typeof matchId === 'string' && BOT_MATCH_ID_REGEX.test(matchId);
}

export type PowerupType = 'extra_time' | 'give_answer';

export function isSupportedPowerup(powerup: unknown): powerup is PowerupType {
  return powerup === 'extra_time' || powerup === 'give_answer';
}

export function getExtraTimeConfig(env: PowerupEnv): ExtraTimeConfig {
  const costVal = parseInt(env.EXTRA_TIME_COST ?? '30', 10);
  const secVal = parseInt(env.EXTRA_TIME_SECONDS ?? '5', 10);
  return {
    cost: Number.isFinite(costVal) && costVal >= 0 ? costVal : 30,
    seconds: Number.isFinite(secVal) && secVal > 0 ? secVal : 5,
  };
}

export function getGiveAnswerConfig(env: PowerupEnv): GiveAnswerConfig {
  const costVal = parseInt(env.GIVE_ANSWER_COST ?? '50', 10);
  return {
    cost: Number.isFinite(costVal) && costVal >= 0 ? costVal : 50,
  };
}
