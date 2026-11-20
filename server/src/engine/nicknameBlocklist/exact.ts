/**
 * NASIL KELİME EKLENİR? (EXACT LİSTESİ)
 * --------------------------------------
 * Bu dosyaya, YALNIZCA takma ad kelimenin TAMAMI olduğunda engellenecek kökleri
 * ekleyin.
 *
 * Kurallar:
 * 1. Kısa (2-4 harfli) veya masum kelimelerin/isimlerin içinde sıkça geçebilen
 *    küfür, hakaret ve argo köklerini (örn: 'am', 'sik', 'got', 'pic', 'mal', 'bok')
 *    mutlaka BURAYA ekleyin.
 *    - Örnek: 'am' buradadır; bu sayede 'kamil', 'damla', 'amiral', 'tamam' engellenmez.
 *    - Ancak tek başına 'am', 'a_m', 'a.m' veya sonuna rakam eklenmiş 'am99' engellenir.
 * 2. Exact kontrolü hem normalleştirilmiş takma adın tamamı için hem de sondaki
 *    rakamlar atıldıktan sonraki hali için çalışır (örn: 'pic123', 'got99' yakalanır).
 * 3. Değişiklik sonrası yalnızca `server/` dizininde `npm run deploy` çalıştırmanız
 *    yeterlidir (uygulama güncellemesi gerekmez).
 */

export const EXACT_WORDS: readonly string[] = [
  // Kısa veya belirsiz Türkçe kökler
  'am',
  'sik',
  'pic',
  'piç',
  'got',
  'göt',
  'bok',
  'mal',
  'dalyan',
  'it',
  'itler',
  'meme',
  '31',
  'sg',
  'aq',
  'oç',
  'oc',

  // Kısa veya çift anlamlı İngilizce kökler
  'ass',
  'dick',
  'cock',
  'tit',
  'tits',
  'sex',
  'gay',
  'anal',
  'fag',
  'faggot',
  'hoe',
];
