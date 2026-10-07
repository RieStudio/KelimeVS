// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

class MatchConfig {
  /// Maçın bitmesi için gereken toplam sonuçlanan (kazananı olan) tur sayısı
  final int totalDecisiveRounds;

  /// Oyuncunun her cevap hakkı için süresi (saniye)
  final int answerSeconds;

  /// Sunucu / ağ toleransı gecikme süresi (milisaniye)
  final int graceMs;

  /// Her turda oyuncu başına izin verilen maksimum "çok yakın" hakkı
  final int nearMissPerRound;

  /// Maçta kullanılacak sorular için minimum ana cevap sayısı eşiği (0 = kapalı)
  final int minAnswersPerQuestion;

  /// Aynı oyuncunun iki denemesi arasındaki minimum süre (milisaniye)
  final int minSubmitIntervalMs;

  /// Bir oyuncunun bir turdaki sırasında yapabileceği maksimum deneme sayısı
  final int maxAttemptsPerTurn;

  const MatchConfig({
    this.totalDecisiveRounds = 3,
    this.answerSeconds = 15,
    this.graceMs = 0,
    this.nearMissPerRound = 1,
    this.minAnswersPerQuestion = 0,
    this.minSubmitIntervalMs = 600,
    this.maxAttemptsPerTurn = 25,
  });
}

