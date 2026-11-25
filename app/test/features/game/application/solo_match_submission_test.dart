import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/achievements/application/achievement_notification_service.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/data/solo_match_api_client.dart';
import 'package:app/features/game/data/solo_match_queue_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';

class _FakeProfileNotifier extends ProfileNotifier {
  int updatedCoins = -1;
  EnergyState? updatedEnergy;
  int syncCalls = 0;

  @override
  Future<void> updateCoins(int coins) async {
    updatedCoins = coins;
  }

  @override
  void updateEnergy(EnergyState energy, [int? serverNowMs]) {
    updatedEnergy = energy;
  }

  @override
  Future<bool> syncWithServer({bool force = false}) async {
    syncCalls++;
    return true;
  }
}

class FakeGameClock implements GameClock {
  final FakeAsync async;
  FakeGameClock(this.async);

  @override
  int nowMs() => async.elapsed.inMilliseconds;
}

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => const [];

  @override
  Future<void> clear() async {}
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
  const q3 = Question(
    id: 'q3',
    categoryId: 'c1',
    text: 'Soru 3',
    answers: [
      Answer(id: 'a3_1', display: 'Cevap 1', aliases: ['cevap1']),
      Answer(id: 'a3_2', display: 'Cevap 2', aliases: ['cevap2']),
    ],
  );

  group('MatchController Solo Match Submission', () {
    test('1. Galibiyetle biten solo maçta POST /matches/solo isteği doğru alanlarla tetiklenir ve ödüller UI state e yazılır', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => const SubmitSoloMatchSuccess(
            ok: true,
            counted: true,
            coins: 250,
            coinsAwarded: 30,
            unlockedAchievements: ['first_win'],
            energy: EnergyState(enabled: true, current: 4, max: 5),
          ),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          questions: [q1, q2, q3],
          opponentName: 'Ahmet',
          initialTurnPlayerId: 'me',
        );

        async.elapse(const Duration(milliseconds: 5000));

        // Galibiyet durumu simülasyonu
        final start = MatchEngine.start(
          config: const MatchConfig(roundsToWin: 2),
          playerIds: ['me', 'bot'],
          questions: [q1, q2],
          random: math.Random(42),
          nowMs: 1000,
        );
        final winState = start.state.copyWith(
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
                  nowMs: 2000,
                ),
              ],
            ),
            RoundRecord(
              questionId: 'q2',
              starterPlayerId: 'bot',
              winnerId: 'me',
              reason: RoundEndReason.exhausted,
              attempts: [
                TurnAttempt(
                  playerId: 'me',
                  rawInput: 'cevap2',
                  resultType: AttemptResultType.correct,
                  nowMs: 4000,
                ),
              ],
            ),
          ],
        );

        controller.applyEngineResultForTesting(
          EngineResult(winState, [const MatchFinished('me', 'normal')]),
        );
        async.elapse(const Duration(milliseconds: 100));

        // API'ye istek anında yapılmış olmalıdır
        expect(mockApi.submissions.length, equals(1));
        final sub = mockApi.submissions.first;

        expect(sub.matchId.startsWith('bot:'), isTrue);
        expect(sub.outcome, equals('win'));
        expect(sub.endedBy, equals('normal'));
        expect(sub.myScore, equals(2));
        expect(sub.oppScore, equals(0));
        expect(sub.correctAnswers, equals(2));
        expect(sub.durationSeconds, greaterThanOrEqualTo(5));

        // UI State kontrolü
        final uiState = container.read(matchControllerProvider);
        expect(uiState.coinsAwarded, equals(30));
        expect(uiState.unlockedAchievements, equals(['first_win']));

        // Kuyruğa eklenmemelidir
        expect(mockQueue.queue, isEmpty);

        container.dispose();
      });
    });

    test('2. Oyuncu maçı terk ettiğinde (forfeit) outcome=loss, endedBy=forfeit ile gönderilir', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient();
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          questions: [q1, q2, q3],
          opponentName: 'Mehmet',
          initialTurnPlayerId: 'me',
        );

        async.elapse(const Duration(milliseconds: 5000));

        // Terk et
        controller.leaveMatch();
        async.elapse(const Duration(milliseconds: 100));

        expect(mockApi.submissions.length, equals(1));
        final sub = mockApi.submissions.first;
        expect(sub.outcome, equals('loss'));
        expect(sub.endedBy, equals('forfeit'));
        expect(sub.myScore, equals(0));
        expect(sub.oppScore, equals(2)); // Best of 3 gereği bot skoru 2 yapılır

        container.dispose();
      });
    });

    test('3. draw_limit_reached durumunda maç sunucuya HİÇ iletilmez (isVoided)', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient();
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          questions: [q1, q2, q3],
          opponentName: 'Can',
          initialTurnPlayerId: 'me',
        );

        // draw_limit_reached simülasyonu
        final start = MatchEngine.start(
          config: const MatchConfig(roundsToWin: 2, maxTotalRounds: 5),
          playerIds: ['me', 'bot'],
          questions: [q1, q2],
          random: math.Random(42),
          nowMs: 1000,
        );
        final drawState = start.state.copyWith(
          phase: MatchPhase.matchFinished,
          endedBy: 'draw_limit_reached',
        );

        controller.applyEngineResultForTesting(
          EngineResult(
            drawState,
            [const MatchFinished(null, 'draw_limit_reached')],
          ),
        );

        // draw_limit_reached tetiklendiğinde maç voided olur
        final uiState = container.read(matchControllerProvider);
        expect(uiState.isVoided, isTrue);

        // Sunucuya istek ATILMAMALIDIR
        expect(mockApi.submissions, isEmpty);
        expect(mockQueue.queue, isEmpty);

        container.dispose();
      });
    });

    test('4. Geçici ağ hatasında maç sonucu kuyruğa (SoloMatchQueueRepository) kaydedilir', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => const SubmitSoloMatchTransientError('Ağ bağlantısı yok'),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          questions: [q1, q2, q3],
          opponentName: 'Ali',
        );

        async.elapse(const Duration(milliseconds: 2000));
        controller.leaveMatch();
        async.elapse(const Duration(milliseconds: 100));

        // İstek denenmiştir
        expect(mockApi.submissions.length, equals(1));

        // Geçici hata olduğu için kuyruğa eklenmiştir
        expect(mockQueue.queue.length, equals(1));
        expect(mockQueue.queue.first.matchId, equals(mockApi.submissions.first.matchId));

        container.dispose();
      });
    });

    test('5. counted: false durumunda (yetersiz enerji vb.) coinsAwarded null kalır', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => const SubmitSoloMatchSuccess(
            ok: true,
            counted: false,
            coins: 100,
            coinsAwarded: 0,
          ),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          questions: [q1, q2, q3],
          opponentName: 'Veli',
        );

        controller.leaveMatch();
        async.elapse(const Duration(milliseconds: 100));

        final uiState = container.read(matchControllerProvider);
        expect(uiState.coinsAwarded, isNull);

        container.dispose();
      });
    });

    test('6. Biletli solo maç draw_limit_reached ile biterse { ticketId, outcome: void } gönderir ve refunded: true ile enerji günceller', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final fakeProfile = _FakeProfileNotifier();
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => const SubmitSoloMatchSuccess(
            ok: true,
            counted: false,
            voided: true,
            refunded: true,
            energy: EnergyState(enabled: true, current: 5, max: 5),
          ),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(() => fakeProfile),
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
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
          matchId: 'bot:voidTicketMatch123',
          ticketId: 'stk_voidTicket123456',
          questions: [q1, q2, q3],
          opponentName: 'Deniz',
        );

        final start = MatchEngine.start(
          config: const MatchConfig(roundsToWin: 2, maxTotalRounds: 5),
          playerIds: ['me', 'bot'],
          questions: [q1, q2],
          random: math.Random(42),
          nowMs: 1000,
        );
        final drawState = start.state.copyWith(
          phase: MatchPhase.matchFinished,
          endedBy: 'draw_limit_reached',
          scores: const {'me': 1, 'bot': 1},
        );

        controller.applyEngineResultForTesting(
          EngineResult(
            drawState,
            [const MatchFinished(null, 'draw_limit_reached')],
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(container.read(matchControllerProvider).isVoided, isTrue);
        expect(mockApi.submissions.length, equals(1));
        expect(mockApi.submissions.first.ticketId, equals('stk_voidTicket123456'));
        expect(mockApi.submissions.first.outcome, equals('void'));
        expect(fakeProfile.updatedEnergy?.current, equals(5));
        expect(fakeProfile.updatedCoins, equals(-1)); // voided yanıtında jeton güncellenmez
        expect(mockQueue.queue, isEmpty);

        container.dispose();
      });
    });

    test('7. Biletli solo void gönderiminde geçici hatada kuyruğa alınır, 400/410 kalıcı hatada kuyruğa eklenmez', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        var returnTransient = true;
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => returnTransient
              ? const SubmitSoloMatchTransientError('401/5xx/network')
              : const SubmitSoloMatchPermanentError(statusCode: 400, error: 'ticket_expired'),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            soloMatchApiClientProvider.overrideWithValue(mockApi),
            soloMatchQueueRepositoryProvider.overrideWithValue(mockQueue),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(answerSeconds: 20, totalDecisiveRounds: 3),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:voidTransient123',
          ticketId: 'stk_voidTransient1234',
          questions: [q1, q2, q3],
          opponentName: 'Deniz',
        );

        final start = MatchEngine.start(
          config: const MatchConfig(roundsToWin: 2, maxTotalRounds: 5),
          playerIds: ['me', 'bot'],
          questions: [q1, q2],
          random: math.Random(42),
          nowMs: 1000,
        );
        final drawState = start.state.copyWith(
          phase: MatchPhase.matchFinished,
          endedBy: 'draw_limit_reached',
        );

        controller.applyEngineResultForTesting(
          EngineResult(drawState, [const MatchFinished(null, 'draw_limit_reached')]),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(mockQueue.queue.length, equals(1));
        expect(mockQueue.queue.first.outcome, equals('void'));
        expect(mockQueue.queue.first.ticketId, equals('stk_voidTransient1234'));

        // Kalıcı hata (400) durumunda kuyruğa eklenmez
        mockQueue.queue.clear();
        returnTransient = false;
        controller.startMatch(
          matchId: 'bot:voidPermErr123',
          ticketId: 'stk_voidPermErr12345',
          questions: [q1, q2, q3],
          opponentName: 'Deniz',
        );
        controller.applyEngineResultForTesting(
          EngineResult(drawState, [const MatchFinished(null, 'draw_limit_reached')]),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(mockQueue.queue, isEmpty);

        container.dispose();
      });
    });

    test('8. Biletli solo void günlük sınır aşımı yanıtında (counted: true, voided: false) enerji güncellenir ve açılan başarım bildirimi gösterilir', () {
      fakeAsync((async) {
        final clock = FakeGameClock(async);
        final fakeProfile = _FakeProfileNotifier();
        final mockApi = MockSoloMatchApiClient(
          onSubmit: (sub) => const SubmitSoloMatchSuccess(
            ok: true,
            counted: true,
            voided: false,
            refunded: false,
            energy: EnergyState(enabled: true, current: 4, max: 5),
            unlockedAchievements: ['matches_10'],
          ),
        );
        final mockQueue = MockSoloMatchQueueRepository();

        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith(() => fakeProfile),
            gameClockProvider.overrideWithValue(clock),
            randomProvider.overrideWithValue(math.Random(42)),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            soloMatchApiClientProvider.overrideWithValue(mockApi),
            soloMatchQueueRepositoryProvider.overrideWithValue(mockQueue),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(answerSeconds: 20, totalDecisiveRounds: 3),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          matchId: 'bot:voidCapClient123',
          ticketId: 'stk_voidCapClient1234',
          questions: [q1, q2, q3],
          opponentName: 'Ege',
        );

        final start = MatchEngine.start(
          config: const MatchConfig(roundsToWin: 2, maxTotalRounds: 5),
          playerIds: ['me', 'bot'],
          questions: [q1, q2],
          random: math.Random(42),
          nowMs: 1000,
        );
        final drawState = start.state.copyWith(
          phase: MatchPhase.matchFinished,
          endedBy: 'draw_limit_reached',
        );

        controller.applyEngineResultForTesting(
          EngineResult(drawState, [const MatchFinished(null, 'draw_limit_reached')]),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(fakeProfile.updatedEnergy?.current, equals(4));
        expect(fakeProfile.updatedCoins, equals(-1)); // jeton sıfırlanmaz
        expect(
          container.read(achievementNotificationProvider).currentItem?.id,
          equals('matches_10'),
        );

        container.dispose();
      });
    });
  });
}
