// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

class BotAction {
  /// Bu eylem öncesi bekleme süresi (milisaniye)
  final int delayMs;

  /// Botun göndereceği girdi metni
  final String input;

  const BotAction(this.delayMs, this.input);
  const BotAction.named({required this.delayMs, required this.input});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotAction &&
          runtimeType == other.runtimeType &&
          delayMs == other.delayMs &&
          input == other.input;

  @override
  int get hashCode => delayMs.hashCode ^ input.hashCode;

  @override
  String toString() => 'BotAction($delayMs, "$input")';
}

class BotDecision {
  /// Botun yapacağı zamanlı eylemler listesi
  final List<BotAction> actions;

  const BotDecision({
    required this.actions,
  });

  bool get willTimeout => actions.isEmpty;

  @override
  String toString() => 'BotDecision(actions: $actions)';
}
