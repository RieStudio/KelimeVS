export interface EnergyPack {
  readonly id: 'one' | 'full';
  readonly cost: number;
  readonly energy: number;
}

export interface EnergyState {
  readonly enabled: boolean;
  readonly current: number;
  readonly max: number;
  readonly nextEnergyAtMs: number | null;
  readonly regenSeconds: number;
  readonly packs: readonly EnergyPack[];
}

export interface EnergyEnv {
  readonly ENERGY_ENABLED?: string;
  readonly ENERGY_TEST_UIDS?: string;
  readonly ENERGY_MAX?: string;
  readonly ENERGY_REGEN_MINUTES?: string;
  readonly ENERGY_COST_PER_MATCH?: string;
  readonly ENERGY_PACK_ONE_COST?: string;
  readonly ENERGY_PACK_FULL_COST?: string;
}

export function isEnergyEnabledForUser(env: EnergyEnv, uid?: string): boolean {
  if (env.ENERGY_ENABLED === 'true') return true;
  if (!uid || typeof env.ENERGY_TEST_UIDS !== 'string' || env.ENERGY_TEST_UIDS.trim().length === 0) {
    return false;
  }
  const testUids = env.ENERGY_TEST_UIDS.split(',')
    .map((u) => u.trim())
    .filter((u) => u.length > 0);
  return testUids.includes(uid);
}

export function getEnergyMax(env: EnergyEnv): number {
  const parsed = parseInt(env.ENERGY_MAX ?? '5', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 5;
}

export function getEnergyRegenMinutes(env: EnergyEnv): number {
  const parsed = parseInt(env.ENERGY_REGEN_MINUTES ?? '20', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 20;
}

export function getEnergyCostPerMatch(env: EnergyEnv): number {
  const parsed = parseInt(env.ENERGY_COST_PER_MATCH ?? '1', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

export function getEnergyPackOneCost(env: EnergyEnv): number {
  const parsed = parseInt(env.ENERGY_PACK_ONE_COST ?? '20', 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 20;
}

export function getEnergyPackFullCost(env: EnergyEnv): number {
  const parsed = parseInt(env.ENERGY_PACK_FULL_COST ?? '80', 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 80;
}

export function buildEnergyPacks(env: EnergyEnv): readonly EnergyPack[] {
  return [
    { id: 'one', cost: getEnergyPackOneCost(env), energy: 1 },
    { id: 'full', cost: getEnergyPackFullCost(env), energy: getEnergyMax(env) },
  ];
}

export interface RegenCalculationResult {
  readonly current: number;
  readonly updatedAtMs: number;
  readonly nextEnergyAtMs: number | null;
  readonly gained: number;
}

/**
 * Tembel (Lazy) enerji yenilenme hesabı.
 * - Kaydedilmiş enerji ve son güncelleme zamanına göre geçen sürede kaç enerji kazanıldığını hesaplar.
 * - Enerji tam ise (veya tam dolduysa) nextEnergyAtMs null döner ve updatedAtMs güncellenir.
 * - Kısmi enerjide nextEnergyAtMs bir sonraki enerjinin dolacağı anı verir.
 */
export function calculateRegeneratedEnergy(
  savedEnergy: number,
  savedUpdatedAtMs: number,
  nowMs: number,
  maxEnergy: number,
  regenMinutes: number
): RegenCalculationResult {
  if (savedUpdatedAtMs <= 0 || savedEnergy >= maxEnergy) {
    return {
      current: maxEnergy,
      updatedAtMs: nowMs,
      nextEnergyAtMs: null,
      gained: 0,
    };
  }

  const regenIntervalMs = regenMinutes * 60 * 1000;
  const elapsedMs = Math.max(0, nowMs - savedUpdatedAtMs);
  const gained = Math.floor(elapsedMs / regenIntervalMs);

  if (gained > 0) {
    const newEnergy = Math.min(maxEnergy, savedEnergy + gained);
    if (newEnergy >= maxEnergy) {
      return {
        current: maxEnergy,
        updatedAtMs: nowMs,
        nextEnergyAtMs: null,
        gained,
      };
    }
    const newUpdatedAtMs = savedUpdatedAtMs + gained * regenIntervalMs;
    return {
      current: newEnergy,
      updatedAtMs: newUpdatedAtMs,
      nextEnergyAtMs: newUpdatedAtMs + regenIntervalMs,
      gained,
    };
  }

  return {
    current: savedEnergy,
    updatedAtMs: savedUpdatedAtMs,
    nextEnergyAtMs: savedUpdatedAtMs + regenIntervalMs,
    gained: 0,
  };
}

