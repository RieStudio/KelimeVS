// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

class BotDecision {
  /// Botun vereceği cevap girdisi.
  /// `null` ise bot hiçbir şey yazmaz ve süreyi geçirir (timeout).
  final String? input;

  /// Hamle öncesi bekleme süresi (milisaniye)
  final int delayMs;

  const BotDecision({
    required this.input,
    required this.delayMs,
  });

  bool get willTimeout => input == null;

  @override
  String toString() => 'BotDecision(input: $input, delayMs: $delayMs)';
}

