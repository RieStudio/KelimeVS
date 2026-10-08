import 'dart:async';
import 'dart:math' as math;

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
import '../domain/models.dart';
import '../domain/text_filter.dart';
import 'match_providers.dart';
import 'match_ui_state.dart';

abstract interface class GameClock {
  int nowMs();
}

class StopwatchClock implements GameClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  int nowMs() => _stopwatch.elapsedMilliseconds;
}

class MatchController extends Notifier<MatchUiState> {
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
  List<BotAction> _pendingBotActions = const [];
  int _botActionIndex = 0;
  List<Question> _loadedQuestions = const [];

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
      _cancelAllTimers();
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

    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      acceptedAnswers: const [],
      roundAttempts: const [],
      lastFeedback: null,
      feedbackCounter: 0,
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

  /// Kullanıcının maçı terk etmesini sağlar.
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

    // Tur içi tüm denemeler (kronolojik, timeout hariç)
    final List<RoundAttemptUiModel> updatedRoundAttempts;
    if (isNewRound) {
      updatedRoundAttempts = const [];
    } else {
      updatedRoundAttempts = nextState.currentRoundAttempts
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
    if (nextState.phase == MatchPhase.matchFinished) {
      _cancelAllTimers();
      summary = MatchSummary(
        scores: nextState.scores,
        winnerId: nextState.winnerId!,
        roundHistory: nextState.roundHistory,
      );
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
    );

    if (nextState.phase == MatchPhase.roundEnded) {
      // Tur bitti: 3000 ms sonra otomatik yeni tur başlat
      _cancelBotTimer();
      _cancelTransitionTimer();
      _transitionTimer = Timer(Duration(milliseconds: roundTransitionDelayMs), () {
        _startNextRound(clock, random);
      });
    } else if (nextState.phase == MatchPhase.roundActive) {
      // Sıra bota YENİ geçtiyse bot zamanlayıcısını kur
      if (!wasBotActive && nextState.turnPlayerId == 'bot') {
        _scheduleBotTurn(nextState, clock, random);
      }
    }
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
      if (match == null || match.phase != MatchPhase.roundActive) return;

      final now = clock.nowMs();
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
    });
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
  }
}

