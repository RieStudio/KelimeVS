import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/question_repository.dart';
import '../domain/attempt_text_sanitizer.dart';
import '../domain/bot/bot_config.dart';
import '../domain/bot/bot_decision.dart';
import '../domain/bot/bot_player.dart';
import '../domain/match/match_config.dart';
import '../domain/match/match_engine.dart';
import '../domain/match/match_events.dart';
import '../domain/match/match_state.dart';
import '../domain/history/match_history_entry.dart';
import '../domain/models.dart';
import '../domain/text_filter.dart';
import 'match_history_provider.dart';
import 'match_providers.dart';
import 'match_session.dart';
import 'match_ui_state.dart';

abstract interface class GameClock {
  int nowMs();
}

class SystemClock implements GameClock {
  const SystemClock();

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;
}

class StopwatchClock implements GameClock {
  final int _initialEpochMs = DateTime.now().millisecondsSinceEpoch;
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  int nowMs() => _initialEpochMs + _stopwatch.elapsedMilliseconds;
}

class MatchController extends Notifier<MatchUiState> implements MatchSession {
  final GameClock? _injectedClock;
  final math.Random? _injectedRandom;
  final QuestionRepository? _injectedRepo;
  final BotConfig? _injectedBotConfig;
  final MatchConfig? _injectedMatchConfig;
  final TextFilter? _injectedTextFilter;
  final int roundTransitionDelayMs;

  MatchController({
    GameClock? clock,
    math.Random? random,
    QuestionRepository? repository,
    BotConfig? botConfig,
    MatchConfig? matchConfig,
    TextFilter? textFilter,
    this.roundTransitionDelayMs = 3000,
  })  : _injectedClock = clock,
        _injectedRandom = random,
        _injectedRepo = repository,
        _injectedBotConfig = botConfig,
        _injectedMatchConfig = matchConfig,
        _injectedTextFilter = textFilter;

  Timer? _tickTimer;
  Timer? _botTimer;
  Timer? _transitionTimer;
  int? _transitionDeadlineMs;
  List<BotAction> _pendingBotActions = const [];
  int _botActionIndex = 0;
  List<Question> _loadedQuestions = const [];
  bool _isMatchSaved = false;

  static const List<String> _opponentNames = [
    'Ahmet',
    'Zeynep',
    'Mehmet',
    'Ayşe',
    'Can',
    'Elif',
    'Emre',
    'Burak',
    'Selin',
    'Deniz',
  ];

  @override
  MatchUiState build() {
    ref.onDispose(() {
      dispose();
    });
    return const MatchUiState();
  }

  GameClock get _clock => _injectedClock ?? ref.read(gameClockProvider);
  math.Random get _random => _injectedRandom ?? ref.read(randomProvider);
  QuestionRepository get _repo => _injectedRepo ?? ref.read(questionRepositoryProvider);
  BotConfig get _botConfig => _injectedBotConfig ?? ref.read(botConfigProvider);
  MatchConfig get _matchConfig => _injectedMatchConfig ?? ref.read(matchConfigProvider);
  TextFilter get _textFilter => _injectedTextFilter ?? ref.read(textFilterProvider);

  /// Yeni bir botlu maç başlatır.
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
  }) async {
    // TODO: arka plan davranışı
    _cancelAllTimers();
    _isMatchSaved = false;

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      acceptedAnswers: const [],
      roundAttempts: const [],
      lastFeedback: null,
      feedbackCounter: 0,
      isFinalReveal: false,
      roundTransitionRemainingMs: 0,
      roundTransitionTotalMs: roundTransitionDelayMs,
      opponentConnected: true,
      isVoided: false,
      isDisconnectedPermanent: false,
    );

    final List<Question> pool;
    if (questions != null) {
      pool = questions;
    } else {
      try {
        pool = await _repo.loadAll();
      } catch (e) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Sorular yüklenirken hata oluştu: $e',
        );
        return;
      }
    }

    if (pool.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Soru havuzu boş.',
      );
      return;
    }

    _loadedQuestions = pool;
    final random = _random;
    final clock = _clock;

    final chosenOpponent = opponentName ?? _opponentNames[random.nextInt(_opponentNames.length)];
    final now = clock.nowMs();

    final engineResult = MatchEngine.start(
      config: _matchConfig,
      playerIds: ['me', 'bot'],
      questions: pool,
      random: random,
      nowMs: now,
    );

    _applyEngineResult(
      engineResult: engineResult,
      clock: clock,
      random: random,
      opponentName: chosenOpponent,
    );

    // 200 ms periyodik zamanlayıcı başlat
    _startTickTimer(clock);
  }

  /// Kullanıcının ('me') cevabını motora iletir.
  @override
  void submit(String text) {
    // TODO: arka plan davranışı
    final sanitized = AttemptTextSanitizer.sanitize(text);
    if (sanitized.isEmpty) return;

    final match = state.matchState;
    if (match == null || match.phase != MatchPhase.roundActive) return;
    if (match.turnPlayerId != 'me') return;

    final clock = _clock;
    final random = _random;
    final now = clock.nowMs();

    final res = MatchEngine.submit(
      state: match,
      playerId: 'me',
      rawInput: sanitized,
      nowMs: now,
    );

    _applyEngineResult(
      engineResult: res,
      clock: clock,
      random: random,
    );
  }

  @override
  void useExtraTime() {
    // Bot maçlarında ek süre güçlendiricisi kullanılamaz.
  }

  /// Kullanıcının maçı terk etmesini sağlar.
  @override
  void leaveMatch() {
    // TODO: arka plan davranışı
    final match = state.matchState;
    if (match == null || match.phase == MatchPhase.matchFinished) return;

    _cancelAllTimers();
    final clock = _clock;
    final random = _random;
    final now = clock.nowMs();

    final res = MatchEngine.forfeit(
      state: match,
      playerId: 'me',
      nowMs: now,
    );

    _applyEngineResult(
      engineResult: res,
      clock: clock,
      random: random,
    );
  }

  @visibleForTesting
  void applyEngineResultForTesting(EngineResult result) {
    _applyEngineResult(
      engineResult: result,
      clock: _clock,
      random: _random,
    );
  }

  void _applyEngineResult({
    required EngineResult engineResult,
    required GameClock clock,
    required math.Random random,
    String? opponentName,
  }) {
    final nextState = engineResult.state;
    final events = engineResult.events;
    final prevState = state.matchState;
    final wasBotActive = prevState?.phase == MatchPhase.roundActive &&
        prevState?.turnPlayerId == 'bot';

    // Sıra veya faz bota ait değilse bekleyen bot aksiyonunu iptal et
    if (nextState.phase != MatchPhase.roundActive || nextState.turnPlayerId != 'bot') {
      _cancelBotTimer();
    }

    final now = clock.nowMs();
    final remaining = nextState.phase == MatchPhase.roundActive
        ? math.max(0, nextState.deadlineMs - now)
        : 0;

    final updatedEvents = events.isNotEmpty
        ? [...state.recentEvents, ...events]
        : state.recentEvents;

    final updatedEventCounter = events.isNotEmpty
        ? state.eventCounter + events.length
        : state.eventCounter;

    // Tur içi kabul edilen cevaplar
    final isNewRound = nextState.currentRoundAttempts.isEmpty;
    final updatedAcceptedAnswers = isNewRound
        ? <AcceptedAnswerUiModel>[]
        : List<AcceptedAnswerUiModel>.from(state.acceptedAnswers);

    // Tur içi tüm denemeler (kronolojik, timeout hariç, aktif turda rakibin yakın denemeleri gizli)
    final List<RoundAttemptUiModel> updatedRoundAttempts;
    if (isNewRound) {
      updatedRoundAttempts = const [];
    } else {
      final isRoundActive = nextState.phase == MatchPhase.roundActive;
      final visible = visibleAttempts(
        nextState.currentRoundRecord,
        state.myPlayerId,
        isRoundActive,
      );
      updatedRoundAttempts = visible
          .where((att) => att.resultType != AttemptResultType.timeout)
          .map((att) {
        String text;
        if (att.resultType == AttemptResultType.correct && att.answerId != null) {
          final matched = nextState.currentQuestion?.answers
              .where((a) => a.id == att.answerId)
              .firstOrNull;
          text = matched?.display ?? att.rawInput;
        } else {
          text = att.rawInput;
        }
        text = AttemptTextSanitizer.sanitize(text);
        if (att.playerId != state.myPlayerId) {
          text = _textFilter.apply(text);
        }
        return RoundAttemptUiModel(
          playerId: att.playerId,
          text: text,
          isCorrect: att.resultType == AttemptResultType.correct,
          isClose: att.isClose,
        );
      }).toList();
    }

    MatchFeedbackType? newFeedback;
    for (final event in events) {
      if (event is AnswerAccepted) {
        updatedAcceptedAnswers.add(
          AcceptedAnswerUiModel(
            playerId: event.playerId,
            display: event.answerDisplay,
          ),
        );
      } else if (event is WrongAnswer && event.playerId == 'me') {
        newFeedback = MatchFeedbackType.wrong;
      } else if (event is AlreadySaid && event.playerId == 'me') {
        newFeedback = MatchFeedbackType.alreadySaid;
      } else if (event is NearMiss && event.playerId == 'me') {
        newFeedback = MatchFeedbackType.nearMiss;
      }
    }

    final updatedFeedback = newFeedback ?? state.lastFeedback;
    final updatedFeedbackCounter = newFeedback != null
        ? state.feedbackCounter + 1
        : state.feedbackCounter;

    MatchSummary? summary;
    bool isFinal = false;
    int transitionRemaining = 0;

    if (nextState.phase == MatchPhase.matchFinished) {
      if (!_isMatchSaved) {
        _isMatchSaved = true;
        _saveMatchToHistory(nextState, clock, opponentName ?? state.opponentName);
      }
      summary = MatchSummary(
        scores: nextState.scores,
        winnerId: nextState.winnerId!,
        roundHistory: nextState.roundHistory,
      );

      if (nextState.endedBy == 'normal') {
        isFinal = true;
        _cancelBotTimer();
        _cancelTransitionTimer();
        final transitionDelay = roundTransitionDelayMs;
        _transitionDeadlineMs = now + transitionDelay;
        transitionRemaining = transitionDelay;
        _transitionTimer = Timer(Duration(milliseconds: transitionDelay), () {
          _cancelAllTimers();
          state = state.copyWith(
            isFinalReveal: false,
            roundTransitionRemainingMs: 0,
          );
        });
      } else {
        // forfeit -> tur sonunu atla, hemen maç sonucu
        _cancelAllTimers();
      }
    } else if (nextState.phase == MatchPhase.roundEnded) {
      // Tur bitti: roundTransitionDelayMs sonra otomatik yeni tur başlat
      _cancelBotTimer();
      _cancelTransitionTimer();
      final transitionDelay = roundTransitionDelayMs;
      _transitionDeadlineMs = now + transitionDelay;
      transitionRemaining = transitionDelay;
      _transitionTimer = Timer(Duration(milliseconds: transitionDelay), () {
        _startNextRound(clock, random);
      });
    } else if (nextState.phase == MatchPhase.roundActive) {
      _cancelTransitionTimer();
      // Sıra bota YENİ geçtiyse bot zamanlayıcısını kur
      if (!wasBotActive && nextState.turnPlayerId == 'bot') {
        _scheduleBotTurn(nextState, clock, random);
      }
    }

    state = state.copyWith(
      matchState: nextState,
      remainingMs: remaining,
      recentEvents: updatedEvents,
      eventCounter: updatedEventCounter,
      opponentName: opponentName ?? state.opponentName,
      summary: summary,
      isLoading: false,
      acceptedAnswers: updatedAcceptedAnswers,
      roundAttempts: updatedRoundAttempts,
      lastFeedback: updatedFeedback,
      feedbackCounter: updatedFeedbackCounter,
      isFinalReveal: isFinal,
      roundTransitionRemainingMs: transitionRemaining,
      roundTransitionTotalMs: roundTransitionDelayMs,
    );
  }

  void _scheduleBotTurn(MatchState match, GameClock clock, math.Random random) {
    _cancelBotTimer();

    final decision = BotPlayer.decide(
      question: match.currentQuestion!,
      usedAnswerIds: match.usedAnswerIds,
      random: random,
      config: _botConfig,
    );

    if (decision.actions.isNotEmpty) {
      _pendingBotActions = decision.actions;
      _botActionIndex = 0;
      _scheduleNextBotAction(clock, random);
    }
    // decision.actions.isEmpty ise zamanlayıcı kurulmaz; 200ms tick timer süreyi doldurur.
  }

  void _scheduleNextBotAction(GameClock clock, math.Random random) {
    if (_botActionIndex >= _pendingBotActions.length) return;
    final action = _pendingBotActions[_botActionIndex];

    _botTimer = Timer(Duration(milliseconds: action.delayMs), () {
      final currentMatch = state.matchState;
      if (currentMatch == null ||
          currentMatch.phase != MatchPhase.roundActive ||
          currentMatch.turnPlayerId != 'bot') {
        return;
      }

      final now = clock.nowMs();
      final res = MatchEngine.submit(
        state: currentMatch,
        playerId: 'bot',
        rawInput: action.input,
        nowMs: now,
      );

      _applyEngineResult(
        engineResult: res,
        clock: clock,
        random: random,
      );

      // Cevap kabul edilmediyse (yanlış, tekrar, yakın ipucu) sıra hala botta kalır;
      // Bu durumda sıradaki bot eylemini zamanla
      final updatedMatch = state.matchState;
      if (updatedMatch != null &&
          updatedMatch.phase == MatchPhase.roundActive &&
          updatedMatch.turnPlayerId == 'bot') {
        _botActionIndex++;
        _scheduleNextBotAction(clock, random);
      }
    });
  }

  void _startNextRound(GameClock clock, math.Random random) {
    final match = state.matchState;
    if (match == null || match.phase != MatchPhase.roundEnded) return;

    final now = clock.nowMs();
    final res = MatchEngine.startNextRound(
      state: match,
      questions: _loadedQuestions,
      random: random,
      nowMs: now,
    );

    _applyEngineResult(
      engineResult: res,
      clock: clock,
      random: random,
    );
  }

  void _startTickTimer(GameClock clock) {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final match = state.matchState;
      if (match == null) return;

      final now = clock.nowMs();

      // Geçiş süresi (roundEnded veya isFinalReveal) sayacı
      if (_transitionDeadlineMs != null) {
        final transitionRemaining = math.max(0, _transitionDeadlineMs! - now);
        state = state.copyWith(roundTransitionRemainingMs: transitionRemaining);
      }

      if (match.phase == MatchPhase.roundActive) {
        final remaining = math.max(0, match.deadlineMs - now);
        state = state.copyWith(remainingMs: remaining);

        // Süre aşımı kontrolü
        if (now > match.deadlineMs + match.config.graceMs) {
          final res = MatchEngine.checkTimeout(state: match, nowMs: now);
          if (res.events.isNotEmpty) {
            _applyEngineResult(
              engineResult: res,
              clock: clock,
              random: _random,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _cancelAllTimers();
  }

  void _cancelAllTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _cancelBotTimer();
    _cancelTransitionTimer();
  }

  void _cancelBotTimer() {
    _botTimer?.cancel();
    _botTimer = null;
    _pendingBotActions = const [];
    _botActionIndex = 0;
  }

  void _cancelTransitionTimer() {
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _transitionDeadlineMs = null;
  }

  static String _shortErrorMessage(Object error) {
    final sanitized = error
        .toString()
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'[A-Za-z0-9_-]{32,}'), '[redacted]')
        .trim();
    if (sanitized.length <= 80) return sanitized;
    return '${sanitized.substring(0, 80)}...';
  }

  Future<void> _saveMatchToHistory(
    MatchState finishedState,
    GameClock clock,
    String opponentName,
  ) async {
    try {
      final myScore = finishedState.scores['me'] ?? 0;
      final opponentScore = finishedState.scores['bot'] ?? 0;
      final isWinner = finishedState.winnerId == 'me';
      final isForfeit = finishedState.endedBy == 'forfeit';
      final forfeitedPlayer = isForfeit
          ? (isWinner ? 'bot' : 'me')
          : null;

      if (kDebugMode) {
        debugPrint(
          '[history] kayıt istendi (kaynak: ${isForfeit ? 'forfeit' : 'bot'})',
        );
      }

      final questionTexts = finishedState.roundHistory.map((r) {
        final q = _loadedQuestions.where((item) => item.id == r.questionId).firstOrNull;
        return q?.text ?? 'Soru';
      }).toList();

      final finishedAtMs = math.max(
        clock.nowMs(),
        DateTime.now().millisecondsSinceEpoch,
      );

      final entry = MatchHistoryEntry(
        id: 'match_${finishedAtMs}_${_random.nextInt(100000)}',
        opponentName: opponentName.isNotEmpty ? opponentName : 'Rakip',
        finishedAtMs: finishedAtMs,
        myScore: myScore,
        opponentScore: opponentScore,
        result: isWinner ? MatchResult.win : MatchResult.lose,
        endType: isForfeit ? MatchEndType.forfeit : MatchEndType.normal,
        forfeitedPlayerId: forfeitedPlayer,
        roundRecords: finishedState.roundHistory,
        roundQuestionTexts: questionTexts,
        botlaOynandi: true,
      );

      state = state.copyWith(lastSavedMatch: entry);

      final repo = ref.read(matchHistoryRepositoryProvider);
      await repo.add(entry);
      ref.invalidate(matchHistoryProvider);
      if (kDebugMode) {
        debugPrint('[history] liste yenilendi');
      }
      state = state.copyWith(lastSavedMatch: entry);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[history] yazma HATASI: ${e.runtimeType}: ${_shortErrorMessage(e)}',
        );
      }
    }
  }
}

