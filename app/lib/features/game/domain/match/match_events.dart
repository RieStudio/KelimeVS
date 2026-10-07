// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

enum RoundEndReason {
  timeout,
  exhausted,
  forfeit,
}

sealed class MatchEvent {
  const MatchEvent();
}

class AnswerAccepted extends MatchEvent {
  final String playerId;
  final String answerDisplay;

  const AnswerAccepted(this.playerId, this.answerDisplay);

  @override
  String toString() => 'AnswerAccepted(playerId: $playerId, answer: $answerDisplay)';
}

class NearMiss extends MatchEvent {
  final String playerId;

  const NearMiss(this.playerId);

  @override
  String toString() => 'NearMiss(playerId: $playerId)';
}

class WrongAnswer extends MatchEvent {
  final String playerId;
  final String rawInput;

  const WrongAnswer(this.playerId, [this.rawInput = '']);

  @override
  String toString() => 'WrongAnswer(playerId: $playerId, rawInput: $rawInput)';
}

class AlreadySaid extends MatchEvent {
  final String playerId;
  final String answerDisplay;

  const AlreadySaid(this.playerId, [this.answerDisplay = '']);

  @override
  String toString() => 'AlreadySaid(playerId: $playerId, answer: $answerDisplay)';
}

class RoundWon extends MatchEvent {
  final String winnerId;
  final RoundEndReason reason;

  const RoundWon(this.winnerId, this.reason);

  @override
  String toString() => 'RoundWon(winnerId: $winnerId, reason: $reason)';
}

class RoundDrawn extends MatchEvent {
  final RoundEndReason reason;

  const RoundDrawn(this.reason);

  @override
  String toString() => 'RoundDrawn(reason: $reason)';
}

class MatchFinished extends MatchEvent {
  final String winnerId;
  final String reason;

  const MatchFinished(this.winnerId, [this.reason = 'normal']);

  @override
  String toString() => 'MatchFinished(winnerId: $winnerId, reason: $reason)';
}

class Ignored extends MatchEvent {
  final String reason;

  const Ignored(this.reason);

  @override
  String toString() => 'Ignored(reason: $reason)';
}
