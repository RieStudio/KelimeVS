import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_dimens.dart';
import '../../../core/utils/bot_frame_resolver.dart';

import '../data/question_repository.dart';
import '../domain/attempt_text_sanitizer.dart';
import '../domain/bot/bot_config.dart';
import '../domain/bot/bot_decision.dart';
import '../domain/bot/bot_opponent_names.dart';
import '../domain/bot/bot_player.dart';
import '../domain/match/match_config.dart';
import '../domain/match/match_engine.dart';
import '../domain/match/match_events.dart';
import '../domain/match/match_state.dart';
import '../domain/history/match_history_entry.dart';
import '../domain/models.dart';
import '../domain/text_filter.dart';
import '../../profile/application/profile_notifier.dart';
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

class MatchController extends Notifier<MatchUiState>
    with WidgetsBindingObserver
    implements MatchSession {
  final GameClock? _injectedClock;
  final math.Random? _injectedRandom;
  final QuestionRepository? _injectedRepo;
  final BotConfig? _injectedBotConfig;
  final MatchConfig? _injectedMatchConfig;
  final TextFilter? _injectedTextFilter;
  final SharedPreferences? _injectedPrefs;
  final String? _injectedSelfNickname;
  final int roundTransitionDelayMs;

  MatchController({
    GameClock? clock,
    math.Random? random,
    QuestionRepository? repository,
    BotConfig? botConfig,
    MatchConfig? matchConfig,
    TextFilter? textFilter,
    SharedPreferences? prefs,
    String? selfNickname,
    this.roundTransitionDelayMs = AppDimens.roundTransitionDurationMs,
  })  : _injectedClock = clock,
        _injectedRandom = random,
        _injectedRepo = repository,
        _injectedBotConfig = botConfig,
        _injectedMatchConfig = matchConfig,
        _injectedTextFilter = textFilter,
        _injectedPrefs = prefs,
        _injectedSelfNickname = selfNickname;

  Timer? _tickTimer;
  Timer? _botTimer;
  int? _botDeadlineMs;
  Timer? _transitionTimer;
  int? _transitionDeadlineMs;
  static const int matchFinishDelayMs = 500;
  MatchState? _pendingFinishedMatchState;
  MatchSummary? _pendingSummary;
  List<BotAction> _pendingBotActions = const [];
  int _botActionIndex = 0;
  List<Question> _loadedQuestions = const [];
  List<String>? _questionOrder;
  Question? _pendingNextQuestion;
  bool _isMatchSaved = false;

  bool _isObserverRegistered = false;
  bool _isPaused = false;
  int? _frozenRemainingTurnMs;
  int? _frozenRemainingBotDelayMs;
  int? _frozenRemainingTransitionMs;
  bool _isDisposed = false;

  @visibleForTesting
  bool get isObserverRegisteredForTesting => _isObserverRegistered;

  @visibleForTesting
  bool get isPausedForTesting => _isPaused;

  @visibleForTesting
  void handleAppLifecycleStateForTesting(AppLifecycleState lifecycleState) {
    didChangeAppLifecycleState(lifecycleState);
  }

  void _registerLifecycleObserver() {
    if (!_isObserverRegistered && !_isDisposed) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _isObserverRegistered = true;
      } catch (_) {
        // Test ortamında WidgetsBinding başlatılmamış olabilir (saf Dart / fakeAsync testleri).
      }
    }
  }

  void _unregisterLifecycleObserver() {
    if (_isObserverRegistered) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _isObserverRegistered = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !_isObserverRegistered) return;
    final match = this.state.matchState;
    if (match == null || match.phase == MatchPhase.matchFinished) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pauseMatch();
    } else if (state == AppLifecycleState.resumed) {
      _resumeMatch();
    }
  }

  void _pauseMatch() {
    if (_isPaused || _isDisposed) return;
    final match = state.matchState;
    if (match == null || match.phase == MatchPhase.matchFinished) return;

    final clock = _clock;
    final now = clock.nowMs();

    _isPaused = true;

    // 1. Aktif tur süresini dondur
    if (match.phase == MatchPhase.roundActive) {
      _frozenRemainingTurnMs = math.max(0, match.deadlineMs - now);
    } else {
      _frozenRemainingTurnMs = null;
    }

    // 2. Bot zamanlayıcısını dondur
    if (_botTimer != null && _botDeadlineMs != null) {
      _frozenRemainingBotDelayMs = math.max(0, _botDeadlineMs! - now);
      _botTimer?.cancel();
      _botTimer = null;
    } else {
      _frozenRemainingBotDelayMs = null;
    }

    // 3. Geçiş zamanlayıcısını dondur
    if (_transitionTimer != null && _transitionDeadlineMs != null) {
      _frozenRemainingTransitionMs = math.max(0, _transitionDeadlineMs! - now);
      _transitionTimer?.cancel();
      _transitionTimer = null;
    } else {
      _frozenRemainingTransitionMs = null;
    }

    // 4. Tick timer'ı durdur (arka planda hiçbir şey tetiklenmesin)
    _tickTimer?.cancel();
    _tickTimer = null;

    state = state.copyWith(isPaused: true);
  }

  void _resumeMatch() {
    if (!_isPaused || _isDisposed) return;
    final match = state.matchState;
    if (match == null || match.phase == MatchPhase.matchFinished) {
      _isPaused = false;
      state = state.copyWith(isPaused: false);
      return;
    }

    final clock = _clock;
    final random = _random;
    final now = clock.nowMs();

    MatchState updatedMatch = match;

    // 1. Aktif tur vadesini ötele (kaldığı nominal süreyle devam etsin)
    int remaining = state.remainingMs;
    if (match.phase == MatchPhase.roundActive && _frozenRemainingTurnMs != null) {
      final newDeadlineMs = now + _frozenRemainingTurnMs!;
      updatedMatch = match.copyWith(deadlineMs: newDeadlineMs);
      remaining = _frozenRemainingTurnMs!;
      _frozenRemainingTurnMs = null;
    }

    // 2. Bot zamanlayıcısını yalnızca duraklatılmadan önce aktif idiyse canlandır
    if (_frozenRemainingBotDelayMs != null &&
        updatedMatch.phase == MatchPhase.roundActive &&
        updatedMatch.turnPlayerId == 'bot' &&
        _botActionIndex < _pendingBotActions.length) {
      final botRemaining = _frozenRemainingBotDelayMs!;
      _frozenRemainingBotDelayMs = null;
      _botDeadlineMs = now + botRemaining;
      _botTimer = Timer(Duration(milliseconds: botRemaining), () {
        _executeBotAction(clock, random);
      });
    } else {
      _frozenRemainingBotDelayMs = null;
    }

    // 3. Geçiş zamanlayıcısını yalnızca duraklatılmadan önce aktif idiyse canlandır
    int transitionRemaining = state.roundTransitionRemainingMs;
    if (_frozenRemainingTransitionMs != null) {
      final transRemaining = _frozenRemainingTransitionMs!;
      _frozenRemainingTransitionMs = null;
      _transitionDeadlineMs = now + transRemaining;
      transitionRemaining = transRemaining;

      if (_pendingFinishedMatchState != null) {
        _transitionTimer = Timer(Duration(milliseconds: transRemaining), () {
          _commitFinishedMatch();
        });
      } else if (updatedMatch.phase == MatchPhase.roundEnded) {
        _transitionTimer = Timer(Duration(milliseconds: transRemaining), () {
          _startNextRound(clock, random);
        });
      }
    }

    if (_pendingFinishedMatchState != null) {
      _isPaused = false;
      state = state.copyWith(
        isPaused: false,
        remainingMs: 0,
        roundTransitionRemainingMs: transitionRemaining,
      );
      return;
    }

    _isPaused = false;

    state = state.copyWith(
      isPaused: false,
      matchState: updatedMatch,
      remainingMs: remaining,
      roundTransitionRemainingMs: transitionRemaining,
    );

    // 4. Tick timer'ı yeniden başlat
    _startTickTimer(clock);
  }

  BotConfig? _activeBotConfig;
  int _roundBotSuccessCount = 0;

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
  BotConfig get _botConfig {
    if (_injectedBotConfig != null) return _injectedBotConfig;
    final provided = ref.read(botConfigProvider);
    if (provided != const BotConfig()) {
      return provided;
    }
    return _activeBotConfig ?? provided;
  }
  MatchConfig get _matchConfig => _injectedMatchConfig ?? ref.read(matchConfigProvider);
  TextFilter get _textFilter => _injectedTextFilter ?? ref.read(textFilterProvider);

  /// Yeni bir botlu maç başlatır.
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
    String? initialTurnPlayerId,
    BotConfig? botConfig,
    String? preselectedQuestionId,
    List<String>? questionOrder,
  }) async {
    _cancelAllTimers();
    _isMatchSaved = false;
    _isPaused = false;
    _frozenRemainingTurnMs = null;
    _frozenRemainingBotDelayMs = null;
    _botDeadlineMs = null;
    _frozenRemainingTransitionMs = null;
    _roundBotSuccessCount = 0;
    _pendingNextQuestion = null;
    _registerLifecycleObserver();

    final random = _random;
    final clock = _clock;

    state = state.copyWith(
      isPaused: false,
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
      // Yeni maç başlarken önceki maçtan kalan boardScores kesinlikle temizlenir.
      // Aksi hâlde eski maçın son skoru yeni maçın ilk turunda görünür.
      clearBoardScores: true,
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

    final String chosenOpponent;
    if (opponentName != null) {
      chosenOpponent = opponentName;
    } else {
      String? selfNickname = _injectedSelfNickname;
      if (selfNickname == null) {
        try {
          selfNickname = ref.read(profileProvider).nickname?.trim();
        } catch (_) {}
      }
      chosenOpponent = BotOpponentNames.pickOpponentName(
        random: random,
        recentNames: _injectedPrefs != null
            ? BotOpponentNames.loadRecentNames(_injectedPrefs)
            : const [],
        excludeName: selfNickname,
      );
    }

    if (_injectedPrefs != null) {
      unawaited(BotOpponentNames.recordRecentName(chosenOpponent, _injectedPrefs));
    } else {
      SharedPreferences.getInstance().then((prefs) {
        BotOpponentNames.recordRecentName(chosenOpponent, prefs);
      }).catchError((_) {});
    }

    final now = clock.nowMs();

    final firstPlayerIsMe = initialTurnPlayerId != null
        ? (initialTurnPlayerId == 'me')
        : random.nextBool();
    final playerIds = firstPlayerIsMe ? ['me', 'bot'] : ['bot', 'me'];

    List<String>? effectiveQuestionOrder = questionOrder;
    if (preselectedQuestionId != null) {
      final remainingIds = pool
          .map((q) => q.id)
          .where((id) => id != preselectedQuestionId)
          .toList()
        ..shuffle(random);
      effectiveQuestionOrder = [preselectedQuestionId, ...remainingIds];
    }
    _questionOrder = effectiveQuestionOrder;

    final engineResult = MatchEngine.start(
      config: _matchConfig,
      playerIds: playerIds,
      questions: pool,
      random: random,
      nowMs: now,
      questionOrder: effectiveQuestionOrder,
    );

    final providedConfig = _injectedBotConfig ?? ref.read(botConfigProvider);
    if (botConfig != null) {
      _activeBotConfig = botConfig;
    } else if (providedConfig != const BotConfig()) {
      _activeBotConfig = providedConfig;
    } else {
      _activeBotConfig = BotConfig.forPersona(
        BotPersona.values[random.nextInt(BotPersona.values.length)],
      );
    }

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
    if (_isPaused) return;
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

  @override
  void useGiveAnswer() {
    // Bot maçlarında cevap ver güçlendiricisi kullanılamaz.
  }

  /// Kullanıcının maçı terk etmesini sağlar.
  @override
  void leaveMatch() {
    final match = state.matchState;
    if (match == null ||
        match.phase == MatchPhase.matchFinished ||
        _pendingFinishedMatchState != null) {
      return;
    }

    _cancelAllTimers();
    _unregisterLifecycleObserver();
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

    // Maç ekranı skor kartı (soru/cevap alanı) skorunun gecikmeli güncellenmesi:
    // Tur sonu ekranı çıkana kadar maç ekranında eski skor gösterilir.
    // Yeni tura geçildiğinde (roundActive) veya ilk tur başında güncel skor gösterilir.
    final Map<String, int> updatedBoardScores;
    if (nextState.phase == MatchPhase.roundActive) {
      if (prevState?.phase == MatchPhase.roundEnded || state.boardScores == null) {
        updatedBoardScores = Map<String, int>.from(nextState.scores);
      } else {
        updatedBoardScores = state.boardScores!;
      }
    } else if (nextState.endedBy == 'forfeit') {
      updatedBoardScores = Map<String, int>.from(nextState.scores);
    } else {
      updatedBoardScores =
          state.boardScores ?? prevState?.scores ?? nextState.scores;
    }

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
        if (att.resultType == AttemptResultType.correct) {
          final matched = nextState.currentQuestion?.answers
              .where((a) => a.id == att.answerId)
              .firstOrNull;
          text = att.displayText ?? matched?.display ?? att.rawInput;
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
          isRepeated: att.resultType == AttemptResultType.repeated,
        );
      }).toList();
    }

    MatchFeedbackType? newFeedback;
    for (final event in events) {
      if (event is AnswerAccepted) {
        if (event.playerId == 'bot') {
          _roundBotSuccessCount++;
        }
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
      if (nextState.endedBy == 'draw_limit_reached') {
        _unregisterLifecycleObserver();
        _cancelAllTimers();
        state = state.copyWith(
          isVoided: true,
          isLoading: false,
        );
        return;
      }

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
        _cancelBotTimer();
        _cancelTransitionTimer();
        _tickTimer?.cancel();
        _tickTimer = null;

        _pendingFinishedMatchState = nextState;
        _pendingSummary = summary;
        _transitionDeadlineMs = now + matchFinishDelayMs;

        final boardDisplayState = nextState.copyWith(
          phase: MatchPhase.roundActive,
          turnPlayerId: null,
          deadlineMs: 0,
        );

        state = state.copyWith(
          matchState: boardDisplayState,
          boardScores: updatedBoardScores,
          remainingMs: 0,
          recentEvents: updatedEvents,
          eventCounter: updatedEventCounter,
          opponentName: opponentName ?? state.opponentName,
          opponentFrame: opponentName != null
              ? BotFrameResolver.resolve(opponentName)
              : state.opponentFrame,
          summary: summary,
          isLoading: false,
          acceptedAnswers: updatedAcceptedAnswers,
          roundAttempts: updatedRoundAttempts,
          lastFeedback: updatedFeedback,
          feedbackCounter: updatedFeedbackCounter,
          isFinalReveal: false,
          roundTransitionRemainingMs: matchFinishDelayMs,
          roundTransitionTotalMs: matchFinishDelayMs,
        );

        _transitionTimer = Timer(const Duration(milliseconds: matchFinishDelayMs), () {
          _commitFinishedMatch();
        });
        return;
      } else {
        // forfeit -> tur sonunu atla, hemen maç sonucu
        _unregisterLifecycleObserver();
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
    }

    String? nextQuestionText;
    String? nextQuestionId;
    if (nextState.phase == MatchPhase.roundEnded) {
      _pendingNextQuestion ??= MatchEngine.peekNextQuestion(
        state: nextState,
        questions: _loadedQuestions,
        random: random,
        questionOrder: _questionOrder,
      );
      if (_pendingNextQuestion != null) {
        nextQuestionText = _pendingNextQuestion!.text;
        nextQuestionId = _pendingNextQuestion!.id;
      }
    } else {
      _pendingNextQuestion = null;
    }

    state = state.copyWith(
      matchState: nextState,
      boardScores: updatedBoardScores,
      remainingMs: remaining,
      recentEvents: updatedEvents,
      eventCounter: updatedEventCounter,
      opponentName: opponentName ?? state.opponentName,
      opponentFrame: opponentName != null
          ? BotFrameResolver.resolve(opponentName)
          : state.opponentFrame,
      summary: summary,
      isLoading: false,
      acceptedAnswers: updatedAcceptedAnswers,
      roundAttempts: updatedRoundAttempts,
      lastFeedback: updatedFeedback,
      feedbackCounter: updatedFeedbackCounter,
      isFinalReveal: isFinal,
      roundTransitionRemainingMs: transitionRemaining,
      roundTransitionTotalMs: roundTransitionDelayMs,
      nextQuestionText: nextQuestionText,
      nextQuestionId: nextQuestionId,
      clearNextQuestion: nextQuestionText == null,
    );

    // Sıra bota YENİ geçtiyse bot zamanlayıcısını kur (state güncellendikten sonra)
    if (nextState.phase == MatchPhase.roundActive &&
        !wasBotActive &&
        nextState.turnPlayerId == 'bot') {
      _scheduleBotTurn(nextState, clock, random);
    }
  }

  void _scheduleBotTurn(MatchState match, GameClock clock, math.Random random) {
    _cancelBotTimer();

    final decision = BotPlayer.decide(
      question: match.currentQuestion!,
      usedAnswerIds: match.usedAnswerIds,
      random: random,
      config: _botConfig,
      roundBotSuccessCount: _roundBotSuccessCount,
      humanScore: match.scores['me'] ?? 0,
      botScore: match.scores['bot'] ?? 0,
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

    final currentMatch = state.matchState;
    if (currentMatch != null &&
        clock.nowMs() + action.delayMs >= currentMatch.deadlineMs) {
      // Eylemin süresi turun bitiş süresini aşıyorsa zamanlama yapılmaz; süre aşımı doğal olarak tamamlansın.
      return;
    }

    _botDeadlineMs = clock.nowMs() + action.delayMs;
    _botTimer = Timer(Duration(milliseconds: action.delayMs), () {
      _executeBotAction(clock, random);
    });
  }

  void _executeBotAction(GameClock clock, math.Random random) {
    _botTimer = null;
    _botDeadlineMs = null;
    final currentMatch = state.matchState;
    if (currentMatch == null ||
        currentMatch.phase != MatchPhase.roundActive ||
        currentMatch.turnPlayerId != 'bot') {
      return;
    }

    final now = clock.nowMs();
    if (now >= currentMatch.deadlineMs) {
      // Süre dolmuşsa eylem gönderilmez; motorun süre aşımı kontrolüne bırakılır.
      return;
    }

    if (_botActionIndex >= _pendingBotActions.length) return;
    final action = _pendingBotActions[_botActionIndex];

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
  }

  void _startNextRound(GameClock clock, math.Random random) {
    _roundBotSuccessCount = 0;
    final match = state.matchState;
    if (match == null || match.phase != MatchPhase.roundEnded) return;

    final now = clock.nowMs();
    final effectiveOrder = _pendingNextQuestion != null
        ? [_pendingNextQuestion!.id]
        : _questionOrder;
    _pendingNextQuestion = null;

    final res = MatchEngine.startNextRound(
      state: match,
      questions: _loadedQuestions,
      random: random,
      nowMs: now,
      questionOrder: effectiveOrder,
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
      if (_isPaused) return;
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
        if (now >= match.deadlineMs + match.config.graceMs) {
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
    _isDisposed = true;
    _cancelAllTimers();
    _unregisterLifecycleObserver();
  }

  void _commitFinishedMatch() {
    final finishedState = _pendingFinishedMatchState;
    final finishedSummary = _pendingSummary;
    _cancelAllTimers();
    _unregisterLifecycleObserver();

    if (finishedState != null) {
      state = state.copyWith(
        matchState: finishedState,
        boardScores: finishedState.scores,
        summary: finishedSummary,
        isFinalReveal: false,
        roundTransitionRemainingMs: 0,
      );
    }
  }

  void _cancelAllTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _cancelBotTimer();
    _cancelTransitionTimer();
    _frozenRemainingTurnMs = null;
    _pendingFinishedMatchState = null;
    _pendingSummary = null;
  }

  void _cancelBotTimer() {
    _botTimer?.cancel();
    _botTimer = null;
    _botDeadlineMs = null;
    _frozenRemainingBotDelayMs = null;
    _pendingBotActions = const [];
    _botActionIndex = 0;
  }

  void _cancelTransitionTimer() {
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _transitionDeadlineMs = null;
    _frozenRemainingTransitionMs = null;
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
        opponentFrame: BotFrameResolver.resolve(opponentName),
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

