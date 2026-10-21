/// Bot rakipler için gerçek oyuncu dağılımına benzer şekilde deterministik
/// pseudo-random avatar çerçevesi atayıcısı.
///
/// Aynı bot adı için her zaman aynı çerçeveyi üretir.
/// Dağılım:
/// - %70 Klasik (classic)
/// - %10 Nane (mint)
/// - %7 Gün Batımı (sunset)
/// - %6 Okyanus (ocean)
/// - %3 Altın (gold)
/// - %2 Neon (neon)
/// - %1 Gökkuşağı (rainbow)
/// - %1 Elmas (diamond)
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

    if (bucket < 70) {
      return 'classic';
    } else if (bucket < 80) {
      return 'mint';
    } else if (bucket < 87) {
      return 'sunset';
    } else if (bucket < 93) {
      return 'ocean';
    } else if (bucket < 96) {
      return 'gold';
    } else if (bucket < 98) {
      return 'neon';
    } else if (bucket < 99) {
      return 'rainbow';
    } else {
      return 'diamond';
    }
  }
}

