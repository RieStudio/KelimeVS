/// Bot rakipler için gerçek oyuncu dağılımına benzer şekilde deterministik
/// pseudo-random avatar çerçevesi atayıcısı.
///
/// Aynı bot adı için her zaman aynı çerçeveyi üretir.
/// Dağılım:
/// - %60 Klasik (classic)
/// - %8 Gümüş Oyma (silver_engraved)
/// - %8 Bronz Oyma (bronze_engraved)
/// - %6 Dişli (gear)
/// - %5 Buz (ice)
/// - %4 Zümrüt (emerald)
/// - %3 Nazar Boncuğu (nazar)
/// - %3 Altın Yaprak (gold_leaf)
/// - %2 Kiraz Çiçeği (sakura)
/// - %1 Sarmaşık (vine)
abstract final class BotFrameResolver {
  static String resolve(String botName) {
    if (botName.trim().isEmpty) return 'classic';

    // FNV-1a 32-bit hash algoritması
    int hash = 0x811c9dc5;
    for (final unit in botName.trim().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }

    final bucket = hash % 100;

    if (bucket < 60) {
      return 'classic';
    } else if (bucket < 68) {
      return 'silver_engraved';
    } else if (bucket < 76) {
      return 'bronze_engraved';
    } else if (bucket < 82) {
      return 'gear';
    } else if (bucket < 87) {
      return 'ice';
    } else if (bucket < 91) {
      return 'emerald';
    } else if (bucket < 94) {
      return 'nazar';
    } else if (bucket < 97) {
      return 'gold_leaf';
    } else if (bucket < 99) {
      return 'sakura';
    } else {
      return 'vine';
    }
  }
}
