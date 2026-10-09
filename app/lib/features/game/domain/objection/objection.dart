// Saf Dart - Flutter, Riverpod veya SharedPreferences bağımlılığı yoktur.

class ObjectionKey {
  final String matchId;
  final int roundIndex;
  final int attemptIndex;

  const ObjectionKey({
    required this.matchId,
    required this.roundIndex,
    required this.attemptIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectionKey &&
          runtimeType == other.runtimeType &&
          matchId == other.matchId &&
          roundIndex == other.roundIndex &&
          attemptIndex == other.attemptIndex;

  @override
  int get hashCode => Object.hash(matchId, roundIndex, attemptIndex);

  @override
  String toString() =>
      'ObjectionKey(matchId: $matchId, round: $roundIndex, attempt: $attemptIndex)';
}

class Objection {
  final String matchId;
  final int roundIndex;
  final int attemptIndex;
  final String rawInput;
  final int createdAtMs;

  const Objection({
    required this.matchId,
    required this.roundIndex,
    required this.attemptIndex,
    required this.rawInput,
    required this.createdAtMs,
  });

  ObjectionKey get key => ObjectionKey(
        matchId: matchId,
        roundIndex: roundIndex,
        attemptIndex: attemptIndex,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Objection &&
          runtimeType == other.runtimeType &&
          matchId == other.matchId &&
          roundIndex == other.roundIndex &&
          attemptIndex == other.attemptIndex;

  @override
  int get hashCode => Object.hash(matchId, roundIndex, attemptIndex);

  @override
  String toString() =>
      'Objection(matchId: $matchId, round: $roundIndex, attempt: $attemptIndex, rawInput: $rawInput)';
}

