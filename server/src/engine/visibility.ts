// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

import type { RoundRecord, TurnAttempt } from './types';

/**
 * Saf fonksiyon: Tur aktifken (roundActive === true):
 * - Tekrarlanan deneme (resultType === 'repeated'): HERKESE gizlidir (ne rakip ne sahibi balon olarak görür).
 * - İpucu verilen yakın deneme (hintShown === true): HERKESE gizlidir (ne rakip ne sahibi balon olarak görür).
 * - İpucu verilmemiş yakın deneme (isClose === true, hintShown === false): rakibe gizlidir, sahibine normal kırmızı balon olarak görünür.
 * - Yakın olmayan yanlış denemeler (isClose === false): herkese görünür.
 * Tur bitince (roundActive === false) tüm denemeler herkese görünür.
 */
export function visibleAttempts(
  round: RoundRecord,
  viewerId: string,
  roundActive: boolean
): TurnAttempt[] {
  if (!roundActive) {
    return [...round.attempts];
  }
  return round.attempts.filter((attempt) => {
    if (attempt.resultType === 'repeated') {
      return false; // Tekrarlanan cevap aktif turda chat akışına girmez (herkese gizli)
    }
    if (attempt.hintShown) {
      return false; // İpucu verilen yakın deneme aktif turda HERKESE gizli
    }
    if (attempt.playerId === viewerId) {
      return true; // Sahibi görür (hintShown false olan yakın veya normal denemeler)
    }
    return !attempt.isClose; // Rakibe isClose denemeleri gizli
  });
}

