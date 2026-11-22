export type AchievementCategory = 'matches_played' | 'matches_won' | 'win_streak';

export interface AchievementDef {
  readonly id: string;
  readonly category: AchievementCategory;
  readonly threshold: number;
  readonly order: number;
}

export interface UserAchievementCounters {
  readonly played: number;
  readonly won: number;
  readonly currentStreak: number;
  readonly maxStreak: number;
}

export const ACHIEVEMENT_DEFINITIONS: readonly AchievementDef[] = [
  { id: 'first_match', category: 'matches_played', threshold: 1, order: 1 },
  { id: 'matches_10', category: 'matches_played', threshold: 10, order: 2 },
  { id: 'matches_50', category: 'matches_played', threshold: 50, order: 3 },
  { id: 'matches_100', category: 'matches_played', threshold: 100, order: 4 },
  { id: 'first_win', category: 'matches_won', threshold: 1, order: 5 },
  { id: 'wins_10', category: 'matches_won', threshold: 10, order: 6 },
  { id: 'wins_50', category: 'matches_won', threshold: 50, order: 7 },
  { id: 'wins_100', category: 'matches_won', threshold: 100, order: 8 },
  { id: 'streak_3', category: 'win_streak', threshold: 3, order: 9 },
  { id: 'streak_5', category: 'win_streak', threshold: 5, order: 10 },
  { id: 'streak_10', category: 'win_streak', threshold: 10, order: 11 },
];

/**
 * Saf fonksiyon: Verilen sayaçlara göre henüz açılmamış başarımları sırasıyla döndürür.
 * İleride maça özel koşullar (örn. tek turda N doğru vb.) eklenebilmesi için matchContext parametresi bırakılmıştır.
 */
export function evaluateAchievements(
  counters: UserAchievementCounters,
  unlocked: ReadonlySet<string>,
  _matchContext?: unknown
): string[] {
  const eligible: AchievementDef[] = [];

  for (const def of ACHIEVEMENT_DEFINITIONS) {
    if (unlocked.has(def.id)) {
      continue;
    }

    let isReached = false;
    switch (def.category) {
      case 'matches_played':
        isReached = counters.played >= def.threshold;
        break;
      case 'matches_won':
        isReached = counters.won >= def.threshold;
        break;
      case 'win_streak':
        isReached = Math.max(counters.currentStreak, counters.maxStreak) >= def.threshold;
        break;
    }

    if (isReached) {
      eligible.push(def);
    }
  }

  eligible.sort((a, b) => a.order - b.order);
  return eligible.map((d) => d.id);
}
