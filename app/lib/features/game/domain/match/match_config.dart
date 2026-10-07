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

  const MatchConfig({
    this.totalDecisiveRounds = 3,
    this.answerSeconds = 15,
    this.graceMs = 0,
    this.nearMissPerRound = 1,
  });
}

