// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

class MatchConfig {
  /// Bir oyuncunun maçı kazanması için gereken galibiyet sayısı (varsayılan 2)
  final int roundsToWin;

  /// Maksimum sonuçlanan (kazananı olan) tur sayısı: 2 * roundsToWin - 1
  int get maxDecisiveRounds => 2 * roundsToWin - 1;

  /// Geriye uyumluluk: eski totalDecisiveRounds alanı maksimum sonuçlanan tura denk gelir
  int get totalDecisiveRounds => maxDecisiveRounds;

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
    int roundsToWin = 2,
    int? totalDecisiveRounds,
    this.answerSeconds = 15,
    this.graceMs = 0,
    this.nearMissPerRound = 1,
    this.minAnswersPerQuestion = 0,
    this.minSubmitIntervalMs = 600,
    this.maxAttemptsPerTurn = 25,
  }) : roundsToWin = totalDecisiveRounds != null
            ? (totalDecisiveRounds + 1) ~/ 2
            : roundsToWin;
}

