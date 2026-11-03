// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

/// Bot kişilik/davranış profilleri.
enum BotPersona {
  /// Dengeli: Ortalama insan oyuncu hız ve doğruluğunda standart profil (varsayılan).
  dengeli,

  /// Aceleci: Hızlı yanıt veren fakat daha sık yazım hatası ve yanlış deneme yapan profil.
  aceleci,

  /// Düşünür: Daha temkinli ve yavaş düşünen, hata payı düşük profil.
  dusunur,
}

class BotConfig {
  // --- Persona Sabitleri (Tek Doğruluk Kaynağı) ---
  // 1. Dengeli (Varsayılan)
  static const int dengeliThinkMinMs = 2500;
  static const int dengeliThinkMaxMs = 7000;
  static const double dengeliBaseKnowChance = 0.20;
  static const double dengeliExtraKnowChance = 0.52;
  static const double dengeliWrongBeforeChance = 0.25;
  static const double dengeliWrongAnswerChance = 0.50;

  // 2. Aceleci
  static const int aceleciThinkMinMs = 1800;
  static const int aceleciThinkMaxMs = 4500;
  static const double aceleciBaseKnowChance = 0.15;
  static const double aceleciExtraKnowChance = 0.46;
  static const double aceleciWrongBeforeChance = 0.40;
  static const double aceleciWrongAnswerChance = 0.65;

  // 3. Düşünür
  static const int dusunurThinkMinMs = 4500;
  static const int dusunurThinkMaxMs = 9000;
  static const double dusunurBaseKnowChance = 0.26;
  static const double dusunurExtraKnowChance = 0.58;
  static const double dusunurWrongBeforeChance = 0.15;
  static const double dusunurWrongAnswerChance = 0.35;

  // --- Tur İçi Doygunluk / Yorulma Sabitleri ---
  /// Turda botun peş peşe doğru cevap verdiği eşik (3. doğrudan sonra bilme şansı düşer)
  static const int fatigueAnswerThreshold = 3;

  /// 3. doğrudan sonraki bilme şansı çarpanı
  static const double fatigueMultiplier = 0.65;

  // --- Telafi (Rubber-Banding) Sabitleri (En fazla %15) ---
  /// Bot skorda öndeyken bilme şansı çarpanı (%15 azaltma - en fazla %15)
  static const double rubberBandBehindKnowMultiplier = 0.85;

  /// Bot skorda öndeyken düşünme süresi çarpanı (%15 uzatma)
  static const double rubberBandBehindThinkMultiplier = 1.15;

  /// Bot skorda gerideyken bilme şansı çarpanı (%10 toparlanma)
  static const double rubberBandAheadKnowMultiplier = 1.10;

  /// Bot skorda gerideyken düşünme süresi çarpanı (%5 hızlanma)
  static const double rubberBandAheadThinkMultiplier = 0.95;

  // --- Kelime Uzunluğu Süre Ölçekleme Sabitleri ---
  /// Baz kelime karakter uzunluğu
  static const int wordLengthBaseChars = 5;

  /// Karakter başına milisaniye gecikme farkı
  static const int wordLengthPerCharMs = 120;

  /// Aktif kişilik
  final BotPersona persona;

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
    this.persona = BotPersona.dengeli,
    this.thinkMinMs = dengeliThinkMinMs,
    this.thinkMaxMs = dengeliThinkMaxMs,
    this.baseKnowChance = dengeliBaseKnowChance,
    this.extraKnowChance = dengeliExtraKnowChance,
    this.wrongBeforeChance = dengeliWrongBeforeChance,
    this.wrongAnswerChance = dengeliWrongAnswerChance,
  });

  /// Belirtilen persona için önceden tanımlı konfigürasyonu döndürür.
  factory BotConfig.forPersona(BotPersona persona) {
    switch (persona) {
      case BotPersona.dengeli:
        return const BotConfig(
          persona: BotPersona.dengeli,
          thinkMinMs: dengeliThinkMinMs,
          thinkMaxMs: dengeliThinkMaxMs,
          baseKnowChance: dengeliBaseKnowChance,
          extraKnowChance: dengeliExtraKnowChance,
          wrongBeforeChance: dengeliWrongBeforeChance,
          wrongAnswerChance: dengeliWrongAnswerChance,
        );
      case BotPersona.aceleci:
        return const BotConfig(
          persona: BotPersona.aceleci,
          thinkMinMs: aceleciThinkMinMs,
          thinkMaxMs: aceleciThinkMaxMs,
          baseKnowChance: aceleciBaseKnowChance,
          extraKnowChance: aceleciExtraKnowChance,
          wrongBeforeChance: aceleciWrongBeforeChance,
          wrongAnswerChance: aceleciWrongAnswerChance,
        );
      case BotPersona.dusunur:
        return const BotConfig(
          persona: BotPersona.dusunur,
          thinkMinMs: dusunurThinkMinMs,
          thinkMaxMs: dusunurThinkMaxMs,
          baseKnowChance: dusunurBaseKnowChance,
          extraKnowChance: dusunurExtraKnowChance,
          wrongBeforeChance: dusunurWrongBeforeChance,
          wrongAnswerChance: dusunurWrongAnswerChance,
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotConfig &&
          runtimeType == other.runtimeType &&
          persona == other.persona &&
          thinkMinMs == other.thinkMinMs &&
          thinkMaxMs == other.thinkMaxMs &&
          baseKnowChance == other.baseKnowChance &&
          extraKnowChance == other.extraKnowChance &&
          wrongBeforeChance == other.wrongBeforeChance &&
          wrongAnswerChance == other.wrongAnswerChance;

  @override
  int get hashCode => Object.hash(
        persona,
        thinkMinMs,
        thinkMaxMs,
        baseKnowChance,
        extraKnowChance,
        wrongBeforeChance,
        wrongAnswerChance,
      );
}
