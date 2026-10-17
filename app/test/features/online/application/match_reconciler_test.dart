import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/online/application/match_reconciler.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

class _FakeMemoryMatchHistoryRepository implements MatchHistoryRepository {
  final List<MatchHistoryEntry> _entries = [];

  _FakeMemoryMatchHistoryRepository([List<MatchHistoryEntry>? initial]) {
    if (initial != null) {
      _entries.addAll(initial);
    }
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return List.unmodifiable(_entries);
  }

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    _entries.removeWhere((e) =>
        e.id == entry.id ||
        (entry.matchId != null && e.matchId != null && e.matchId == entry.matchId));
    _entries.insert(0, entry);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

class _MockOnlineMatchClient extends OnlineMatchClient {
  final StreamController<OnlineMatchEvent> _mockEventsController =
      StreamController<OnlineMatchEvent>.broadcast();

  String? connectedMatchId;
  bool isConnectCalled = false;
  bool isCloseCalled = false;
  final Future<void> Function(String matchId)? onConnect;

  _MockOnlineMatchClient({this.onConnect});

  @override
  Stream<OnlineMatchEvent> get events => _mockEventsController.stream;

  @override
  Future<void> connect(String matchId) async {
    isConnectCalled = true;
    connectedMatchId = matchId;
    if (onConnect != null) {
      await onConnect!(matchId);
    }
  }

  void emit(OnlineMatchEvent event) {
    if (!_mockEventsController.isClosed) {
      _mockEventsController.add(event);
    }
  }

  @override
  Future<void> close() async {
    isCloseCalled = true;
    await _mockEventsController.close();
  }
}

void main() {
  MatchHistoryEntry createTempEntry({
    required String id,
    required String matchId,
    String opponentName = 'Ali',
    int finishedAtMs = 5000,
    int myScore = 0,
    int opponentScore = 0,
  }) {
    return MatchHistoryEntry(
      id: id,
      matchId: matchId,
      opponentName: opponentName,
      finishedAtMs: finishedAtMs,
      myScore: myScore,
      opponentScore: opponentScore,
      result: MatchResult.lose,
      endType: MatchEndType.forfeit,
      endReason: MatchEndReason.baglantiKoptu,
      roundRecords: [
        const RoundRecord(
          questionId: 'q_1',
          starterPlayerId: 'me',
          winnerId: null,
          reason: RoundEndReason.timeout,
          attempts: [],
        ),
      ],
      roundQuestionTexts: const ['Türkiye illeri'],
      isFinal: false,
    );
  }

  group('MatchReconciler - Kesinleştirme Servisi', () {
    test(
      '1. isFinal=false kaydı sunucudan OnlineMatchFinal gelince isFinal=true olarak güncellenir ve tek kayıt kalır',
      () async {
        final repo = _FakeMemoryMatchHistoryRepository([
          createTempEntry(id: 'local_1', matchId: 'm_100'),
        ]);

        late _MockOnlineMatchClient createdClient;
        var onUpdatedCalled = false;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            createdClient = _MockOnlineMatchClient(
              onConnect: (matchId) async {
                // Sunucu bağlandığında hemen final mesajı gönderir
                createdClient.emit(
                  const OnlineMatchFinal(
                    FinalServerMessage(
                      rounds: [
                        OnlineRoundRecord(
                          questionId: 'q_1',
                          attempts: [
                            OnlineAttempt(
                              mine: true,
                              text: 'Ankara',
                              result: 'correct',
                            ),
                          ],
                          winnerIsMe: false,
                          reason: 'timeout',
                        ),
                      ],
                      myScore: 0,
                      opponentScore: 2,
                      winnerIsMe: false,
                      endedBy: 'forfeit',
                    ),
                  ),
                );
              },
            );
            return createdClient;
          },
          onUpdated: () => onUpdatedCalled = true,
          reconcileTimeout: const Duration(seconds: 2),
        );

        await reconciler.reconcile();

        expect(onUpdatedCalled, isTrue);
        expect(createdClient.isCloseCalled, isTrue);

        final entries = await repo.loadRecent();
        expect(entries.length, 1);
        final finalized = entries.first;
        expect(finalized.id, 'local_1');
        expect(finalized.matchId, 'm_100');
        expect(finalized.isFinal, isTrue);
        expect(finalized.result, MatchResult.lose);
        expect(finalized.myScore, 0);
        expect(finalized.opponentScore, 2);
        expect(finalized.endReason, MatchEndReason.baglantiKoptu);
        expect(finalized.roundRecords.length, 1);
        expect(finalized.roundQuestionTexts, ['Türkiye illeri']);
      },
    );

    test(
      '2. Sunucu maçı bilmiyorsa (error/disconnected) kayıt geçici (isFinal=false) olarak kalır ve sessizce tamamlanır',
      () async {
        final repo = _FakeMemoryMatchHistoryRepository([
          createTempEntry(id: 'local_2', matchId: 'm_expired'),
        ]);

        late _MockOnlineMatchClient createdClient;
        var onUpdatedCalled = false;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            createdClient = _MockOnlineMatchClient(
              onConnect: (matchId) async {
                createdClient.emit(
                  const OnlineMatchError('Match not found (404)'),
                );
              },
            );
            return createdClient;
          },
          onUpdated: () => onUpdatedCalled = true,
          reconcileTimeout: const Duration(seconds: 2),
        );

        await reconciler.reconcile();

        expect(onUpdatedCalled, isFalse);
        expect(createdClient.isCloseCalled, isTrue);

        final entries = await repo.loadRecent();
        expect(entries.length, 1);
        final unchanged = entries.first;
        expect(unchanged.isFinal, isFalse);
        expect(unchanged.matchId, 'm_expired');
      },
    );

    test(
      '3. Sunucu zaman aşımına uğrarsa (timeout) kayıt geçici kalır',
      () async {
        final repo = _FakeMemoryMatchHistoryRepository([
          createTempEntry(id: 'local_3', matchId: 'm_timeout'),
        ]);

        late _MockOnlineMatchClient createdClient;
        var onUpdatedCalled = false;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            createdClient = _MockOnlineMatchClient(
              onConnect: (matchId) async {
                // Hiçbir mesaj gönderme, zaman aşımı oluşsun
              },
            );
            return createdClient;
          },
          onUpdated: () => onUpdatedCalled = true,
          reconcileTimeout: const Duration(milliseconds: 50),
        );

        await reconciler.reconcile();

        expect(onUpdatedCalled, isFalse);
        expect(createdClient.isCloseCalled, isTrue);

        final entries = await repo.loadRecent();
        expect(entries.length, 1);
        expect(entries.first.isFinal, isFalse);
      },
    );

    test(
      '4. Eşzamanlı birden fazla kesinleştirme çağrısı engellenir (concurrency guard)',
      () async {
        final repo = _FakeMemoryMatchHistoryRepository([
          createTempEntry(id: 'local_4', matchId: 'm_concurrent'),
        ]);

        final clientConnectCompleter = Completer<void>();
        var clientInstantiations = 0;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            clientInstantiations++;
            return _MockOnlineMatchClient(
              onConnect: (matchId) async {
                await clientConnectCompleter.future;
              },
            );
          },
          reconcileTimeout: const Duration(seconds: 2),
        );

        // 1. çağrıyı başlat (asenkron bekliyor)
        final future1 = reconciler.reconcile();
        expect(reconciler.isReconciling, isTrue);

        // 2. çağrıyı hemen yap -> isReconciling guard nedeniyle es geçilmeli
        final future2 = reconciler.reconcile();

        // 1. çağrının kilidini çöz
        clientConnectCompleter.complete();
        await Future.wait([future1, future2]);

        expect(reconciler.isReconciling, isFalse);
        // İkinci çağrı yeni bir istemci üretmemeli
        expect(clientInstantiations, 1);
      },
    );

    test(
      '5. isFinal=false kaydı yoksa sunucuya bağlantı açılmaz',
      () async {
        final finalizedEntry = MatchHistoryEntry(
          id: 'local_done',
          matchId: 'm_done',
          opponentName: 'Can',
          finishedAtMs: 5000,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: const [],
          isFinal: true,
        );

        final repo = _FakeMemoryMatchHistoryRepository([finalizedEntry]);
        var clientCreated = false;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            clientCreated = true;
            return _MockOnlineMatchClient();
          },
        );

        await reconciler.reconcile();

        expect(clientCreated, isFalse);
      },
    );

    test(
      '6. Sunucudan gelen kesin sonuç kazandıysa kaydı olduğu gibi win ve rakipBaglantiKoptu olarak kaydeder',
      () async {
        final repo = _FakeMemoryMatchHistoryRepository([
          createTempEntry(id: 'local_win', matchId: 'm_win'),
        ]);

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            late _MockOnlineMatchClient client;
            client = _MockOnlineMatchClient(
              onConnect: (matchId) async {
                client.emit(
                  const OnlineMatchFinal(
                    FinalServerMessage(
                      rounds: [],
                      myScore: 2,
                      opponentScore: 1,
                      winnerIsMe: true,
                      endedBy: 'forfeit',
                    ),
                  ),
                );
              },
            );
            return client;
          },
          reconcileTimeout: const Duration(seconds: 2),
        );

        await reconciler.reconcile();

        final entries = await repo.loadRecent();
        expect(entries.length, 1);
        final finalized = entries.first;
        expect(finalized.isFinal, isTrue);
        expect(finalized.result, MatchResult.win);
        expect(finalized.myScore, 2);
        expect(finalized.opponentScore, 1);
        expect(finalized.endReason, MatchEndReason.rakipBaglantiKoptu);
      },
    );

    test(
      '8. Kural 5: Kesinleşen maçın final mesajındaki coins değeri onCoinsUpdated ile mutlak olarak iletilir',
      () async {
        final initialEntry = MatchHistoryEntry(
          id: 'local_entry_1',
          matchId: 'match_coins_reconcile',
          opponentName: 'Rakip',
          finishedAtMs: 1000,
          myScore: 0,
          opponentScore: 0,
          result: MatchResult.lose,
          endType: MatchEndType.forfeit,
          endReason: MatchEndReason.baglantiKoptu,
          roundRecords: const [],
          isFinal: false,
        );

        final repo = _FakeMemoryMatchHistoryRepository([initialEntry]);
        int? updatedCoins;

        final reconciler = MatchReconciler(
          repo: repo,
          clientFactory: () {
            late final _MockOnlineMatchClient client;
            client = _MockOnlineMatchClient(
              onConnect: (mId) async {
                client.emit(
                  const OnlineMatchFinal(
                    FinalServerMessage(
                      rounds: [],
                      myScore: 2,
                      opponentScore: 0,
                      winnerIsMe: true,
                      endedBy: 'normal',
                      coinsAwarded: 30,
                      coins: 160,
                    ),
                  ),
                );
              },
            );
            return client;
          },
          onCoinsUpdated: (coins) {
            updatedCoins = coins;
          },
          reconcileTimeout: const Duration(seconds: 2),
        );

        await reconciler.reconcile();

        expect(updatedCoins, 160);
      },
    );
  });
}

