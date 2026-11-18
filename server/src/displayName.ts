import { isGuestPatternNickname } from './engine/nicknameValidator';

/**
 * Misafir kullanıcılar için deterministik "M-####" formatında takma ad üretir.
 * 1000 ile 9999 arasında 4 haneli bir sayı üretir; "M-0000" gibi uç durumlar oluşmaz.
 */
export function generateGuestNickname(uid: string): string {
  let hash = 0;
  for (let i = 0; i < uid.length; i++) {
    hash = (hash * 31 + uid.charCodeAt(i)) >>> 0;
  }
  const num = 1000 + (hash % 9000);
  return `M-${num}`;
}

export interface ResolveDisplayNameParams {
  readonly nickname?: string | null;
  readonly uid?: string | null;
  readonly isGuest?: boolean;
}

/**
 * Görünen adı TEK bir kaynaktan tutarlı şekilde çözümler:
 * - isGuest === true ise: ad her zaman M-#### olmalıdır. Mevcut ad M-#### ise korunur, değilse veya yoksa uid'den türetilir.
 * - Geçerli bir özel takma ad varsa (ve isGuest false/belirtilmemişse): o ad döner.
 * - Ad yoksa veya boşsa:
 *   - uid biliniyorsa: uid'den deterministik M-#### üretilir.
 *   - uid bilinmiyorsa: 'Oyuncu' yedek metni döner.
 */
export function resolveDisplayName(params: ResolveDisplayNameParams): string {
  const trimmed = params.nickname?.trim();
  const cleanUid = params.uid?.trim();

  if (params.isGuest === true) {
    if (trimmed && isGuestPatternNickname(trimmed)) {
      return trimmed;
    }
    if (cleanUid) {
      return generateGuestNickname(cleanUid);
    }
    return trimmed && trimmed.length > 0 && trimmed !== 'Oyuncu' ? trimmed : 'Oyuncu';
  }

  if (params.isGuest === false) {
    if (trimmed && trimmed.length > 0) {
      return trimmed;
    }
    return 'Oyuncu';
  }

  // isGuest belirtilmemiş (undefined) ise:
  if (trimmed && trimmed.length > 0) {
    if (trimmed === 'Oyuncu' && cleanUid) {
      // 'Oyuncu' önceden hatalı sanitize edilmiş veya yedeklenmiş olabilir; uid varsa misafir formatına çevir
      return generateGuestNickname(cleanUid);
    }
    return trimmed;
  }

  if (cleanUid) {
    return generateGuestNickname(cleanUid);
  }

  return 'Oyuncu';
}
