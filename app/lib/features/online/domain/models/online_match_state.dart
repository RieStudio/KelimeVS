// Saf Dart - Flutter veya harici paket bağımlılığı yoktur.

/// Canlı maç fazı.
enum OnlineMatchPhase {
  roundActive,
  roundEnded,
  matchFinished,
  unknown;

  static OnlineMatchPhase fromString(String? value) {
    switch (value) {
      case 'roundActive':
        return OnlineMatchPhase.roundActive;
      case 'roundEnded':
        return OnlineMatchPhase.roundEnded;
      case 'matchFinished':
        return OnlineMatchPhase.matchFinished;
      default:
        return OnlineMatchPhase.unknown;
    }
  }
}

/// İstemciye gelen tek bir deneme / cevap balonu.
class OnlineAttempt {
  final bool mine;
  final String text;
  final String result; // 'correct', 'repeated', 'wrong', 'nearMiss', 'timeout'
  final bool hintShown;

  const OnlineAttempt({
    required this.mine,
    required this.text,
    required this.result,
    this.hintShown = false,
  });

  factory OnlineAttempt.fromJson(Map<String, dynamic> json) {
    return OnlineAttempt(
      mine: json['mine'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      result: json['result'] as String? ?? 'wrong',
      hintShown: json['hintShown'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mine': mine,
    'text': text,
    'result': result,
    if (hintShown) 'hintShown': true,
  };
}

/// Soru bilgisi.
class OnlineQuestion {
  final String id;
  final String text;

  const OnlineQuestion({required this.id, required this.text});

  factory OnlineQuestion.fromJson(Map<String, dynamic> json) {
    return OnlineQuestion(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

/// Son tur özeti.
class OnlineLastRound {
  final bool winnerIsMe;
  final bool draw;
  final String reason;

  const OnlineLastRound({
    required this.winnerIsMe,
    required this.draw,
    required this.reason,
  });

  factory OnlineLastRound.fromJson(Map<String, dynamic> json) {
    return OnlineLastRound(
      winnerIsMe: json['winnerIsMe'] as bool? ?? false,
      draw: json['draw'] as bool? ?? false,
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'winnerIsMe': winnerIsMe,
    'draw': draw,
    'reason': reason,
  };
}

/// Sunucu durum mesajının (`state`) güçlü tipli modeli.
class OnlineMatchState {
  final int serverNowMs;
  final int receivedLocalMs;
  final OnlineMatchPhase phase;
  final int roundNumber;
  final int myScore;
  final int opponentScore;
  final OnlineQuestion? question;
  final bool turnIsMine;
  final int deadlineMs;
  final int myHintsLeft;
  final List<OnlineAttempt> attempts;
  final String opponentName;
  final bool opponentConnected;
  final String? endedBy;
  final bool? winnerIsMe;
  final OnlineLastRound? lastRound;
  final int? nextRoundAtMs;

  const OnlineMatchState({
    required this.serverNowMs,
    required this.receivedLocalMs,
    required this.phase,
    required this.roundNumber,
    required this.myScore,
    required this.opponentScore,
    this.question,
    required this.turnIsMine,
    required this.deadlineMs,
    required this.myHintsLeft,
    required this.attempts,
    required this.opponentName,
    required this.opponentConnected,
    this.endedBy,
    this.winnerIsMe,
    this.lastRound,
    this.nextRoundAtMs,
  });

  /// Sunucu saati ile istemcinin yerel saati arasındaki fark:
  /// serverNowMs = receivedLocalMs + clockOffsetMs
  int get clockOffsetMs => serverNowMs - receivedLocalMs;

  /// Verilen yerel zamana göre ([nowLocalMs]) kalan hamle süresini (milisaniye)
  /// sunucu saat sapmasını ([clockOffsetMs]) hesaba katarak hesaplar.
  /// Tur süresi üst sınırı [maxDurationMs] (varsayılan 15000 ms) ile 0 arasında sınırlandırılır (clamp).
  int kalanSureMs(int nowLocalMs, {int maxDurationMs = 15000}) {
    final estimatedServerNow = nowLocalMs + clockOffsetMs;
    final remaining = deadlineMs - estimatedServerNow;
    if (remaining <= 0) return 0;
    return remaining > maxDurationMs ? maxDurationMs : remaining;
  }

  /// [kalanSureMs] için takma ad.
  int remainingDeadlineMs(int nowLocalMs, {int maxDurationMs = 15000}) =>
      kalanSureMs(nowLocalMs, maxDurationMs: maxDurationMs);

  factory OnlineMatchState.fromJson(
    Map<String, dynamic> json, {
    int? receivedLocalMs,
  }) {
    final serverNow = (json['serverNowMs'] as num?)?.toInt() ?? 0;
    final localTime = receivedLocalMs ?? DateTime.now().millisecondsSinceEpoch;

    final scoresMap = json['scores'] as Map<String, dynamic>?;
    final myScore = (scoresMap?['me'] as num?)?.toInt() ?? 0;
    final oppScore = (scoresMap?['opponent'] as num?)?.toInt() ?? 0;

    final qMap = json['question'] as Map<String, dynamic>?;
    final question = qMap != null ? OnlineQuestion.fromJson(qMap) : null;

    final attemptsList = (json['attempts'] as List<dynamic>?)
            ?.map((e) => OnlineAttempt.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    final lastRoundMap = json['lastRound'] as Map<String, dynamic>?;
    final lastRound =
        lastRoundMap != null ? OnlineLastRound.fromJson(lastRoundMap) : null;

    return OnlineMatchState(
      serverNowMs: serverNow,
      receivedLocalMs: localTime,
      phase: OnlineMatchPhase.fromString(json['phase'] as String?),
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
      myScore: myScore,
      opponentScore: oppScore,
      question: question,
      turnIsMine: json['turnIsMine'] as bool? ?? false,
      deadlineMs: (json['deadlineMs'] as num?)?.toInt() ?? 0,
      myHintsLeft: (json['myHintsLeft'] as num?)?.toInt() ?? 0,
      attempts: attemptsList,
      opponentName: json['opponentName'] as String? ?? '',
      opponentConnected: json['opponentConnected'] as bool? ?? false,
      endedBy: json['endedBy'] as String?,
      winnerIsMe: json['winnerIsMe'] as bool?,
      lastRound: lastRound,
      nextRoundAtMs: (json['nextRoundAtMs'] as num?)?.toInt(),
    );
  }
}

