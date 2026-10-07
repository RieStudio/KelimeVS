import '../domain/match/match_events.dart';
import '../domain/match/match_state.dart';

class MatchSummary {
  final Map<String, int> scores;
  final String winnerId;
  final List<RoundRecord> roundHistory;

  const MatchSummary({
    required this.scores,
    required this.winnerId,
    required this.roundHistory,
  });
}

class MatchUiState {
  final MatchState? matchState;
  final int remainingMs;
  final List<MatchEvent> recentEvents;
  final int eventCounter;
  final String myPlayerId;
  final String opponentName;
  final MatchSummary? summary;
  final bool isLoading;
  final String? errorMessage;

  const MatchUiState({
    this.matchState,
    this.remainingMs = 0,
    this.recentEvents = const [],
    this.eventCounter = 0,
    this.myPlayerId = 'me',
    this.opponentName = '',
    this.summary,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isMyTurn =>
      matchState?.phase == MatchPhase.roundActive &&
      matchState?.turnPlayerId == myPlayerId;

  bool get isMatchFinished => matchState?.phase == MatchPhase.matchFinished;
  bool get isRoundActive => matchState?.phase == MatchPhase.roundActive;
  bool get isRoundEnded => matchState?.phase == MatchPhase.roundEnded;

  MatchUiState copyWith({
    MatchState? matchState,
    int? remainingMs,
    List<MatchEvent>? recentEvents,
    int? eventCounter,
    String? myPlayerId,
    String? opponentName,
    MatchSummary? summary,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MatchUiState(
      matchState: matchState ?? this.matchState,
      remainingMs: remainingMs ?? this.remainingMs,
      recentEvents: recentEvents ?? this.recentEvents,
      eventCounter: eventCounter ?? this.eventCounter,
      myPlayerId: myPlayerId ?? this.myPlayerId,
      opponentName: opponentName ?? this.opponentName,
      summary: summary ?? this.summary,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

