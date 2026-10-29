import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/match_tip_card.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/matchmaking_client.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';

class FakeMatchmakingClient extends MatchmakingClient {
  final StreamController<MatchmakingEvent> controller =
      StreamController<MatchmakingEvent>.broadcast(sync: true);

  bool startCalled = false;
  String? startedWithName;
  bool cancelCalled = false;

  @override
  Stream<MatchmakingEvent> get events => controller.stream;

  @override
  Future<void> start(String name) async {
    startCalled = true;
    startedWithName = name;
    controller.add(const MatchmakingConnecting());
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    if (!controller.isClosed) {
      controller.add(const MatchmakingCancelled());
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await controller.close();
  }

  void emit(MatchmakingEvent event) {
    controller.add(event);
  }
}

class FakeMatchController extends MatchController {
  String? startedWithOpponentName;
  bool startMatchCalled = false;

  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
  }) async {
    startMatchCalled = true;
    startedWithOpponentName = opponentName;
    state = state.copyWith(opponentName: opponentName ?? '', isLoading: true);
  }
}

class FakeOnlineMatchSession extends OnlineMatchSession {
  String? startedWithMatchId;
  String? startedWithOpponentName;
  bool startOnlineMatchCalled = false;

  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    String opponentFrame = 'classic',
    bool isFriendly = false,
    OnlineMatchClient? client,
  }) async {
    startOnlineMatchCalled = true;
    startedWithMatchId = matchId;
    startedWithOpponentName = opponentName;
    state = state.copyWith(opponentName: opponentName, isLoading: true);
  }
}

Widget _buildTestApp({
  required FakeMatchController botController,
  required FakeOnlineMatchSession onlineSession,
  required FakeMatchmakingClient matchmakingClient,
  bool onlineEnabled = true,
  Duration? searchDuration,
  String? initialOpponentName,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => botController),
      onlineMatchSessionProvider.overrideWith(() => onlineSession),
      matchmakingClientFactoryProvider.overrideWithValue(
        () => matchmakingClient,
      ),
      onlineMatchmakingEnabledProvider.overrideWithValue(onlineEnabled),
    ],
    child: MaterialApp(
      home: MatchmakingScreen(
        searchDuration: searchDuration,
        initialOpponentName: initialOpponentName,
      ),
    ),
  );
}

void main() {
  testWidgets(
    '1. Eşleşme ekranı başlangıç durumu: avatarlar, başlık, ipucu, vazgeç butonu ve MatchmakingClient.start çağrısı',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          initialOpponentName: 'Deniz',
        ),
      );
      await tester.pump();

      expect(mmClient.startCalled, isTrue);
      expect(mmClient.startedWithName, AppStrings.defaultPlayerName);

      // Kendi avatarı ve bilinmeyen rakip avatarı
      expect(find.text('S'), findsOneWidget);
      expect(find.text(AppStrings.vs), findsOneWidget);
      expect(find.text(AppStrings.questionMark), findsOneWidget);

      // Başlık ve alt yazı
      expect(find.text(AppStrings.searchingOpponent), findsOneWidget);
      expect(find.text(AppStrings.startingSoon), findsOneWidget);

      // İpucu kartı
      expect(find.text(AppStrings.searchTipTitle), findsOneWidget);
      expect(find.byType(MatchTipCard), findsOneWidget);

      // Vazgeç butonu
      expect(
        find.widgetWithText(SecondaryButton, AppStrings.cancel),
        findsOneWidget,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '2. Vazgeç butonuna basıldığında MatchmakingClient.cancel çağrılır, zamanlayıcılar iptal edilir ve ekran kapanır',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchControllerProvider.overrideWith(() => botController),
            onlineMatchSessionProvider.overrideWith(() => onlineSession),
            matchmakingClientFactoryProvider.overrideWithValue(() => mmClient),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const MatchmakingScreen(initialOpponentName: 'Deniz'),
                    ),
                  );
                },
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );

      // Ekranı aç
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MatchmakingScreen), findsOneWidget);
      expect(mmClient.startCalled, isTrue);

      // Vazgeç butonuna bas
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(mmClient.cancelCalled, isTrue);
      expect(find.byType(MatchmakingScreen), findsNothing);
      expect(find.text('Go'), findsOneWidget);
      expect(botController.startMatchCalled, isFalse);
      expect(onlineSession.startOnlineMatchCalled, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '3. MatchmakingMatched gelince rakip avatarı/adı görünür, 800 ms sonra OnlineMatchSession ile maça geçer',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          initialOpponentName: 'Deniz',
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.questionMark), findsOneWidget);
      expect(find.text('Gerçek Rakip'), findsNothing);

      // Sunucu eşleşme buldu
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_online_42',
          opponentName: 'Gerçek Rakip',
        ),
      );
      await tester.pump();

      // Rakip adı ve avatarı ekranda
      expect(find.text('Gerçek Rakip'), findsOneWidget);
      expect(find.text(AppStrings.questionMark), findsNothing);

      // 800 ms geçiş süresini ilerlet -> MatchScreen açılır ve OnlineMatchSession başlatılır
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MatchScreen), findsOneWidget);
      expect(onlineSession.startOnlineMatchCalled, isTrue);
      expect(onlineSession.startedWithMatchId, 'match_online_42');
      expect(onlineSession.startedWithOpponentName, 'Gerçek Rakip');
      expect(botController.startMatchCalled, isFalse);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MatchScreen)),
      );
      expect(
        container.read(activeMatchSessionModeProvider),
        MatchSessionMode.online,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '4. MatchmakingNoOpponent / Unavailable / Failed gelince hata göstermeden sessizce botlu maça düşer',
    (tester) async {
      for (final fallbackEvent in <MatchmakingEvent>[
        const MatchmakingNoOpponent(),
        const MatchmakingUnavailable('content_unavailable'),
        const MatchmakingFailed('network_error'),
      ]) {
        final botController = FakeMatchController();
        final onlineSession = FakeOnlineMatchSession();
        final mmClient = FakeMatchmakingClient();

        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(fallbackEvent.runtimeType),
            overrides: [
              matchControllerProvider.overrideWith(() => botController),
              onlineMatchSessionProvider.overrideWith(() => onlineSession),
              matchmakingClientFactoryProvider.overrideWithValue(
                () => mmClient,
              ),
            ],
            child: const MaterialApp(
              home: MatchmakingScreen(initialOpponentName: 'Deniz'),
            ),
          ),
        );
        await tester.pump();

        // Olayı tetikle
        mmClient.emit(fallbackEvent);
        await tester.pump();

        // Rakip adı görünür (bot ibaresi yok)
        expect(find.text('Deniz'), findsOneWidget);
        expect(find.textContaining('Bot'), findsNothing);
        expect(find.text(AppStrings.questionMark), findsNothing);

        // 800 ms sonra yerel bot MatchController ile MatchScreen açılır
        await tester.pump(const Duration(milliseconds: 850));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(MatchScreen), findsOneWidget);
        expect(botController.startMatchCalled, isTrue);
        expect(botController.startedWithOpponentName, 'Deniz');
        expect(onlineSession.startOnlineMatchCalled, isFalse);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MatchScreen)),
        );
        expect(
          container.read(activeMatchSessionModeProvider),
          MatchSessionMode.bot,
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '5. ONLINE_MATCHMAKING=false (devre kesici) iken sunucuya hiç gitmeden doğrudan botlu maça geçer',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          onlineEnabled: false,
          searchDuration: const Duration(milliseconds: 200),
          initialOpponentName: 'Zeynep',
        ),
      );
      await tester.pump();

      // Sunucu istemcisi hiç başlatılmamalı
      expect(mmClient.startCalled, isFalse);

      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Zeynep'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MatchScreen), findsOneWidget);
      expect(botController.startMatchCalled, isTrue);
      expect(botController.startedWithOpponentName, 'Zeynep');
      expect(onlineSession.startOnlineMatchCalled, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '6. MatchmakingMatched mesajında energy geldiğinde profileProvider enerjiyi anında günceller',
    (tester) async {
      final mmClient = FakeMatchmakingClient();
      final container = ProviderContainer(
        overrides: [
          matchmakingClientFactoryProvider.overrideWithValue(() => mmClient),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MatchmakingScreen()),
        ),
      );
      await tester.pump();

      // Başlangıçta enerji 5
      container
          .read(profileProvider.notifier)
          .updateEnergy(const EnergyState(enabled: true, current: 5, max: 5));
      expect(container.read(profileProvider).energy?.current, 5);

      // Sunucudan matched mesajı ve güncel enerji (4) gelir
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_999',
          opponentName: 'Ahmet',
          opponentFrame: 'gold',
          energy: MatchedEnergyInfo(
            current: 4,
            max: 5,
            nextEnergyAtMs: 1729556400000,
          ),
          serverNowMs: 1729555200000,
        ),
      );
      await tester.pump();

      // Profil durumu anında 4'e güncellenmeli
      final profile = container.read(profileProvider);
      expect(profile.energy, isNotNull);
      expect(profile.energy!.current, 4);
      expect(profile.energy!.max, 5);
      expect(profile.energy!.nextEnergyAtMs, 1729556400000);
      expect(profile.serverNowMs, 1729555200000);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'İpucu kartı: initState içinde bir kez seçilir ve ekran rebuild olduğunda değişmez',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          searchDuration: const Duration(seconds: 30),
        ),
      );
      await tester.pump();

      final tipCardFinder = find.byType(MatchTipCard);
      expect(tipCardFinder, findsOneWidget);
      final tipBefore = tester.widget<MatchTipCard>(tipCardFinder).tip;
      expect(tipBefore, isNotEmpty);

      // Nokta animasyonunun tetiklediği setState rebuild'leri
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      final tipAfter = tester.widget<MatchTipCard>(tipCardFinder).tip;
      expect(tipAfter, equals(tipBefore));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
