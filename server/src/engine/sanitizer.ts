// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

/**
 * GDD Bölüm 4.6: Serbest Metin Güvenliği
 *
 * Deneme metni en fazla 40 karakterdir;
 * baştaki ve sondaki boşluklar silinir, ardışık boşluklar tek boşluğa indirilir.
 */
export class AttemptTextSanitizer {
  static readonly maxLength = 40;

  /**
   * Metni temizler:
   * - Baştaki ve sondaki boşlukları siler (trim).
   * - Birden fazla ardışık boşluğu tek boşluğa indirir.
   * - En fazla 40 karaktere kırpar.
   */
  static sanitize(input: string): string {
    const trimmed = input.trim();
    if (trimmed.length === 0) return '';

    const collapsed = trimmed.replace(/\s+/g, ' ');
    if (collapsed.length > AttemptTextSanitizer.maxLength) {
      return collapsed.substring(0, AttemptTextSanitizer.maxLength);
    }
    return collapsed;
  }
}

