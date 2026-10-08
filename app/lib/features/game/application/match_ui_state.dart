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

class AcceptedAnswerUiModel {
  final String playerId;
  final String display;

  const AcceptedAnswerUiModel({
    required this.playerId,
    required this.display,
  });
}

class RoundAttemptUiModel {
  final String playerId;
  final String text;
  final bool isCorrect;

  const RoundAttemptUiModel({
    required this.playerId,
    required this.text,
    required this.isCorrect,
  });
}

enum MatchFeedbackType {
  wrong,
  alreadySaid,
  nearMiss,
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
  final List<AcceptedAnswerUiModel> acceptedAnswers;
  final List<RoundAttemptUiModel> roundAttempts;
  final MatchFeedbackType? lastFeedback;
  final int feedbackCounter;

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
    this.acceptedAnswers = const [],
    this.roundAttempts = const [],
    this.lastFeedback,
    this.feedbackCounter = 0,
  });

  bool get isMyTurn =>
      matchState?.phase == MatchPhase.roundActive &&
      matchState?.turnPlayerId == myPlayerId;

  bool get isMatchFinished => matchState?.phase == MatchPhase.matchFinished;
  bool get isRoundActive => matchState?.phase == MatchPhase.roundActive;
  bool get isRoundEnded => matchState?.phase == MatchPhase.roundEnded;

  List<RoundAttemptUiModel> get displayAttempts {
    if (roundAttempts.isNotEmpty) {
      return roundAttempts;
    }
    return acceptedAnswers
        .map((a) => RoundAttemptUiModel(
              playerId: a.playerId,
              text: a.display,
              isCorrect: true,
            ))
        .toList();
  }

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
    List<AcceptedAnswerUiModel>? acceptedAnswers,
    List<RoundAttemptUiModel>? roundAttempts,
    MatchFeedbackType? lastFeedback,
    int? feedbackCounter,
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
      acceptedAnswers: acceptedAnswers ?? this.acceptedAnswers,
      roundAttempts: roundAttempts ?? this.roundAttempts,
      lastFeedback: lastFeedback ?? this.lastFeedback,
      feedbackCounter: feedbackCounter ?? this.feedbackCounter,
    );
  }
}

