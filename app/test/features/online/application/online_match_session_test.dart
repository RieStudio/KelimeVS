import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
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
    final idx = entries.indexWhere((e) =>
        e.id == entry.id ||
        (entry.matchId != null &&
            e.matchId != null &&
            e.matchId == entry.matchId));
    if (idx != -1) {
      entries[idx] = entry;
    } else {
      entries.insert(0, entry);
    }
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return List.unmodifiable(entries);
  }

  @override
  Future<void> clear() async {
    entries.clear();
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

  bool pausedCalled = false;
  bool resumedCalled = false;

  @override
  void handleAppPaused() {
    pausedCalled = true;
  }

  @override
  Future<void> handleAppResumed() async {
    resumedCalled = true;
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
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });
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
    '2b. Aktif turda gelen repeated denemeler displayAttempts içinde filtrelenir; feedback: alreadySaid uyarısı çalışır',
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
      await session.startOnlineMatch(matchId: 'm_rep', opponentName: 'Zeynep');

      // Aktif tur state'i: bir correct, bir wrong, bir repeated attempt içeriyor (eski sunucu ya da senkronizasyon)
      final stateWithRepeated = OnlineMatchState(
        serverNowMs: 50000,
        receivedLocalMs: 10000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 0,
        opponentScore: 0,
        question: const OnlineQuestion(id: 'q1', text: 'Meyveler'),
        turnIsMine: true,
        deadlineMs: 65000,
        myHintsLeft: 1,
        attempts: const [
          OnlineAttempt(mine: true, text: 'elma', result: 'correct'),
          OnlineAttempt(mine: false, text: 'yanlis', result: 'wrong'),
          OnlineAttempt(mine: true, text: 'elma', result: 'repeated'),
        ],
        opponentName: 'Zeynep',
        opponentConnected: true,
      );

      client.emit(OnlineMatchStateUpdate(stateWithRepeated));

      var uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isRoundActive, isTrue);

      // Doğrulama: displayAttempts içinde repeated elenir; correct ve wrong kalır
      expect(uiState.displayAttempts.length, 2);
      expect(uiState.displayAttempts[0].text, 'elma');
      expect(uiState.displayAttempts[0].isCorrect, isTrue);
      expect(uiState.displayAttempts[1].text, 'yanlis');
      expect(uiState.displayAttempts[1].isCorrect, isFalse);

      // Doğrulama: alreadySaid feedback'i kutu uyarısı için feedbackCounter artırır
      client.emit(const OnlineMatchFeedback(kind: 'alreadySaid'));
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.lastFeedback, MatchFeedbackType.alreadySaid);
      expect(uiState.feedbackCounter, 1);
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

      // Ana ekrana dönülmüş, bilgi mesajı gösterilmiş ve geçmişe baglantiKoptu yenilgisi yazılmış olmalı (GDD 3.2)
      expect(find.byType(MatchScreen), findsNothing);
      expect(find.text('StartOnline'), findsOneWidget);
      expect(find.text(AppStrings.connectionLostNotice), findsOneWidget);
      expect(repo.entries.length, 1);
      final discEntry = repo.entries.first;
      expect(discEntry.result, MatchResult.lose);
      expect(discEntry.endReason, MatchEndReason.baglantiKoptu);
      expect(discEntry.matchId, 'm_disc');
      expect(discEntry.isFinal, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '8. Uygulama yeniden başlatıldıktan sonra (StopwatchClock sıfırlansa bile) biten online maç gerçek depoya yazılır ve yeni depo örneğinde en başta okunur',
    () async {
      // Önceki daha uzun oturumdan kalmış 10 kayıt (500.000 ms - 1.400.000 ms arası zaman damgaları,
      // botlaOynandi alanı olan ve olmayan eski kayıtlar birlikte)
      final existingJsonList = List.generate(10, (i) {
        final map = <String, dynamic>{
          'id': 'prev_online_$i',
          'opponentName': 'Eski Oyuncu $i',
          'finishedAtMs': 500000 + i * 100000,
          'myScore': 1,
          'opponentScore': 2,
          'result': 'lose',
          'endType': 'normal',
          'forfeitedPlayerId': null,
          'roundRecords': <Map<String, dynamic>>[],
          'roundQuestionTexts': <String>[],
        };
        if (i.isOdd) {
          map['botlaOynandi'] = true;
        }
        return map;
      });

      SharedPreferences.setMockInitialValues({
        'kelimego_match_history': jsonEncode(existingJsonList),
      });

      final client = FakeOnlineMatchClient();
      final container = ProviderContainer(
        overrides: [
          // Varsayılan gameClockProvider (StopwatchClock) ve gerçek LocalMatchHistoryRepository kullanılır!
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_restart_online_1',
        opponentName: 'Gerçek Rakip',
      );

      client.emit(
        const OnlineMatchFinal(
          FinalServerMessage(
            rounds: [
              OnlineRoundRecord(
                questionId: 'q_1',
                attempts: [
                  OnlineAttempt(mine: true, text: 'ankara', result: 'correct'),
                ],
                winnerIsMe: true,
                reason: 'timeout',
              ),
            ],
            myScore: 2,
            opponentScore: 0,
            winnerIsMe: true,
            endedBy: 'normal',
          ),
        ),
      );

      // Asenkron SharedPreferences yazımının tamamlanmasını bekle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Uygulama yeniden başlatılmış gibi YENİ bir LocalMatchHistoryRepository örneğiyle oku
      final freshRepo = LocalMatchHistoryRepository();
      final loaded = await freshRepo.loadRecent();

      expect(loaded.length, 10);
      expect(loaded.first.id, 'm_restart_online_1');
      expect(loaded.first.opponentName, 'Gerçek Rakip');
      expect(loaded.first.botlaOynandi, isFalse);
      expect(loaded.first.result, MatchResult.win);

      // Sağlayıcı üzerinden de güncel listenin döndüğünü doğrula
      final providerList = await container.read(matchHistoryProvider.future);
      expect(providerList.first.id, 'm_restart_online_1');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '9. leaveMatch sonrası state(phase: matchFinished) gelip final düşerse zaman aşımında kayıt kaybolmaz',
    () async {
      final clock = FakeManualClock(45000);
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
      await session.startOnlineMatch(
        matchId: 'm_leave_state_only',
        opponentName: 'Deniz',
      );

      session.leaveMatch();
      expect(capturedTimeoutCallback, isNotNull);

      // Sunucudan state(phase: matchFinished) gelir ama final mesajı ağda düşer
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 45000,
            receivedLocalMs: 45000,
            phase: OnlineMatchPhase.matchFinished,
            roundNumber: 1,
            myScore: 0,
            opponentScore: 2,
            question: OnlineQuestion(id: 'q_1', text: 'Renkler'),
            turnIsMine: false,
            deadlineMs: 0,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Deniz',
            opponentConnected: true,
            endedBy: 'forfeit',
            winnerIsMe: false,
          ),
        ),
      );

      // 3 sn zaman aşımı tetiklenir -> final gelmediği için yerel kayıt üretilmeli
      capturedTimeoutCallback!();
      await Future<void>.delayed(Duration.zero);

      expect(repo.entries.length, 1);
      expect(repo.entries.first.id, 'm_leave_state_only');
      expect(repo.entries.first.endType, MatchEndType.forfeit);
      expect(repo.entries.first.botlaOynandi, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '10. OnlineMatchReconnecting ve OnlineMatchConnected kendiBağlantı durumunu günceller',
    () async {
      final client = FakeOnlineMatchClient();
      final repo = FakeHistoryRepo();

      final container = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_conn_status',
        opponentName: 'Zeynep',
        client: client,
      );

      expect(session.state.kendiBaglanti, ConnectionStatus.connected);

      client.emit(const OnlineMatchReconnecting());
      expect(session.state.kendiBaglanti, ConnectionStatus.reconnecting);

      client.emit(const OnlineMatchConnected());
      expect(session.state.kendiBaglanti, ConnectionStatus.connected);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '11. opponentConnected false olunca rakipBağlı false olur, true gelince düzelir',
    () async {
      final client = FakeOnlineMatchClient();
      final repo = FakeHistoryRepo();

      final container = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_opp_status',
        opponentName: 'Zeynep',
        client: client,
      );

      expect(session.state.rakipBagli, isTrue);

      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 10000,
            receivedLocalMs: 10000,
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 1,
            myScore: 0,
            opponentScore: 0,
            turnIsMine: true,
            deadlineMs: 25000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Zeynep',
            opponentConnected: false,
          ),
        ),
      );

      expect(session.state.rakipBagli, isFalse);
      expect(session.state.opponentConnected, isFalse);

      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 12000,
            receivedLocalMs: 12000,
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 1,
            myScore: 0,
            opponentScore: 0,
            turnIsMine: true,
            deadlineMs: 25000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Zeynep',
            opponentConnected: true,
          ),
        ),
      );

      expect(session.state.rakipBagli, isTrue);
      expect(session.state.opponentConnected, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '12. DisconnectReason.replaced durumunda isDisconnectedReplaced: true olur, kalıcı kopmada false kalır',
    () async {
      final client1 = FakeOnlineMatchClient();
      final repo1 = FakeHistoryRepo();

      final container1 = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo1),
        ],
      );
      addTearDown(container1.dispose);

      final session1 = container1.read(onlineMatchSessionProvider.notifier);
      await session1.startOnlineMatch(
        matchId: 'm_replaced',
        opponentName: 'Ayşe',
        client: client1,
      );

      client1.emit(const OnlineMatchDisconnected(DisconnectReason.replaced));

      expect(session1.state.isDisconnectedPermanent, isTrue);
      expect(session1.state.isDisconnectedReplaced, isTrue);
      expect(repo1.entries, isEmpty); // Geçmişe kayıt yazılmaz!

      final client2 = FakeOnlineMatchClient();
      final repo2 = FakeHistoryRepo();

      final container2 = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo2),
        ],
      );
      addTearDown(container2.dispose);

      final session2 = container2.read(onlineMatchSessionProvider.notifier);
      await session2.startOnlineMatch(
        matchId: 'm_permanent',
        opponentName: 'Mehmet',
        client: client2,
      );

      client2.emit(const OnlineMatchDisconnected(DisconnectReason.permanent));

      expect(session2.state.isDisconnectedPermanent, isTrue);
      expect(session2.state.isDisconnectedReplaced, isFalse);
      expect(repo2.entries.length, 1); // Kalıcı kopmada yerel yenilgi kaydı yazılır!
      expect(repo2.entries.first.result, MatchResult.lose);
      expect(repo2.entries.first.endReason, MatchEndReason.baglantiKoptu);
      expect(repo2.entries.first.matchId, 'm_permanent');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '13. OnlineMatchSession yaşam döngüsü çağrılarını client\'a aktarır',
    () async {
      final client = FakeOnlineMatchClient();
      final repo = FakeHistoryRepo();

      final container = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_lifecycle',
        opponentName: 'Burak',
        client: client,
      );

      expect(client.pausedCalled, isFalse);
      expect(client.resumedCalled, isFalse);

      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(client.pausedCalled, isTrue);

      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(client.resumedCalled, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '14. Kalıcı kopma hemen yerel yenilgi yazar; sonradan gelen final mevcut kaydı günceller ve tek kayıt kalır',
    () async {
      final clock = FakeManualClock(60000);
      final repo = FakeHistoryRepo();
      final client = FakeOnlineMatchClient();

      final container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_disc_update',
        opponentName: 'Deniz',
        client: client,
      );

      // 1. Turda 0-0 iken kalıcı kopma
      client.emit(
        const OnlineMatchDisconnected(DisconnectReason.permanent),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repo.entries.length, 1);
      final localLoss = repo.entries.first;
      expect(localLoss.matchId, 'm_disc_update');
      expect(localLoss.result, MatchResult.lose);
      expect(localLoss.endReason, MatchEndReason.baglantiKoptu);
      expect(localLoss.myScore, 0);
      expect(localLoss.opponentScore, 0);
      expect(localLoss.isFinal, isFalse);

      // 2. Oyuncu yeniden bağlandı ve sunucudan kesin final geldi (ör. 0-2 skorla)
      final client2 = FakeOnlineMatchClient();
      await session.startOnlineMatch(
        matchId: 'm_disc_update',
        opponentName: 'Deniz',
        client: client2,
      );

      const finalMsg = FinalServerMessage(
        rounds: [],
        myScore: 0,
        opponentScore: 2,
        winnerIsMe: false,
        endedBy: 'forfeit',
      );

      client2.emit(const OnlineMatchFinal(finalMsg));
      await Future<void>.delayed(Duration.zero);

      // Toplam kayıt sayısı ARTMAZ (1 kalır), veriler güncellenir
      expect(repo.entries.length, 1);
      final updatedLoss = repo.entries.first;
      expect(updatedLoss.matchId, 'm_disc_update');
      expect(updatedLoss.result, MatchResult.lose);
      expect(updatedLoss.endReason, MatchEndReason.baglantiKoptu);
      expect(updatedLoss.myScore, 0);
      expect(updatedLoss.opponentScore, 2);
      expect(updatedLoss.isFinal, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '15. Rakip bağlantısı kopup maç bitince rakipBaglantiKoptu; kopmadan çıkınca rakipTerk atanır',
    () async {
      // Senaryo A: Rakip koptu (opponentConnected: false) ve ardından final (forfeit) geldi
      final clientA = FakeOnlineMatchClient();
      final repoA = FakeHistoryRepo();
      final containerA = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repoA),
        ],
      );
      addTearDown(containerA.dispose);

      final sessionA = containerA.read(onlineMatchSessionProvider.notifier);
      await sessionA.startOnlineMatch(
        matchId: 'm_opp_disc',
        opponentName: 'Ahmet',
        client: clientA,
      );

      // Rakip bağlantısı koptu bilgisi state'e yansıdı
      clientA.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 1,
            myScore: 1,
            opponentScore: 0,
            turnIsMine: true,
            deadlineMs: 70000,
            serverNowMs: 60000,
            receivedLocalMs: 60000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Ahmet',
            opponentConnected: false,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      clientA.emit(
        const OnlineMatchFinal(
          FinalServerMessage(
            rounds: [],
            myScore: 1,
            opponentScore: 0,
            winnerIsMe: true,
            endedBy: 'forfeit',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repoA.entries.length, 1);
      expect(repoA.entries.first.endReason, MatchEndReason.rakipBaglantiKoptu);
      expect(repoA.entries.first.result, MatchResult.win);

      // Senaryo B: Rakip kopmadan maçı terk etti (opponentConnected hep true kaldı)
      final clientB = FakeOnlineMatchClient();
      final repoB = FakeHistoryRepo();
      final containerB = ProviderContainer(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repoB),
        ],
      );
      addTearDown(containerB.dispose);

      final sessionB = containerB.read(onlineMatchSessionProvider.notifier);
      await sessionB.startOnlineMatch(
        matchId: 'm_opp_leave',
        opponentName: 'Zeynep',
        client: clientB,
      );

      clientB.emit(
        const OnlineMatchFinal(
          FinalServerMessage(
            rounds: [],
            myScore: 1,
            opponentScore: 0,
            winnerIsMe: true,
            endedBy: 'forfeit',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repoB.entries.length, 1);
      expect(repoB.entries.first.endReason, MatchEndReason.rakipTerk);
      expect(repoB.entries.first.result, MatchResult.win);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'OnlineMatchSession displayText testi: doğru cevapta displayText, yanlış cevapta text kullanılır, geriye dönük displayText yoksa text fallback olur',
    () async {
      final client = FakeOnlineMatchClient();
      final container = ProviderContainer(
        overrides: [
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_alias_test',
        opponentName: 'Ahmet',
      );

      // Sunucudan state mesajı gelir:
      // 1. Doğru cevap: displayText = "Beşiktaş", text = "Beşiktaş"
      // 2. Doğru cevap (eski sunucu fallback): displayText = null, text = "Fenerbahçe"
      // 3. Yanlış cevap: displayText = null, text = "yanlis_girdi"
      final onlineState = OnlineMatchState(
        serverNowMs: 50000,
        receivedLocalMs: 10000,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 0,
        opponentScore: 0,
        question: const OnlineQuestion(
          id: 'q_futbol',
          text: 'Futbol Takımları',
        ),
        turnIsMine: true,
        deadlineMs: 65000,
        myHintsLeft: 1,
        attempts: const [
          OnlineAttempt(
            mine: true,
            text: 'Beşiktaş',
            displayText: 'Beşiktaş',
            result: 'correct',
          ),
          OnlineAttempt(
            mine: false,
            text: 'Fenerbahçe',
            displayText: null,
            result: 'correct',
          ),
          OnlineAttempt(
            mine: true,
            text: 'yanlis_girdi',
            displayText: null,
            result: 'wrong',
          ),
        ],
        opponentName: 'Ahmet',
        opponentConnected: true,
      );

      client.emit(OnlineMatchStateUpdate(onlineState));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(onlineMatchSessionProvider);
      expect(state.roundAttempts.length, 3);
      expect(state.roundAttempts[0].text, 'Beşiktaş');
      expect(state.roundAttempts[0].isCorrect, isTrue);

      expect(state.roundAttempts[1].text, 'Fenerbahçe');
      expect(state.roundAttempts[1].isCorrect, isTrue);

      expect(state.roundAttempts[2].text, 'yanlis_girdi');
      expect(state.roundAttempts[2].isCorrect, isFalse);
    },
  );

  test(
    '15. Maçı bitiren turda sunucudan state(phase: matchFinished) ve final geldiğinde isRoundEnded ASLA true olmaz, doğrudan isMatchFinished true olur (ranked ve friendly)',
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
      await session.startOnlineMatch(matchId: 'm_finish_test', opponentName: 'Ayşe');

      // 1. Tur bitti (ara tur) -> roundEnded fazı gelir, isRoundEnded true olur
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 20000,
            receivedLocalMs: 20000,
            phase: OnlineMatchPhase.roundEnded,
            roundNumber: 1,
            myScore: 1,
            opponentScore: 0,
            question: OnlineQuestion(id: 'q_1', text: 'Meyveler'),
            turnIsMine: false,
            deadlineMs: 0,
            nextRoundAtMs: 23000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Ayşe',
            opponentConnected: true,
          ),
        ),
      );
      var uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isRoundEnded, isTrue);
      expect(uiState.isMatchFinished, isFalse);

      // 2. Tur başladı -> roundActive fazı gelir, isRoundEnded false olur
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 23000,
            receivedLocalMs: 23000,
            phase: OnlineMatchPhase.roundActive,
            roundNumber: 2,
            myScore: 1,
            opponentScore: 0,
            question: OnlineQuestion(id: 'q_2', text: 'Renkler'),
            turnIsMine: true,
            deadlineMs: 38000,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Ayşe',
            opponentConnected: true,
          ),
        ),
      );
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isRoundEnded, isFalse);
      expect(uiState.isMatchFinished, isFalse);

      // 3. 2. Tur bitti ve maçı bitirdi (skor 2-0):
      // Sunucu doğrudan phase: matchFinished gönderir (roundEnded göndermez!)
      client.emit(
        const OnlineMatchStateUpdate(
          OnlineMatchState(
            serverNowMs: 35000,
            receivedLocalMs: 35000,
            phase: OnlineMatchPhase.matchFinished,
            roundNumber: 2,
            myScore: 2,
            opponentScore: 0,
            question: OnlineQuestion(id: 'q_2', text: 'Renkler'),
            turnIsMine: false,
            deadlineMs: 0,
            myHintsLeft: 1,
            attempts: [],
            opponentName: 'Ayşe',
            opponentConnected: true,
            winnerIsMe: true,
            endedBy: 'normal',
          ),
        ),
      );
      uiState = container.read(onlineMatchSessionProvider);
      // DOĞRULAMA: Ara tur-sonu ekranı (isRoundEnded) ASLA true olmaz!
      expect(uiState.isRoundEnded, isFalse);
      expect(uiState.isMatchFinished, isTrue);
      expect(uiState.matchState?.scores['me'], 2);
      expect(uiState.matchState?.scores['bot'], 0);

      // 4. Hemen ardından final mesajı gelir
      client.emit(
        const OnlineMatchFinal(
          FinalServerMessage(
            rounds: [
              OnlineRoundRecord(
                questionId: 'q_1',
                attempts: [],
                winnerIsMe: true,
                reason: 'timeout',
              ),
              OnlineRoundRecord(
                questionId: 'q_2',
                attempts: [],
                winnerIsMe: true,
                reason: 'timeout',
              ),
            ],
            myScore: 2,
            opponentScore: 0,
            winnerIsMe: true,
            endedBy: 'normal',
            coinsAwarded: 50,
            coins: null,
          ),
        ),
      );
      uiState = container.read(onlineMatchSessionProvider);
      expect(uiState.isRoundEnded, isFalse);
      expect(uiState.isMatchFinished, isTrue);
      expect(uiState.coinsAwarded, 50);
    },
  );
}


