import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
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

class LifecycleTestClient extends OnlineMatchClient {
  final StreamController<OnlineMatchEvent> controller =
      StreamController<OnlineMatchEvent>.broadcast(sync: true);

  String? connectedMatchId;

  @override
  Stream<OnlineMatchEvent> get events => controller.stream;

  @override
  Future<void> connect(String matchId) async {
    connectedMatchId = matchId;
    controller.add(const OnlineMatchConnected());
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

FinalServerMessage _createFinal(String matchId, String oppName, {bool winnerIsMe = true}) {
  return FinalServerMessage(
    rounds: const [],
    myScore: winnerIsMe ? 2 : 1,
    opponentScore: winnerIsMe ? 1 : 2,
    winnerIsMe: winnerIsMe,
    endedBy: 'normal',
    opponentName: oppName,
    opponentUid: 'u_$oppName',
    rematchAvailable: true,
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('OnlineMatchSession Rematch Lifecycle & Session Cleanup Tests', () {
    late FakeManualClock clock;
    late FakeHistoryRepo repo;
    late LifecycleTestClient client1;
    late LifecycleTestClient client2;
    late ProviderContainer container;
    late OnlineMatchSession session;

    setUp(() {
      clock = FakeManualClock(10000);
      repo = FakeHistoryRepo();
      client1 = LifecycleTestClient();
      client2 = LifecycleTestClient();

      var clientCallCount = 0;
      container = ProviderContainer(
        overrides: [
          gameClockProvider.overrideWithValue(clock),
          matchHistoryRepositoryProvider.overrideWithValue(repo),
          onlineMatchClientFactoryProvider.overrideWithValue(() {
            clientCallCount++;
            return clientCallCount == 1 ? client1 : client2;
          }),
        ],
      );
      session = container.read(onlineMatchSessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('1. Rövanş başladığında önceki oturum durumu temizlenir ve yeni maç sıfırdan başlar', () async {
      // 1. Maç başlatılır ve tamamlanır
      await session.startOnlineMatch(
        matchId: 'match_1',
        opponentName: 'Ali',
        isFriendly: false,
        client: client1,
      );

      client1.emit(OnlineMatchFinal(_createFinal('match_1', 'Ali')));

      final state1 = container.read(activeMatchUiStateProvider);
      expect(state1.lastSavedMatch, isNotNull);
      expect(state1.lastSavedMatch?.matchId, 'match_1');
      expect(state1.rematchState, equals(RematchState.idle));
      expect(state1.matchState, isNotNull);

      // Rövanş maçı başlatılır (Adım 3 akışı)
      await session.startOnlineMatch(
        matchId: 'match_2',
        opponentName: 'Ali',
        isFriendly: false,
        client: client2,
      );

      final state2 = container.read(activeMatchUiStateProvider);
      // Yeni oturumda eski maçın verileri sıfırlanmış olmalıdır
      expect(state2.lastSavedMatch, isNull);
      expect(state2.rematchState, equals(RematchState.unavailable));
      expect(state2.matchState, isNull);
      expect(state2.isLoading, isTrue);
      expect(state2.opponentName, 'Ali');
      expect(state2.isFriendly, isFalse);
    });

    test('2. Rövanş zincirinde eski maç geçmişi korunur, çift yazılmaz ve her maç ayrı kaydedilir', () async {
      // 1. Maçı oyna ve bitir
      await session.startOnlineMatch(
        matchId: 'match_round_1',
        opponentName: 'Veli',
        isFriendly: false,
        client: client1,
      );
      client1.emit(OnlineMatchFinal(_createFinal('match_round_1', 'Veli', winnerIsMe: true)));

      // 1. Maç repo'ya kaydedildi
      final saved1 = await repo.loadRecent();
      expect(saved1.length, 1);
      expect(saved1.first.matchId, 'match_round_1');
      expect(saved1.first.result, MatchResult.win);

      // 2. Rövanş maçını başlat
      await session.startOnlineMatch(
        matchId: 'match_round_2',
        opponentName: 'Veli',
        isFriendly: false,
        client: client2,
      );

      // Rövanş oynanırken eski maç kaydı hala repo'da durmalı
      final midHistory = await repo.loadRecent();
      expect(midHistory.length, 1);
      expect(midHistory.first.matchId, 'match_round_1');

      // 2. Maçı bitir (bu sefer kaybettik)
      client2.emit(OnlineMatchFinal(_createFinal('match_round_2', 'Veli', winnerIsMe: false)));

      // Her iki maç da ayrı ve eksiksiz olarak repo'da yer almalıdır
      final finalHistory = await repo.loadRecent();
      expect(finalHistory.length, 2);
      expect(finalHistory[0].matchId, 'match_round_2');
      expect(finalHistory[0].result, MatchResult.lose);
      expect(finalHistory[1].matchId, 'match_round_1');
      expect(finalHistory[1].result, MatchResult.win);
    });

    test('3. Rövanş ile açılan maçta activeMatchSessionModeProvider online olarak ayarlanır', () async {
      // Başlangıçta mod bot olsun
      container.read(activeMatchSessionModeProvider.notifier).setMode(MatchSessionMode.bot);
      expect(container.read(activeMatchSessionModeProvider), MatchSessionMode.bot);

      await session.startOnlineMatch(
        matchId: 'match_rematch_mode',
        opponentName: 'Selin',
        isFriendly: false,
        client: client1,
      );

      // startOnlineMatch otomatik olarak modu online yapar
      expect(container.read(activeMatchSessionModeProvider), MatchSessionMode.online);
    });
  });
}
