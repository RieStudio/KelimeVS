import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../game/application/match_controller.dart';
import '../../game/application/match_history_provider.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/application/match_ui_state.dart';
import '../../game/domain/attempt_text_sanitizer.dart';
import '../../game/domain/history/match_history_entry.dart';
import '../../game/domain/match/match_config.dart';
import '../../game/domain/match/match_events.dart';
import '../../game/domain/match/match_state.dart';
import '../../game/domain/models.dart';
import '../../game/domain/text_filter.dart';
import '../data/online_match_client.dart';
import '../domain/models/online_match_state.dart';
import '../domain/models/online_messages.dart';

/// Sunucudan gelen `final` mesajını yerel [MatchHistoryEntry] ve [RoundRecord]
/// modellerine dönüştüren yardımcı sınıf.
abstract final class OnlineMatchHistoryMapper {
  static RoundEndReason mapRoundReason(String rawReason) {
    switch (rawReason) {
      case 'exhausted':
      case 'allAnswersFound':
        return RoundEndReason.exhausted;
      case 'forfeit':
        return RoundEndReason.forfeit;
      case 'timeout':
      default:
        return RoundEndReason.timeout;
    }
  }

  static AttemptResultType mapAttemptResultType(String rawResult) {
    switch (rawResult) {
      case 'correct':
        return AttemptResultType.correct;
      case 'repeated':
        return AttemptResultType.repeated;
      case 'nearMiss':
        return AttemptResultType.nearMiss;
      case 'timeout':
        return AttemptResultType.timeout;
      case 'wrong':
      default:
        return AttemptResultType.wrong;
    }
  }

  static TurnAttempt mapAttempt(OnlineAttempt attempt) {
    final resultType = mapAttemptResultType(attempt.result);
    return TurnAttempt(
      playerId: attempt.mine ? 'me' : 'bot',
      rawInput: attempt.text,
      resultType: resultType,
      answerId: null,
      nowMs: 0,
      isClose: attempt.result == 'nearMiss' || attempt.hintShown,
      hintShown: attempt.hintShown,
    );
  }

  static RoundRecord mapRoundRecord(OnlineRoundRecord round, int roundIndex) {
    final attempts = round.attempts.map(mapAttempt).toList();
    final starterPlayerId = attempts.isNotEmpty
        ? attempts.first.playerId
        : (roundIndex.isEven ? 'me' : 'bot');
    final String? winnerId;
    if (round.winnerIsMe == null) {
      winnerId = null;
    } else {
      winnerId = round.winnerIsMe! ? 'me' : 'bot';
    }

    return RoundRecord(
      questionId: round.questionId,
      starterPlayerId: starterPlayerId,
      attempts: attempts,
      winnerId: winnerId,
      reason: mapRoundReason(round.reason),
    );
  }

  static MatchHistoryEntry toHistoryEntry({
    required FinalServerMessage finalMessage,
    required String matchId,
    required String opponentName,
    required int finishedAtMs,
    required Map<String, String> questionTextsById,
  }) {
    final roundRecords = <RoundRecord>[];
    final roundQuestionTexts = <String>[];

    for (var i = 0; i < finalMessage.rounds.length; i++) {
      final onlineRound = finalMessage.rounds[i];
      roundRecords.add(mapRoundRecord(onlineRound, i));
      roundQuestionTexts.add(
        questionTextsById[onlineRound.questionId] ??
            AppStrings.defaultQuestionText,
      );
    }

    final isWinner = finalMessage.winnerIsMe;
    final isForfeit = finalMessage.endedBy == 'forfeit';
    final forfeitedPlayerId = isForfeit ? (isWinner ? 'bot' : 'me') : null;

    return MatchHistoryEntry(
      id: matchId,
      opponentName:
          opponentName.isNotEmpty ? opponentName : AppStrings.opponent,
      finishedAtMs: finishedAtMs,
      myScore: finalMessage.myScore,
      opponentScore: finalMessage.opponentScore,
      result: isWinner ? MatchResult.win : MatchResult.lose,
      endType: isForfeit ? MatchEndType.forfeit : MatchEndType.normal,
      forfeitedPlayerId: forfeitedPlayerId,
      roundRecords: roundRecords,
      roundQuestionTexts: roundQuestionTexts,
      botlaOynandi: false,
    );
  }
}

/// Çevrimiçi sunucu maçını yöneten ve [MatchUiState] üreten oturum sınıfı.
class OnlineMatchSession extends Notifier<MatchUiState>
    with WidgetsBindingObserver
    implements MatchSession {
  final GameClock? _injectedClock;
  final math.Random? _injectedRandom;
  final TextFilter? _injectedTextFilter;
  final Duration leaveTimeoutDuration;
  final Timer Function(Duration duration, void Function() callback)?
      _injectedTimerFactory;

  OnlineMatchSession({
    GameClock? clock,
    math.Random? random,
    TextFilter? textFilter,
    this.leaveTimeoutDuration = const Duration(seconds: 3),
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  })  : _injectedClock = clock,
        _injectedRandom = random,
        _injectedTextFilter = textFilter,
        _injectedTimerFactory = timerFactory;

  OnlineMatchClient? _client;
  StreamSubscription<OnlineMatchEvent>? _subscription;
  Timer? _tickTimer;
  Timer? _leaveTimeoutTimer;

  OnlineMatchState? _lastOnlineState;
  String? _currentMatchId;
  bool _isMatchSaved = false;
  bool _isLeaving = false;
  bool _isObserverRegistered = false;

  /// Maç boyunca `state` mesajlarından gelen soru metinlerinin önbelleği (`questionId -> text`).
  final Map<String, String> _questionTextCache = {};

  /// Sunucudan `final` gelmeden yerel terk zaman aşımı olursa kullanılacak tamamlanmış turlar.
  final List<OnlineRoundRecord> _observedRounds = [];
  int _lastObservedRoundCount = 0;

  @override
  MatchUiState build() {
    ref.onDispose(() {
      dispose();
    });
    return const MatchUiState();
  }

  GameClock get _clock => _injectedClock ?? ref.read(gameClockProvider);
  math.Random get _random => _injectedRandom ?? ref.read(randomProvider);
  TextFilter get _textFilter =>
      _injectedTextFilter ?? ref.read(textFilterProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      handleAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      handleAppResumed();
    }
  }

  /// Yaşam döngüsü: uygulama arka plana geçtiğinde (paused/inactive) maçı terk etmez.
  void handleAppPaused() {
    _client?.handleAppPaused();
  }

  /// Yaşam döngüsü: uygulama öne geldiğinde (resumed) sync gönderir veya derhal bağlanır.
  void handleAppResumed() {
    _client?.handleAppResumed();
  }

  /// Yeni bir çevrimiçi maç oturumu başlatır ve [matchId] odasına bağlanır.
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    OnlineMatchClient? client,
  }) async {
    _cleanupSession();

    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }

    _currentMatchId = matchId;
    _isMatchSaved = false;
    _isLeaving = false;
    _lastOnlineState = null;
    _questionTextCache.clear();
    _observedRounds.clear();
    _lastObservedRoundCount = 0;

    state = MatchUiState(
      isLoading: true,
      opponentName: opponentName,
      connectionStatus: ConnectionStatus.connected,
      opponentConnected: true,
      isVoided: false,
      isDisconnectedPermanent: false,
      isDisconnectedReplaced: false,
    );

    final activeClient =
        client ?? ref.read(onlineMatchClientFactoryProvider)();
    _client = activeClient;

    _subscription = activeClient.events.listen(_handleEvent);
    _startTickTimer();

    await activeClient.connect(matchId);
  }

  void _handleEvent(OnlineMatchEvent event) {
    if (event is OnlineMatchReconnecting) {
      state = state.copyWith(connectionStatus: ConnectionStatus.reconnecting);
    } else if (event is OnlineMatchConnected) {
      state = state.copyWith(connectionStatus: ConnectionStatus.connected);
    } else if (event is OnlineMatchStateUpdate) {
      _handleStateUpdate(event.state);
    } else if (event is OnlineMatchFeedback) {
      _handleFeedback(event);
    } else if (event is OnlineMatchFinal) {
      _handleFinal(event.result);
    } else if (event is OnlineMatchVoided) {
      _handleVoided();
    } else if (event is OnlineMatchDisconnected) {
      _handleDisconnected(event.reason);
    }
  }

  void _handleStateUpdate(OnlineMatchState onlineState) {
    _lastOnlineState = onlineState;

    if (onlineState.question != null &&
        onlineState.question!.id.isNotEmpty &&
        onlineState.question!.text.isNotEmpty) {
      _questionTextCache[onlineState.question!.id] = onlineState.question!.text;
    }

    // Tur sonlarında yerel terk yedeklemesi için tur bilgisini sakla
    if ((onlineState.phase == OnlineMatchPhase.roundEnded ||
            onlineState.phase == OnlineMatchPhase.matchFinished) &&
        onlineState.lastRound != null &&
        onlineState.roundNumber > _lastObservedRoundCount) {
      _lastObservedRoundCount = onlineState.roundNumber;
      _observedRounds.add(
        OnlineRoundRecord(
          questionId: onlineState.question?.id ?? '',
          attempts: onlineState.attempts,
          winnerIsMe: onlineState.lastRound!.draw
              ? null
              : onlineState.lastRound!.winnerIsMe,
          reason: onlineState.lastRound!.reason,
        ),
      );
    }

    final nowLocalMs = _clock.nowMs();
    final MatchPhase mappedPhase;
    switch (onlineState.phase) {
      case OnlineMatchPhase.roundActive:
        mappedPhase = MatchPhase.roundActive;
      case OnlineMatchPhase.roundEnded:
        mappedPhase = MatchPhase.roundEnded;
      case OnlineMatchPhase.matchFinished:
        mappedPhase = MatchPhase.matchFinished;
      case OnlineMatchPhase.unknown:
        mappedPhase = state.matchState?.phase ?? MatchPhase.roundActive;
    }

    final isDraw = onlineState.lastRound?.draw ?? false;
    final int decisiveRounds;
    if (mappedPhase == MatchPhase.roundActive) {
      decisiveRounds = math.max(0, onlineState.roundNumber - 1);
    } else if (isDraw) {
      decisiveRounds = onlineState.myScore + onlineState.opponentScore;
    } else {
      decisiveRounds = math.max(
        onlineState.roundNumber,
        onlineState.myScore + onlineState.opponentScore,
      );
    }

    final Question? currentQuestion = onlineState.question != null
        ? Question(
            id: onlineState.question!.id,
            categoryId: '',
            text: onlineState.question!.text,
            answers: const [],
          )
        : state.matchState?.currentQuestion;

    // Sunucu visibleAttempts kurallarını zaten uyguladığı için yeniden filtreleme yapılmaz;
    // yalnızca görüntü metin temizliği uygulanır.
    final roundAttempts = onlineState.attempts.map((a) {
      var cleanText = AttemptTextSanitizer.sanitize(a.text);
      if (!a.mine) {
        cleanText = _textFilter.apply(cleanText);
      }
      return RoundAttemptUiModel(
        playerId: a.mine ? 'me' : 'bot',
        text: cleanText,
        isCorrect: a.result == 'correct',
        isClose: a.result == 'nearMiss' || a.hintShown,
      );
    }).toList();

    final acceptedAnswers = onlineState.attempts
        .where((a) => a.result == 'correct')
        .map((a) {
          var cleanText = AttemptTextSanitizer.sanitize(a.text);
          if (!a.mine) {
            cleanText = _textFilter.apply(cleanText);
          }
          return AcceptedAnswerUiModel(
            playerId: a.mine ? 'me' : 'bot',
            display: cleanText,
          );
        })
        .toList();

    final List<RoundRecord> roundHistory;
    if (onlineState.lastRound != null) {
      final lr = onlineState.lastRound!;
      roundHistory = [
        RoundRecord(
          questionId: onlineState.question?.id ?? '',
          starterPlayerId: 'me',
          attempts: onlineState.attempts
              .map(OnlineMatchHistoryMapper.mapAttempt)
              .toList(),
          winnerId: lr.draw ? null : (lr.winnerIsMe ? 'me' : 'bot'),
          reason: OnlineMatchHistoryMapper.mapRoundReason(lr.reason),
        ),
      ];
    } else {
      roundHistory = state.matchState?.roundHistory ?? const [];
    }

    final String? winnerId;
    if (mappedPhase == MatchPhase.matchFinished) {
      if (onlineState.winnerIsMe != null) {
        winnerId = onlineState.winnerIsMe! ? 'me' : 'bot';
      } else {
        winnerId = state.matchState?.winnerId ??
            (onlineState.myScore >= onlineState.opponentScore ? 'me' : 'bot');
      }
    } else {
      winnerId = null;
    }

    final mappedMatchState = MatchState(
      config: const MatchConfig(),
      playerIds: const ['me', 'bot'],
      scores: {
        'me': onlineState.myScore,
        'bot': onlineState.opponentScore,
      },
      decisiveRounds: decisiveRounds,
      totalRoundsPlayed: decisiveRounds,
      phase: mappedPhase,
      currentQuestion: currentQuestion,
      usedAnswerIds: const {},
      turnPlayerId: mappedPhase == MatchPhase.roundActive
          ? (onlineState.turnIsMine ? 'me' : 'bot')
          : null,
      deadlineMs: onlineState.deadlineMs,
      remainingNearMisses: {
        'me': onlineState.myHintsLeft,
        'bot': 0,
      },
      usedQuestionIds: const {},
      currentRoundAttempts: const [],
      roundHistory: roundHistory,
      winnerId: winnerId,
      endedBy: onlineState.endedBy ?? state.matchState?.endedBy,
    );

    final int remainingMs = mappedPhase == MatchPhase.roundActive
        ? onlineState.kalanSureMs(nowLocalMs)
        : 0;

    int transitionRemainingMs = 0;
    int transitionTotalMs = state.roundTransitionTotalMs;
    if (mappedPhase == MatchPhase.roundEnded &&
        onlineState.nextRoundAtMs != null) {
      final estimatedServerNow = nowLocalMs + onlineState.clockOffsetMs;
      transitionRemainingMs =
          math.max(0, onlineState.nextRoundAtMs! - estimatedServerNow);
      final totalFromServer =
          onlineState.nextRoundAtMs! - onlineState.serverNowMs;
      if (totalFromServer > 0) {
        transitionTotalMs = totalFromServer;
      }
    }

    final updatedOpponentName = onlineState.opponentName.isNotEmpty
        ? onlineState.opponentName
        : state.opponentName;

    state = state.copyWith(
      matchState: mappedMatchState,
      remainingMs: remainingMs,
      opponentName: updatedOpponentName,
      connectionStatus: ConnectionStatus.connected,
      opponentConnected: onlineState.opponentConnected,
      isLoading: false,
      acceptedAnswers: acceptedAnswers,
      roundAttempts: roundAttempts,
      isFinalReveal: false,
      roundTransitionRemainingMs: transitionRemainingMs,
      roundTransitionTotalMs: transitionTotalMs,
    );
  }

  void _handleFeedback(OnlineMatchFeedback feedback) {
    final MatchFeedbackType? feedbackType;
    switch (feedback.kind) {
      case 'wrong':
        feedbackType = MatchFeedbackType.wrong;
      case 'alreadySaid':
        feedbackType = MatchFeedbackType.alreadySaid;
      case 'nearMiss':
        feedbackType = MatchFeedbackType.nearMiss;
      case 'ignored':
      default:
        // Cooldown vb. ignored mesajlarında kullanıcıya hata gösterilmez.
        return;
    }

    state = state.copyWith(
      lastFeedback: feedbackType,
      feedbackCounter: state.feedbackCounter + 1,
    );
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

  void _handleFinal(FinalServerMessage finalMsg) {
    _leaveTimeoutTimer?.cancel();
    _leaveTimeoutTimer = null;
    _isLeaving = false;
    _cancelTickTimer();

    final finishedAtMs = math.max(
      _clock.nowMs(),
      DateTime.now().millisecondsSinceEpoch,
    );
    final matchId =
        _currentMatchId ?? 'online_${finishedAtMs}_${_random.nextInt(100000)}';
    final entry = OnlineMatchHistoryMapper.toHistoryEntry(
      finalMessage: finalMsg,
      matchId: matchId,
      opponentName: state.opponentName,
      finishedAtMs: finishedAtMs,
      questionTextsById: _questionTextCache,
    );

    final winnerId = finalMsg.winnerIsMe ? 'me' : 'bot';
    final scores = {
      'me': finalMsg.myScore,
      'bot': finalMsg.opponentScore,
    };

    final prevMatchState = state.matchState;
    final finishedMatchState = MatchState(
      config: prevMatchState?.config ?? const MatchConfig(),
      playerIds: const ['me', 'bot'],
      scores: scores,
      decisiveRounds: finalMsg.myScore + finalMsg.opponentScore,
      totalRoundsPlayed: entry.roundRecords.length,
      phase: MatchPhase.matchFinished,
      currentQuestion: prevMatchState?.currentQuestion,
      usedAnswerIds: const {},
      turnPlayerId: null,
      deadlineMs: 0,
      remainingNearMisses:
          prevMatchState?.remainingNearMisses ?? const {'me': 0, 'bot': 0},
      usedQuestionIds: const {},
      currentRoundAttempts: const [],
      roundHistory: entry.roundRecords,
      winnerId: winnerId,
      endedBy: finalMsg.endedBy,
    );

    state = state.copyWith(
      matchState: finishedMatchState,
      remainingMs: 0,
      isLoading: false,
      isFinalReveal: false,
      roundTransitionRemainingMs: 0,
      lastSavedMatch: entry,
      summary: MatchSummary(
        scores: scores,
        winnerId: winnerId,
        roundHistory: entry.roundRecords,
      ),
    );

    if (!_isMatchSaved) {
      _isMatchSaved = true;
      unawaited(_persistHistoryEntry(entry));
    }
  }

  Future<void> _persistHistoryEntry(MatchHistoryEntry entry) async {
    try {
      final isForfeit = entry.endType == MatchEndType.forfeit;
      if (kDebugMode) {
        debugPrint(
          '[history] kayıt istendi (kaynak: ${isForfeit ? 'forfeit' : 'online'})',
        );
      }
      final repo = ref.read(matchHistoryRepositoryProvider);
      await repo.add(entry);
      ref.invalidate(matchHistoryProvider);
      if (kDebugMode) {
        debugPrint('[history] liste yenilendi');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[history] yazma HATASI: ${e.runtimeType}: ${_shortErrorMessage(e)}',
        );
      }
    }
  }

  void _handleVoided() {
    _cancelAllTimers();
    final client = _client;
    _client = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (client != null) {
      unawaited(client.close());
    }

    state = state.copyWith(
      isLoading: false,
      isVoided: true,
    );
  }

  void _handleDisconnected(DisconnectReason reason) {
    // Maç zaten tamamlandıysa veya terk sonucu bekleniyorsa kopma olayını yok say
    if (_isMatchSaved ||
        _isLeaving ||
        state.matchState?.phase == MatchPhase.matchFinished ||
        state.isVoided) {
      return;
    }

    if (reason == DisconnectReason.permanent ||
        reason == DisconnectReason.replaced) {
      // TODO: 4.5d'de ayrıntılı bağlantı kopma deneyimi
      _cancelAllTimers();
      final client = _client;
      _client = null;
      unawaited(_subscription?.cancel());
      _subscription = null;
      if (client != null) {
        unawaited(client.close());
      }

      final isReplaced = reason == DisconnectReason.replaced;

      // Yenilgi yazılmaz; bağlantı koptu durumuyla sonlandırılır
      state = state.copyWith(
        isLoading: false,
        connectionStatus: ConnectionStatus.permanentDisconnected,
        isDisconnectedPermanent: true,
        isDisconnectedReplaced: isReplaced,
      );
    }
  }

  @override
  void submit(String text) {
    final sanitized = AttemptTextSanitizer.sanitize(text);
    if (sanitized.isEmpty) return;

    final match = state.matchState;
    if (match == null || match.phase != MatchPhase.roundActive) return;
    if (match.turnPlayerId != 'me') return;

    _client?.submit(sanitized);
  }

  @override
  void leaveMatch() {
    if (_isLeaving ||
        _isMatchSaved ||
        state.matchState?.phase == MatchPhase.matchFinished) {
      return;
    }

    _isLeaving = true;
    unawaited(_client?.leave());

    _leaveTimeoutTimer?.cancel();
    void onLeaveTimeout() {
      if (_isMatchSaved) {
        return;
      }
      _synthesizeLocalForfeit();
    }

    if (_injectedTimerFactory != null) {
      _leaveTimeoutTimer =
          _injectedTimerFactory(leaveTimeoutDuration, onLeaveTimeout);
    } else {
      _leaveTimeoutTimer = Timer(leaveTimeoutDuration, onLeaveTimeout);
    }
  }

  void _synthesizeLocalForfeit() {
    _leaveTimeoutTimer?.cancel();
    _leaveTimeoutTimer = null;
    _isLeaving = false;
    _cancelTickTimer();

    final lastOnline = _lastOnlineState;
    final rounds = List<OnlineRoundRecord>.from(_observedRounds);
    if (lastOnline != null &&
        lastOnline.phase == OnlineMatchPhase.roundActive &&
        lastOnline.question != null) {
      rounds.add(
        OnlineRoundRecord(
          questionId: lastOnline.question!.id,
          attempts: lastOnline.attempts,
          winnerIsMe: false,
          reason: 'forfeit',
        ),
      );
    }

    final myScore =
        state.matchState?.scores['me'] ?? lastOnline?.myScore ?? 0;
    final opponentScore =
        state.matchState?.scores['bot'] ?? lastOnline?.opponentScore ?? 0;

    final syntheticFinal = FinalServerMessage(
      rounds: rounds,
      myScore: myScore,
      opponentScore: opponentScore,
      winnerIsMe: false,
      endedBy: 'forfeit',
    );

    _handleFinal(syntheticFinal);

    final client = _client;
    _client = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (client != null) {
      unawaited(client.close());
    }
  }

  void _startTickTimer() {
    _cancelTickTimer();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final onlineState = _lastOnlineState;
      final match = state.matchState;
      if (onlineState == null || match == null) return;

      final nowLocalMs = _clock.nowMs();

      // Yalnızca görüntü amaçlı geri sayım güncellemesi; zaman aşımına sunucu karar verir.
      if (match.phase == MatchPhase.roundActive) {
        final remaining = onlineState.kalanSureMs(nowLocalMs);
        if (remaining != state.remainingMs) {
          state = state.copyWith(remainingMs: remaining);
        }
      } else if (match.phase == MatchPhase.roundEnded &&
          onlineState.nextRoundAtMs != null) {
        final estimatedServerNow = nowLocalMs + onlineState.clockOffsetMs;
        final transitionRemaining =
            math.max(0, onlineState.nextRoundAtMs! - estimatedServerNow);
        if (transitionRemaining != state.roundTransitionRemainingMs) {
          state = state.copyWith(
            roundTransitionRemainingMs: transitionRemaining,
          );
        }
      }
    });
  }

  void _cancelTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  void _cancelAllTimers() {
    _cancelTickTimer();
    _leaveTimeoutTimer?.cancel();
    _leaveTimeoutTimer = null;
  }

  void _cleanupSession() {
    _cancelAllTimers();
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(client.close());
    }
  }

  @override
  void dispose() {
    _cleanupSession();
  }
}

