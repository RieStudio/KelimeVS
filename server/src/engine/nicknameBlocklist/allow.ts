/**
 * NASIL KELİME EKLENİR? (ALLOW / İZİN VERİLENLER LİSTESİ)
 * --------------------------------------------------------
 * Bu dosyaya, masum ve geçerli olmasına rağmen `contains.ts` kökleriyle
 * yanlış pozitif (false positive) çakışması yaşama ihtimali olan kelimeleri,
 * isimleri ve oyun terimlerini ekleyin.
 *
 * Nasıl Çalışır?
 * 1. Filtreleme motoru, `contains` kontrolünü yapmadan önce bu listedeki kelimeleri
 *    metinden güvenli biçimde maskeler (yerine nötr ayraç koyar).
 * 2. Böylece örneğin 'siklamen' içinde 'sik' kökünden dolayı yanlışlıkla
 *    tetiklenebilecek filtreler önlenmiş olur.
 * 3. Büyük/küçük harf veya Türkçe karakter ayrımı yapmanıza gerek yoktur;
 *    motor otomatik olarak normalize eder.
 * 4. Değişiklik sonrası yalnızca `server/` dizininde `npm run deploy` çalıştırmanız
 *    yeterlidir (uygulama güncellemesi gerekmez).
 */

export const ALLOW_WORDS: readonly string[] = [
  // Türkçe Yaygın İsimler / Kelimeler (contains çakışmalarını önlemek için)
  'kemal',
  'cemal',
  'kamil',
  'damla',
  'samet',
  'muhammed',
  'muhammet',
  'pamuk',
  'amiral',
  'hamur',
  'tamam',
  'camgöz',
  'koc',
  'koç',
  'siklamen',
  'kasik',
  'kaşık',
  'fistik',
  'fıstık',
  'lastik',
  'klasik',
  'sarimsak',
  'sarımsak',
  'eksik',
  'fizik',
  'muzik',
  'müzik',
  'taktik',
  'kritik',
  'otantik',
  'pratik',
  'patik',
  'antik',
  'celtik',
  'çeltik',
  'bitik',
  'yitik',
  'tetik',
  'estetik',
  'lastikli',
  'fistikli',
  'siklet',
  'boks',
  'boksor',
  'boksör',
  'asker',
  'passer',
  'classic',
  'associate',
  'asset',
  'pass',
  'grass',
  'class',
  'bass',
];
