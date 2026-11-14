import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/online_match_client.dart';
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

class TestOnlineMatchClient extends OnlineMatchClient {
  final StreamController<OnlineMatchEvent> controller =
      StreamController<OnlineMatchEvent>.broadcast(sync: true);

  String? connectedMatchId;
  int offerRematchCalls = 0;
  int acceptRematchCalls = 0;
  int declineRematchCalls = 0;
  int leaveRematchCalls = 0;
  bool closeCalled = false;

  @override
  Stream<OnlineMatchEvent> get events => controller.stream;

  @override
  Future<void> connect(String matchId) async {
    connectedMatchId = matchId;
    controller.add(const OnlineMatchConnected());
  }

  @override
  bool offerRematch() {
    offerRematchCalls++;
    return true;
  }

  @override
  bool acceptRematch() {
    acceptRematchCalls++;
    return true;
  }

  @override
  bool declineRematch() {
    declineRematchCalls++;
    return true;
  }

  @override
  bool leaveRematch() {
    leaveRematchCalls++;
    return true;
  }

  @override
  Future<void> close() async {
    closeCalled = true;
  }

  void emit(OnlineMatchEvent event) {
    if (!controller.isClosed) {
      controller.add(event);
    }
  }

  @override
  Future<void> dispose() async {
    await close();
    await controller.close();
  }
}

FinalServerMessage createFinalMessage({
  bool rematchAvailable = true,
  bool winnerIsMe = true,
  int myScore = 2,
  int opponentScore = 1,
  String endedBy = 'normal',
  String opponentName = 'Elif',
  String opponentUid = 'u_opp',
}) {
  return FinalServerMessage(
    rounds: const [],
    myScore: myScore,
    opponentScore: opponentScore,
    winnerIsMe: winnerIsMe,
    endedBy: endedBy,
    opponentName: opponentName,
    opponentUid: opponentUid,
    opponentFrame: 'classic',
    rematchAvailable: rematchAvailable,
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('OnlineMatchSession Rematch State Machine Tests', () {
    late FakeManualClock clock;
    late FakeHistoryRepo repo;
    late TestOnlineMatchClient client;
    late ProviderContainer container;
    late OnlineMatchSession session;

    setUp(() {
      clock = FakeManualClock(10000);
      repo = FakeHistoryRepo();
      client = TestOnlineMatchClient();
      container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
          onlineMatchClientFactoryProvider.overrideWithValue(() => client),
        ],
      );
      session = container.read(onlineMatchSessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('1. Başlangıçta rematchState unavailable durumundadır', () {
      expect(container.read(rematchStateProvider), equals(RematchState.unavailable));
    });

    test('2. Final mesajında rematchAvailable: true ise rematchState idle olur', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );

      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      expect(container.read(rematchStateProvider), equals(RematchState.idle));
      expect(container.read(rematchStateProvider).canOffer, isTrue);
    });

    test('3. Final mesajında rematchAvailable: false ise rematchState unavailable kalır', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );

      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: false)));

      expect(container.read(rematchStateProvider), equals(RematchState.unavailable));
      expect(container.read(rematchStateProvider).canOffer, isFalse);
    });

    test('4. offerRematch çağrıldığında pendingSent durumuna geçer ve client.offerRematch çağrılır', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      final ok = session.offerRematch();
      expect(ok, isTrue);
      expect(client.offerRematchCalls, 1);
      expect(container.read(rematchStateProvider), isA<RematchPendingSent>());
      final pending = container.read(rematchStateProvider) as RematchPendingSent;
      expect(pending.secondsRemaining, 45);

      // İkinci offerRematch çağrısı kilitli olmalıdır
      final secondOk = session.offerRematch();
      expect(secondOk, isFalse);
      expect(client.offerRematchCalls, 1);
    });

    test('5. Kendi teklifimizin yankısı (rematch_offered byUid: myUid) pendingSent durumunu korur', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      session.offerRematch();
      expect(container.read(rematchStateProvider), isA<RematchPendingSent>());

      // Sunucudan kendi UID'miz ile yankı gelir
      client.emit(
        const OnlineMatchRematchOffered(
          RematchOfferedServerMessage(byUid: 'u_me', expiresAtMs: 55000),
        ),
      );

      expect(container.read(rematchStateProvider), isA<RematchPendingSent>());
    });

    test('6. Rakip teklif ettiğinde (rematch_offered byUid: u_opp) pendingReceived durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      // Rakip teklif etti
      client.emit(
        const OnlineMatchRematchOffered(
          RematchOfferedServerMessage(byUid: 'u_opp', expiresAtMs: 55000),
        ),
      );

      expect(container.read(rematchStateProvider), isA<RematchPendingReceived>());
      final received = container.read(rematchStateProvider) as RematchPendingReceived;
      expect(received.secondsRemaining, 45);
    });

    test('7. pendingReceived iken acceptRematch çağrıldığında starting durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      client.emit(
        const OnlineMatchRematchOffered(
          RematchOfferedServerMessage(byUid: 'u_opp', expiresAtMs: 55000),
        ),
      );

      final ok = session.acceptRematch();
      expect(ok, isTrue);
      expect(client.acceptRematchCalls, 1);
      expect(container.read(rematchStateProvider), equals(RematchState.starting));

      // Tekrar kabul çağrısı no-op
      expect(session.acceptRematch(), isFalse);
      expect(client.acceptRematchCalls, 1);
    });

    test('8. pendingReceived iken declineRematch çağrıldığında declined durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      client.emit(
        const OnlineMatchRematchOffered(
          RematchOfferedServerMessage(byUid: 'u_opp', expiresAtMs: 55000),
        ),
      );

      final ok = session.declineRematch();
      expect(ok, isTrue);
      expect(client.declineRematchCalls, 1);
      expect(container.read(rematchStateProvider), equals(RematchState.declined));
      expect(container.read(rematchStateProvider).isTerminal, isTrue);
    });

    test('9. Sunucudan rematch_status: declined geldiğinde declined durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();

      client.emit(
        const OnlineMatchRematchStatus(
          RematchStatusServerMessage(status: RematchStatusType.declined),
        ),
      );

      expect(container.read(rematchStateProvider), equals(RematchState.declined));
      expect(container.read(rematchStateProvider).isTerminal, isTrue);
    });

    test('10. Sunucudan rematch_status: expired geldiğinde expired durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();

      client.emit(
        const OnlineMatchRematchStatus(
          RematchStatusServerMessage(status: RematchStatusType.expired),
        ),
      );

      expect(container.read(rematchStateProvider), equals(RematchState.expired));
      expect(container.read(rematchStateProvider).isTerminal, isTrue);
    });

    test('11. Sunucudan rematch_status: opponent_left geldiğinde opponentLeft durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();

      client.emit(
        const OnlineMatchRematchStatus(
          RematchStatusServerMessage(status: RematchStatusType.opponentLeft),
        ),
      );

      expect(container.read(rematchStateProvider), equals(RematchState.opponentLeft));
      expect(container.read(rematchStateProvider).isTerminal, isTrue);
    });

    test('12. Sunucudan rematch_status: closed geldiğinde closed durumuna geçer', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      client.emit(
        const OnlineMatchRematchStatus(
          RematchStatusServerMessage(status: RematchStatusType.closed),
        ),
      );

      expect(container.read(rematchStateProvider), equals(RematchState.closed));
      expect(container.read(rematchStateProvider).isTerminal, isTrue);
    });

    test('13. Sunucudan rematch_error (no_energy) geldiğinde error durumuna geçer ve buton kilitlenir', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();

      client.emit(
        const OnlineMatchRematchError(
          RematchErrorServerMessage(code: RematchErrorCode.noEnergy),
        ),
      );

      final state = container.read(rematchStateProvider);
      expect(state, isA<RematchError>());
      final err = state as RematchError;
      expect(err.code, RematchErrorCode.noEnergy);
      expect(err.isTerminal, isTrue);

      // Terminal hata durumunda yeni teklif veya kabul engellenir
      expect(session.offerRematch(), isFalse);
      expect(session.acceptRematch(), isFalse);
    });

    test('14. matched mesajı geldiğinde rematchState matched olur ve 1000/rematch_started soket kapanışı korunur', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();

      const newMatchMsg = MatchedServerMessage(
        matchId: 'm_rematch_999',
        opponentName: 'Elif',
        opponentFrame: 'classic',
        opponentUid: 'u_opp',
        isFriendly: false,
      );
      client.emit(const OnlineMatchMatched(newMatchMsg));

      final rematchState = container.read(rematchStateProvider);
      expect(rematchState, isA<RematchMatched>());
      final matchedState = rematchState as RematchMatched;
      expect(matchedState.matchedMessage.matchId, 'm_rematch_999');

      // Ardından gelen beklenen soket kapanışı (1000 / rematch_started)
      client.emit(
        const OnlineMatchDisconnected(
          DisconnectReason.rematchStarted,
          closeCode: 1000,
          closeReason: 'rematch_started',
        ),
      );

      // Durum korunmalı, kopma olarak algılanmamalıdır
      expect(container.read(rematchStateProvider), isA<RematchMatched>());
    });

    test('15. Maç bittikten sonra beklenmeyen soket kopması MatchEndView verilerini silmez', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

      // Maç bitmiş ve kaydedilmiş
      expect(container.read(activeMatchUiStateProvider).lastSavedMatch, isNotNull);

      // Soket beklenmedik şekilde koptu
      client.emit(const OnlineMatchDisconnected(DisconnectReason.error));

      // Maç özeti ve son kaydedilen maç silinmemeli, kullanıcı maç sonu ekranını görebilmeli
      expect(container.read(activeMatchUiStateProvider).lastSavedMatch, isNotNull);
      // Rematch durumu rakip ayrıldı veya unavailable olarak güncellenir
      expect(container.read(rematchStateProvider), equals(RematchState.opponentLeft));
    });

    test('16. leaveRematch client.leaveRematch çağırır ve pending durumu temizler', () async {
      await session.startOnlineMatch(
        matchId: 'm1',
        opponentName: 'Elif',
        opponentUid: 'u_opp',
      );
      client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));
      session.offerRematch();
      expect(container.read(rematchStateProvider), isA<RematchPendingSent>());

      session.leaveRematch();
      expect(client.leaveRematchCalls, 1);
      expect(container.read(rematchStateProvider), equals(RematchState.closed));

      // Çoklu çağrı güvenlidir (idempotent: tekrar ağ çağrısı yapmaz)
      session.leaveRematch();
      expect(client.leaveRematchCalls, 1);
      expect(container.read(rematchStateProvider), equals(RematchState.closed));
    });
  });

  testWidgets('17. 45 saniyelik yerel sayaç her saniye azalır ve süre bitince fallback çalışır', (tester) async {
    final clock = FakeManualClock(10000);
    final repo = FakeHistoryRepo();
    final client = TestOnlineMatchClient();
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
      matchId: 'm1',
      opponentName: 'Elif',
      opponentUid: 'u_opp',
    );
    client.emit(OnlineMatchFinal(createFinalMessage(rematchAvailable: true)));

    // Rakip teklif etti
    client.emit(
      const OnlineMatchRematchOffered(
        RematchOfferedServerMessage(byUid: 'u_opp', expiresAtMs: 55000),
      ),
    );

    final s1 = container.read(rematchStateProvider);
    expect(s1, isA<RematchPendingReceived>());
    expect((s1 as RematchPendingReceived).secondsRemaining, 45);

    // 10 saniye ilerlet
    await tester.pump(const Duration(seconds: 10));
    final s2 = container.read(rematchStateProvider);
    expect(s2, isA<RematchPendingReceived>());
    expect((s2 as RematchPendingReceived).secondsRemaining, 35);

    // 35 saniye daha ilerlet (toplam 45 saniye)
    await tester.pump(const Duration(seconds: 35));
    final s3 = container.read(rematchStateProvider);
    expect(s3, isA<RematchPendingReceived>());
    expect((s3 as RematchPendingReceived).secondsRemaining, 0);

    // Tolerans süresi (3 sn) sonrası yerel fallback expired yapar
    await tester.pump(const Duration(seconds: 4));
    final s4 = container.read(rematchStateProvider);
    expect(s4, equals(RematchState.expired));
  });
}
