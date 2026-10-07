// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

class BotConfig {
  /// Düşünme süresi alt sınırı (milisaniye)
  final int thinkMinMs;

  /// Düşünme süresi üst sınırı (milisaniye)
  final int thinkMaxMs;

  /// Temel bilme olasılığı
  final double baseKnowChance;

  /// Ekstra bilme şansı katsayısı (kalan cevap oranı ile çarpılır)
  final double extraKnowChance;

  /// Bilen botun doğru cevaptan önce yanlış deneme yapma olasılığı
  final double wrongBeforeChance;

  /// Bilmediğinde yanlış cevap denemesi yapma olasılığı (kalanında sessiz kalır)
  final double wrongAnswerChance;

  const BotConfig({
    this.thinkMinMs = 2500,
    this.thinkMaxMs = 9500,
    this.baseKnowChance = 0.35,
    this.extraKnowChance = 0.65,
    this.wrongBeforeChance = 0.3,
    this.wrongAnswerChance = 0.5,
  });
}
