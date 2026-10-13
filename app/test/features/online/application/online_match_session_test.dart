import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

class FakeManualClock implements GameClock {
  int currentMs;
  FakeManualClock([this.currentMs = 10000]);

  @override
  int nowMs() => currentMs;
}

class FakeHistoryRepo implements MatchHistoryRepository {
  final List<MatchHistoryEntry> entries = [];

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    entries.add(entry);
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return List.unmodifiable(entries);
  }
}

class FakeOnlineMatchClient extends OnlineMatchClient {
  final StreamController<OnlineMatchEvent> controller =
      StreamController<OnlineMatchEvent>.broadcast(sync: true);

  String? connectedMatchId;
  final List<String> submittedTexts = [];
  bool leaveCalled = false;
  bool closeCalled = false;

  @override
  Stream<OnlineMatchEvent> get events => controller.stream;

  @override
  Future<void> connect(String matchId) async {
    connectedMatchId = matchId;
    controller.add(const OnlineMatchConnected());
  }

  @override
  bool submit(String text) {
    submittedTexts.add(text);
    return true;
  }

  @override
  Future<void> leave() async {
    leaveCalled = true;
  }

  @override
  Future<void> close() async {
    closeCalled = true;
  }

  @override
  Future<void> dispose() async {
    await close();
    await controller.close();
  }

  void emit(OnlineMatchEvent event) {
    if (!controller.isClosed) {
      controller.add(event);
    }
  }
}

void main() {
  test(
    '1. state -> MatchUiState dönüşümü: tur, skor, soru, sıra, clockOffsetMs ile kalan süre ve deneme balonları',
    () async {
      final clock = FakeManualClock(10000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_1',
        opponentName: 'Elif',
      );

      expect(client.connectedMatchId, 'm_1');

      // Sunucu saati 50000, yerel alış saati 10000 -> clockOffsetMs = +40000
      // deadlineMs = 65000 (sunucu saatine göre 15 sn kaldı)
      final onlineState = OnlineMatchState(
        serverNowMs: 50000,
        receivedLocalMs: 10000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 2,
        myScore: 1,
        opponentScore: 0,
        question: const OnlineQuestion(
          id: 'q_sehir',
          text: 'A ile başlayan şehirler',
        ),
        turnIsMine: true,
        deadlineMs: 65000,
        myHintsLeft: 1,
        attempts: const [
          OnlineAttempt(mine: false, text: 'ankara', result: 'correct'),
          OnlineAttempt(
            mine: true,
            text: 'antaly',
            result: 'nearMiss',
            hintShown: true,
          ),
        ],
        opponentName: 'Elif',
        opponentConnected: true,
      );

      client.emit(OnlineMatchStateUpdate(onlineState));

      final uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isLoading, isFalse);
      expect(uiState.opponentName, 'Elif');
      expect(uiState.opponentConnected, isTrue);
      expect(uiState.isMyTurn, isTrue);
      expect(uiState.remainingMs, 15000);

      final matchState = uiState.matchState!;
      expect(matchState.phase, MatchPhase.roundActive);
      expect(matchState.decisiveRounds, 1); // Tur 2 -> decisiveRounds = 1
      expect(matchState.scores['me'], 1);
      expect(matchState.scores['bot'], 0);
      expect(matchState.currentQuestion?.id, 'q_sehir');
      expect(matchState.currentQuestion?.text, 'A ile başlayan şehirler');
      expect(matchState.remainingNearMisses['me'], 1);

      // Deneme balonları doğrudan dönüştürülür
      expect(uiState.displayAttempts.length, 2);
      expect(uiState.displayAttempts[0].playerId, 'bot');
      expect(uiState.displayAttempts[0].text, 'ankara');
      expect(uiState.displayAttempts[0].isCorrect, isTrue);

      expect(uiState.displayAttempts[1].playerId, 'me');
      expect(uiState.displayAttempts[1].text, 'antaly');
      expect(uiState.displayAttempts[1].isCorrect, isFalse);
      expect(uiState.displayAttempts[1].isClose, isTrue);

      // submit çağrısı istemciye iletilir
      session.submit('  Adana  ');
      expect(client.submittedTexts, ['Adana']);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '2. feedback olayları: wrong, alreadySaid, nearMiss feedbackCounter artırır; ignored yok sayılır',
    () async {
      final clock = FakeManualClock(10000);
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_2', opponentName: 'Can');

      client.emit(const OnlineMatchFeedback(kind: 'wrong'));
      var uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.lastFeedback, MatchFeedbackType.wrong);
      expect(uiState.feedbackCounter, 1);

      client.emit(const OnlineMatchFeedback(kind: 'alreadySaid'));
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.lastFeedback, MatchFeedbackType.alreadySaid);
      expect(uiState.feedbackCounter, 2);

      client.emit(const OnlineMatchFeedback(kind: 'nearMiss'));
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.lastFeedback, MatchFeedbackType.nearMiss);
      expect(uiState.feedbackCounter, 3);

      // ignored (cooldown vb.) -> sayaç ve geri bildirim değişmez, hata gösterilmez
      client.emit(
        const OnlineMatchFeedback(kind: 'ignored', reason: 'cooldown'),
      );
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.lastFeedback, MatchFeedbackType.nearMiss);
      expect(uiState.feedbackCounter, 3);
      expect(uiState.errorMessage, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '3. Tur sonu (roundEnded): lastRound ve nextRoundAtMs ile geri sayım hesaplanır',
    () async {
      final clock = FakeManualClock(20000);
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_3', opponentName: 'Burak');

      // serverNowMs: 80000, receivedLocalMs: 20000 -> offset = +60000
      // nextRoundAtMs: 83000 -> 3000 ms geçiş süresi
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 80000,
            receivedLocalMs: 20000,
            phase: OnlineMatchPhase.roundEnded,
            roundNumber: 1,
            myScore: 1,
            opponentScore: 0,
            question: OnlineQuestion(id: 'q1', text: 'Soru 1'),
            turnIsMine: false,
            deadlineMs: 0,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Burak',
            opponentConnected: true,
            lastRound: OnlineLastRound(
              winnerIsMe: true,
              draw: false,
              reason: 'timeout',
            ),
            nextRoundAtMs: 83000,
          ),
        ),
      );

      final uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isRoundEnded, isTrue);
      expect(uiState.roundTransitionTotalMs, 3000);
      expect(uiState.roundTransitionRemainingMs, 3000);
      expect(uiState.matchState?.roundHistory.last.winnerId, 'me');
      expect(
        uiState.matchState?.roundHistory.last.reason,
        RoundEndReason.timeout,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '4. final mesajı -> MatchHistoryRepository tek kayıt (botlaOynandi: false), soru metni önbelleği ve terk durumu',
    () async {
      final clock = FakeManualClock(30000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_final_1', opponentName: 'Selin');

      // Maç içi state ile soru metnini önbellekle
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 30000,
            receivedLocalMs: 30000,
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 1,
            myScore: 0,
            opponentScore: 0,
            question: OnlineQuestion(
              id: 'q_cached_1',
              text: 'Başkent olan şehirler',
            ),
            turnIsMine: true,
            deadlineMs: 45000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Selin',
            opponentConnected: true,
          ),
        ),
      );

      final finalMsg = FinalServerMessage(
        rounds: const [
          OnlineRoundRecord(
            questionId: 'q_cached_1',
            attempts: [
              OnlineAttempt(mine: true, text: 'ankar', result: 'nearMiss', hintShown: true),
              OnlineAttempt(mine: true, text: 'ankara', result: 'correct'),
              OnlineAttempt(mine: false, text: 'izmir', result: 'wrong'),
            ],
            winnerIsMe: true,
            reason: 'timeout',
          ),
          OnlineRoundRecord(
            questionId: 'q_uncached_2',
            attempts: [
              OnlineAttempt(mine: false, text: 'bursa', result: 'wrong'),
            ],
            winnerIsMe: true,
            reason: 'forfeit',
          ),
        ],
        myScore: 2,
        opponentScore: 0,
        winnerIsMe: true,
        endedBy: 'forfeit',
      );

      // final mesajını iki kez göndersek bile geçmişe BİR KEZ kaydedilmeli
      client.emit(OnlineMatchFinal(finalMsg));
      client.emit(OnlineMatchFinal(finalMsg));
      await Future<void>.delayed(Duration.zero);

      expect(repo.entries.length, 1);
      final saved = repo.entries.first;
      expect(saved.id, 'm_final_1');
      expect(saved.opponentName, 'Selin');
      expect(saved.botlaOynandi, isFalse);
      expect(saved.result, MatchResult.win);
      expect(saved.endType, MatchEndType.forfeit);
      expect(saved.forfeitedPlayerId, 'bot');
      expect(saved.myScore, 2);
      expect(saved.opponentScore, 0);

      // Önbellekteki soru metni ve önbellekte olmayan için varsayılan metin
      expect(saved.roundQuestionTexts, [
        'Başkent olan şehirler',
        AppStrings.defaultQuestionText,
      ]);

      // Yakın deneme dahil tüm denemeler korunmuş olmalı
      expect(saved.roundRecords.length, 2);
      final r1 = saved.roundRecords[0];
      expect(r1.attempts.length, 3);
      expect(r1.attempts[0].rawInput, 'ankar');
      expect(r1.attempts[0].resultType, AttemptResultType.nearMiss);
      expect(r1.attempts[0].isClose, isTrue);
      expect(r1.attempts[0].hintShown, isTrue);
      expect(r1.attempts[1].resultType, AttemptResultType.correct);
      expect(r1.attempts[2].playerId, 'bot');

      final r2 = saved.roundRecords[1];
      expect(r2.reason, RoundEndReason.forfeit);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '5. leaveMatch: 3 sn içinde final gelmezse yerel olarak "terk ettin" sonucu üretip geçmişe kaydeder',
    () async {
      final clock = FakeManualClock(40000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();
      void Function()? capturedTimeoutCallback;

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
          onlineMatchSessionProvider.overrideWith(
            () => OnlineMatchSession(
              clock: clock,
              timerFactory: (duration, callback) {
                capturedTimeoutCallback = callback;
                return Timer(const Duration(days: 1), () {});
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_leave_1', opponentName: 'Mert');

      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 40000,
            receivedLocalMs: 40000,
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 1,
            myScore: 0,
            opponentScore: 1,
            question: OnlineQuestion(id: 'q_1', text: 'Meyveler'),
            turnIsMine: true,
            deadlineMs: 55000,
            myHintsLeft: 1,
            attempts: [
              OnlineAttempt(mine: true, text: 'elma', result: 'correct'),
            ],
            opponentName: 'Mert',
            opponentConnected: true,
          ),
        ),
      );

      session.leaveMatch();
      expect(client.leaveCalled, isTrue);
      expect(repo.entries, isEmpty);
      expect(capturedTimeoutCallback, isNotNull);

      // 3 sn doldu ve sunucudan final gelmedi -> yerel forfeit üretilir
      capturedTimeoutCallback!();
      await Future<void>.delayed(Duration.zero);

      expect(repo.entries.length, 1);
      final entry = repo.entries.first;
      expect(entry.id, 'm_leave_1');
      expect(entry.botlaOynandi, isFalse);
      expect(entry.result, MatchResult.lose);
      expect(entry.endType, MatchEndType.forfeit);
      expect(entry.forfeitedPlayerId, 'me');
      expect(entry.roundQuestionTexts, ['Meyveler']);
      expect(entry.roundRecords.first.reason, RoundEndReason.forfeit);

      final uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isMatchFinished, isTrue);
      expect(uiState.matchState?.endedBy, 'forfeit');
      expect(uiState.matchState?.winnerId, 'bot');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '6. voided (opponent_absent) gelince hata göstermeden eşleşme akışına döner ve botlu maça düşer',
    (tester) async {
      final clock = FakeManualClock(50000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            matchHistoryRepositoryProvider.overrideWithValue(repo),
            onlineMatchClientFactoryProvider.overrideWithValue(() => client),
          ],
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MatchScreen)),
      );
      container
          .read(activeMatchSessionModeProvider.notifier)
          .setMode(MatchSessionMode.online);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(matchId: 'm_void', opponentName: 'Ayşe');
      await tester.pump();

      // Sunucu voided gönderir
      client.emit(const OnlineMatchVoided(reason: 'opponent_absent'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // MatchmakingScreen (forceBotFallback: true) açılmış olmalı ve yenilgi kaydedilmemeli
      expect(find.byType(MatchmakingScreen), findsOneWidget);
      expect(repo.entries, isEmpty);

      // 800 ms sonra botlu maça geçer
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MatchScreen), findsOneWidget);
      expect(
        container.read(activeMatchSessionModeProvider),
        MatchSessionMode.bot,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '7. Kalıcı kopma (DisconnectReason.permanent / replaced) yenilgi yazmaz, ana ekrana döner ve bilgi mesajı gösterir',
    (tester) async {
      final clock = FakeManualClock(60000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            matchHistoryRepositoryProvider.overrideWithValue(repo),
            onlineMatchClientFactoryProvider.overrideWithValue(() => client),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => const MatchScreen(),
                      ),
                    );
                  },
                  child: const Text('StartOnline'),
                ),
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.text('StartOnline')),
      );
      container
          .read(activeMatchSessionModeProvider.notifier)
          .setMode(MatchSessionMode.online);
      await container
          .read(onlineMatchSessionProvider.notifier)
          .startOnlineMatch(matchId: 'm_disc', opponentName: 'Emre');

      await tester.tap(find.text('StartOnline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MatchScreen), findsOneWidget);

      // Kalıcı kopma olayı
      client.emit(
        const OnlineMatchDisconnected(DisconnectReason.permanent),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Ana ekrana dönülmüş, bilgi mesajı gösterilmiş ve geçmişe yenilgi YAZILMAMIŞ olmalı
      expect(find.byType(MatchScreen), findsNothing);
      expect(find.text('StartOnline'), findsOneWidget);
      expect(find.text(AppStrings.connectionLostNotice), findsOneWidget);
      expect(repo.entries, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

