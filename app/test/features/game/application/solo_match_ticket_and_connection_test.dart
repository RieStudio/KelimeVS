import 'dart:async';
import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/data/solo_match_api_client.dart';
import 'package:app/features/game/data/solo_match_queue_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';

class FakeGameClock implements GameClock {
  final FakeAsync async;
  FakeGameClock(this.async);

  @override
  int nowMs() => async.elapsed.inMilliseconds;
}

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  final List<MatchHistoryEntry> entries = [];

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    entries.add(entry);
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => List.unmodifiable(entries);

  @override
  Future<void> clear() async {
    entries.clear();
  }
}

class MockSoloMatchApiClient implements SoloMatchApiClient {
  final List<SoloMatchSubmission> submissions = [];
  SubmitSoloMatchResult Function(SoloMatchSubmission)? onSubmit;

  MockSoloMatchApiClient({this.onSubmit});

  @override
  Future<SubmitSoloMatchResult> submit(SoloMatchSubmission submission) async {
    submissions.add(submission);
    if (onSubmit != null) {
      return onSubmit!(submission);
    }
    return const SubmitSoloMatchSuccess(
      ok: true,
      counted: true,
      coins: 200,
      coinsAwarded: 30,
      unlockedAchievements: ['first_win'],
    );
  }
}

class MockSoloMatchQueueRepository implements SoloMatchQueueRepository {
  final List<SoloMatchSubmission> queue = [];

  @override
  Future<void> enqueue(SoloMatchSubmission submission) async {
    queue.add(submission);
  }

  @override
  Future<List<SoloMatchSubmission>> getPendingSubmissions() async => List.unmodifiable(queue);

  @override
  Future<void> remove(String matchId) async {
    queue.removeWhere((s) => s.matchId == matchId);
  }

  @override
  Future<void> clear() async {
    queue.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const q1 = Question(
    id: 'q1',
    categoryId: 'c1',
    text: 'Soru 1',
    answers: [
      Answer(id: 'a1_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a1_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );
  const q2 = Question(
    id: 'q2',
    categoryId: 'c1',
    text: 'Soru 2',
    answers: [
      Answer(id: 'a2_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a2_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );

  group('Solo Match Ticket & Connection Requirement', () {
    test('1. Biletli maç sunucudan gelen matchId ve ticketId ile başlar ve sonuç bildiriminde iletir', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient();
        final mockQueue = MockSoloMatchQueueRepository();
        final historyRepo = FakeMatchHistoryRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
            soloMatchApiClientProvider.overrideWithValue(mockApi),
            soloMatchQueueRepositoryProvider.overrideWithValue(mockQueue),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:server_match_999',
          ticketId: 'ticket_abc_123',
          questions: [q1, q2],
          opponentName: 'Ahmet',
        );

        expect(controller.botMatchIdForTesting, 'bot:server_match_999');
        expect(controller.soloTicketIdForTesting, 'ticket_abc_123');

        // Maçı terk et (bitir)
        controller.leaveMatch();
        async.elapse(const Duration(milliseconds: 100));

        expect(mockApi.submissions.length, 1);
        final sub = mockApi.submissions.first;
        expect(sub.matchId, 'bot:server_match_999');
        expect(sub.ticketId, 'ticket_abc_123');
        expect(sub.outcome, 'loss');
        expect(sub.endedBy, 'forfeit');

        container.dispose();
      });
    });

    test('2. Maç sırasında bağlantı kopunca ConnectionBanner reconnecting durumuna geçer ve 15 sn sayaç başlar (oyun saati durmaz)', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final connectionStreamController = StreamController<bool>.broadcast();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            soloMatchApiClientProvider.overrideWithValue(MockSoloMatchApiClient()),
            soloMatchQueueRepositoryProvider.overrideWithValue(MockSoloMatchQueueRepository()),
            matchControllerProvider.overrideWith(
              () => MatchController(
                connectionStream: connectionStreamController.stream,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:match_1',
          ticketId: 'ticket_1',
          questions: [q1, q2],
          opponentName: 'Mehmet',
          initialTurnPlayerId: 'me',
        );
        async.elapse(Duration.zero);

        expect(container.read(matchControllerProvider).connectionStatus, ConnectionStatus.connected);
        expect(controller.disconnectForfeitTimerForTesting, isNull);

        // Bağlantı koptu sinyali
        connectionStreamController.add(false);
        async.elapse(Duration.zero);

        expect(container.read(matchControllerProvider).connectionStatus, ConnectionStatus.reconnecting);
        expect(controller.disconnectForfeitTimerForTesting, isNotNull);
        expect(controller.disconnectForfeitTimerForTesting!.isActive, isTrue);

        // Oyun saati akmaya devam eder (nominal süre azalır, duraklama YOK)
        final remainingBefore = container.read(matchControllerProvider).remainingMs;
        async.elapse(const Duration(seconds: 3));
        final remainingAfter = container.read(matchControllerProvider).remainingMs;
        expect(remainingAfter, lessThan(remainingBefore));
        expect(container.read(matchControllerProvider).isPaused, isFalse);

        connectionStreamController.close();
        container.dispose();
      });
    });

    test('3. 15 saniye dolmadan bağlantı geri gelirse sayaç iptal edilir ve maç kesintisiz devam eder', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final connectionStreamController = StreamController<bool>.broadcast();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            soloMatchApiClientProvider.overrideWithValue(MockSoloMatchApiClient()),
            soloMatchQueueRepositoryProvider.overrideWithValue(MockSoloMatchQueueRepository()),
            matchControllerProvider.overrideWith(
              () => MatchController(
                connectionStream: connectionStreamController.stream,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:match_2',
          ticketId: 'ticket_2',
          questions: [q1, q2],
          opponentName: 'Ayşe',
          initialTurnPlayerId: 'me',
        );
        async.elapse(Duration.zero);

        // Bağlantı koptu
        connectionStreamController.add(false);
        async.elapse(const Duration(seconds: 5));
        expect(container.read(matchControllerProvider).connectionStatus, ConnectionStatus.reconnecting);

        // 5. saniyede bağlantı geri geldi
        connectionStreamController.add(true);
        async.elapse(Duration.zero);

        expect(container.read(matchControllerProvider).connectionStatus, ConnectionStatus.connected);
        expect(controller.disconnectForfeitTimerForTesting, isNull);
        expect(container.read(matchControllerProvider).isMatchFinished, isFalse);

        connectionStreamController.close();
        container.dispose();
      });
    });

    test('4. 15 saniye içinde bağlantı gelmezse maç hükmen kayıp (baglantiKoptu) ile biter ve yerel kuyruğa eklenir', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final connectionStreamController = StreamController<bool>.broadcast();
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (_) => const SubmitSoloMatchTransientError('Bağlantı yok'),
        );
        final mockQueue = MockSoloMatchQueueRepository();
        final historyRepo = FakeMatchHistoryRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
            soloMatchApiClientProvider.overrideWithValue(mockApi),
            soloMatchQueueRepositoryProvider.overrideWithValue(mockQueue),
            matchControllerProvider.overrideWith(
              () => MatchController(
                connectionStream: connectionStreamController.stream,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:match_3',
          ticketId: 'ticket_3',
          questions: [q1, q2],
          opponentName: 'Fatma',
          initialTurnPlayerId: 'me',
        );
        async.elapse(Duration.zero);

        // Bağlantı koptu
        connectionStreamController.add(false);
        async.elapse(Duration.zero);

        // 15 saniyelik zaman aşımı süresini geçir
        async.elapse(const Duration(seconds: 16));

        final uiState = container.read(matchControllerProvider);
        expect(uiState.isMatchFinished, isTrue);
        expect(uiState.connectionStatus, ConnectionStatus.permanentDisconnected);
        expect(uiState.isDisconnectedPermanent, isTrue);

        // Geçmiş kaydı kontrolü: baglantiKoptu, forfeitedPlayerId: 'me', result: lose
        expect(historyRepo.entries.length, 1);
        final entry = historyRepo.entries.first;
        expect(entry.endType, MatchEndType.forfeit);
        expect(entry.endReason, MatchEndReason.baglantiKoptu);
        expect(entry.forfeitedPlayerId, 'me');
        expect(entry.result, MatchResult.lose);

        // Çevrim dışı olduğu için yerel bekleme kuyruğuna kaydedildi
        expect(mockQueue.queue.length, 1);
        final queuedSub = mockQueue.queue.first;
        expect(queuedSub.matchId, 'bot:match_3');
        expect(queuedSub.ticketId, 'ticket_3');
        expect(queuedSub.outcome, 'loss');
        expect(queuedSub.endedBy, 'forfeit');

        connectionStreamController.close();
        container.dispose();
      });
    });

    test('5. Bağlantı kopukken maç doğal yolla biterse sonuç hükmen değil normal sonuç olarak kaydedilir/kuyruğa alınır', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final connectionStreamController = StreamController<bool>.broadcast();
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (_) => const SubmitSoloMatchTransientError('Bağlantı yok'),
        );
        final mockQueue = MockSoloMatchQueueRepository();
        final historyRepo = FakeMatchHistoryRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
            soloMatchApiClientProvider.overrideWithValue(mockApi),
            soloMatchQueueRepositoryProvider.overrideWithValue(mockQueue),
            matchControllerProvider.overrideWith(
              () => MatchController(
                connectionStream: connectionStreamController.stream,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 20,
                totalDecisiveRounds: 1,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:match_4',
          ticketId: 'ticket_4',
          questions: [q1, q2],
          opponentName: 'Emre',
          initialTurnPlayerId: 'me',
        );
        async.elapse(Duration.zero);

        // Bağlantı koptu
        connectionStreamController.add(false);
        async.elapse(const Duration(seconds: 2));

        // Maçın doğal yolla normal bitişi (15 sn zaman aşımı dolmadan önce)
        final currentMatch = container.read(matchControllerProvider).matchState!;
        final winState = currentMatch.copyWith(
          phase: MatchPhase.matchFinished,
          endedBy: 'normal',
          winnerId: 'me',
          scores: const {'me': 2, 'bot': 0},
          roundHistory: const [
            RoundRecord(
              questionId: 'q1',
              starterPlayerId: 'me',
              winnerId: 'me',
              reason: RoundEndReason.exhausted,
              attempts: [
                TurnAttempt(
                  playerId: 'me',
                  rawInput: 'cevap1',
                  resultType: AttemptResultType.correct,
                  nowMs: 1000,
                ),
              ],
            ),
          ],
        );

        controller.applyEngineResultForTesting(
          EngineResult(winState, [const MatchFinished('me', 'normal')]),
        );
        async.elapse(const Duration(milliseconds: 600));

        final uiState = container.read(matchControllerProvider);
        expect(uiState.isMatchFinished, isTrue);

        // Normal sonuç olarak kaydedilmiş olmalı (baglantiKoptu değil)
        expect(historyRepo.entries.length, 1);
        final entry = historyRepo.entries.first;
        expect(entry.endType, MatchEndType.normal);
        expect(entry.endReason, MatchEndReason.normal);
        expect(entry.result, MatchResult.win);

        // Kuyrukta da normal win olmalı
        expect(mockQueue.queue.length, 1);
        final queuedSub = mockQueue.queue.first;
        expect(queuedSub.outcome, 'win');
        expect(queuedSub.endedBy, 'normal');
        expect(queuedSub.ticketId, 'ticket_4');

        connectionStreamController.close();
        container.dispose();
      });
    });

    test('6. SoloMatchSubmission serialization ve ticketId uyumluluğu', () {
      final sub = SoloMatchSubmission(
        matchId: 'bot:12345678',
        ticketId: 't_abc_xyz',
        outcome: 'win',
        myScore: 50,
        oppScore: 30,
        correctAnswers: 5,
        durationSeconds: 42,
        endedBy: 'normal',
        submittedAtMs: 1700000000,
      );

      final json = sub.toJson();
      expect(json['ticketId'], 't_abc_xyz');
      expect(json['matchId'], 'bot:12345678');

      final fromJson = SoloMatchSubmission.fromJson(json);
      expect(fromJson.ticketId, 't_abc_xyz');
      expect(fromJson.matchId, 'bot:12345678');
      expect(fromJson.outcome, 'win');
      expect(fromJson.myScore, 50);
      expect(fromJson.durationSeconds, 42);
    });
  });
}
