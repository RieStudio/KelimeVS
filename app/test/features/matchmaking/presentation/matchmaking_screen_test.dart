import 'package:app/features/game/domain/bot/bot_config.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/app_icon_button.dart';
import 'package:app/core/widgets/avatar_frame_registry.dart';
import 'package:app/core/widgets/match_tip_card.dart';
import 'package:app/core/widgets/player_avatar.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/main.dart';
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
    String? initialTurnPlayerId,
    BotConfig? botConfig,
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

class _TestProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  _TestProfileNotifier(this._state);

  @override
  ProfileState build() => _state;
}

Widget _buildTestApp({
  required FakeMatchController botController,
  required FakeOnlineMatchSession onlineSession,
  required FakeMatchmakingClient matchmakingClient,
  bool onlineEnabled = true,
  Duration? searchDuration,
  String? initialOpponentName,
  ProfileState? profileState,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => botController),
      onlineMatchSessionProvider.overrideWith(() => onlineSession),
      matchmakingClientFactoryProvider.overrideWithValue(
        () => matchmakingClient,
      ),
      onlineMatchmakingEnabledProvider.overrideWithValue(onlineEnabled),
      if (profileState != null)
        profileProvider.overrideWith(() => _TestProfileNotifier(profileState)),
    ],
    child: MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
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

      // Başlık ve alt yazı ("Birazdan başlıyoruz" kaldırılmıştır)
      expect(find.text(AppStrings.searchingOpponent), findsOneWidget);
      expect(find.text('Birazdan başlıyoruz'), findsNothing);

      // İpucu kartı
      expect(find.text(AppStrings.searchTipTitle), findsOneWidget);
      expect(find.byType(MatchTipCard), findsOneWidget);

      // Vazgeç butonu (kırmızı stil tokenleri: kart dolgu, danger kenarlık ve yazı, dangerShadow gölge)
      final cancelButtonFinder = find.widgetWithText(
        SecondaryButton,
        AppStrings.cancel,
      );
      expect(cancelButtonFinder, findsOneWidget);
      final cancelButton = tester.widget<SecondaryButton>(cancelButtonFinder);
      expect(cancelButton.backgroundColor, AppColors.card);
      expect(cancelButton.borderColor, AppColors.danger);
      expect(cancelButton.textColor, AppColors.danger);
      expect(cancelButton.boxShadow?.first.color, AppColors.dangerShadow);
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
      await tester.pump(const Duration(seconds: 4));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '3. MatchmakingMatched gelince min arama süresi (1500 ms) tamamlanınca rakip görünür, 2000 ms tanıtımdan sonra OnlineMatchSession ile maça geçer',
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

      // Sunucu 100 ms'de eşleşme buldu
      await tester.pump(const Duration(milliseconds: 100));
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_online_42',
          opponentName: 'Gerçek Rakip',
        ),
      );
      await tester.pump();

      // Henüz 1.5 sn dolmadığı için hala aranıyor ve "?" görünür
      expect(find.text(AppStrings.questionMark), findsOneWidget);
      expect(find.text('Gerçek Rakip'), findsNothing);
      expect(find.text(AppStrings.searchingOpponent), findsOneWidget);

      // 1.5 sn arama süresi tamamlanınca rakip adı, avatarı ve "Rakip bulundu!" görünür
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Gerçek Rakip'), findsOneWidget);
      expect(find.text(AppStrings.questionMark), findsNothing);
      expect(find.text(AppStrings.opponentFound), findsOneWidget);

      // 2000 ms tanıtım süresini ilerlet -> MatchScreen açılır ve OnlineMatchSession başlatılır
      await tester.pump(const Duration(milliseconds: 2050));
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
    '4. MatchmakingNoOpponent / Unavailable / Failed gelince hata göstermeden sessizce botlu maça düşer ve aynı arama/tanıtım süresine uyar',
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

        // Minimum arama süresi (1500 ms) tamamlanana kadar bot adı henüz açılmaz
        expect(find.text(AppStrings.questionMark), findsOneWidget);
        expect(find.text('Deniz'), findsNothing);

        await tester.pump(const Duration(milliseconds: 1550));

        // Rakip adı görünür (bot ibaresi yok) ve başlık "Rakip bulundu!" olur
        expect(find.text('Deniz'), findsOneWidget);
        expect(find.textContaining('Bot'), findsNothing);
        expect(find.text(AppStrings.questionMark), findsNothing);
        expect(find.text(AppStrings.opponentFound), findsOneWidget);

        // 2000 ms tanıtım sonrası yerel bot MatchController ile MatchScreen açılır
        await tester.pump(const Duration(milliseconds: 2050));
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
    '5. ONLINE_MATCHMAKING=false (devre kesici) iken sunucuya hiç gitmeden min arama ve tanıtım süresiyle doğrudan botlu maça geçer',
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

      // searchDuration (200 ms) geçse bile min arama süresi (1500 ms) dolmadan rakip gösterilmez
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Zeynep'), findsNothing);
      expect(find.text(AppStrings.questionMark), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Zeynep'), findsOneWidget);
      expect(find.text(AppStrings.opponentFound), findsOneWidget);

      // 2000 ms tanıtım sonrası maça geçer
      await tester.pump(const Duration(milliseconds: 2050));
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

  testWidgets(
    '7. Yığın boşken (canPop == false) Vazgeç butonuna basılınca siyah ekran yerine MainShell\'e döner',
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
            onlineMatchmakingEnabledProvider.overrideWithValue(true),
          ],
          child: const MaterialApp(
            home: MatchmakingScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MatchmakingScreen), findsOneWidget);

      // canPop == false iken Vazgeç'e bas
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Siyah ekran oluşmaz, MainShell açılır
      expect(find.byType(MatchmakingScreen), findsNothing);
      expect(find.byType(MainShell), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '8. Sistem geri hareketi (PopScope) tetiklendiğinde _cancelAndExit çalışır, client iptal edilir ve ekran kapanır',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      // Üstte bir sayfa var gibi push edilmiş MaterialApp
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchControllerProvider.overrideWith(() => botController),
            onlineMatchSessionProvider.overrideWith(() => onlineSession),
            matchmakingClientFactoryProvider.overrideWithValue(() => mmClient),
            onlineMatchmakingEnabledProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MatchmakingScreen), findsOneWidget);

      // Sistem geri hareketini simüle et
      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mmClient.cancelCalled, isTrue);
      expect(find.byType(MatchmakingScreen), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '17. Sol avatar vine çerçeveli, sağ "?" veya klasik/görsel çerçeveliyken VS iki avatarın merkezine eşit uzaklıktadır ve 360 dp altında taşmaz',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // textScale 1.3 ve 360 dp genişlik altında test et
      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          textScale: 1.3,
          profileState: const ProfileState(
            nickname: 'Arif',
            equippedFrame: 'vine',
          ),
        ),
      );
      await tester.pump();

      // Taşma (overflow) hatası yok
      expect(tester.takeException(), isNull);

      // 1. Sol vine, sağ "?" yer tutucu
      var vsCenter = tester.getCenter(find.text(AppStrings.vs));
      var leftCenter = tester.getCenter(find.byType(PlayerAvatar).first);
      var rightCenter = tester.getCenter(find.byType(PlayerAvatar).last);

      var leftDist = (vsCenter.dx - leftCenter.dx).abs();
      var rightDist = (rightCenter.dx - vsCenter.dx).abs();
      expect((leftDist - rightDist).abs(), lessThanOrEqualTo(1.0));
      expect((leftCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));
      expect((rightCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));

      // 2. Rakip bulundu: klasik çerçeveli
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'm1',
          opponentName: 'M-1234',
          opponentFrame: 'classic',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      vsCenter = tester.getCenter(find.text(AppStrings.vs));
      leftCenter = tester.getCenter(find.byType(PlayerAvatar).first);
      rightCenter = tester.getCenter(find.byType(PlayerAvatar).last);

      leftDist = (vsCenter.dx - leftCenter.dx).abs();
      rightDist = (rightCenter.dx - vsCenter.dx).abs();
      expect((leftDist - rightDist).abs(), lessThanOrEqualTo(1.0));
      expect((leftCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));
      expect((rightCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));

      // 3. Rakip bulundu: görsel çerçeveli (ör. gear)
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'm2',
          opponentName: 'M-5678',
          opponentFrame: 'gear',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      vsCenter = tester.getCenter(find.text(AppStrings.vs));
      leftCenter = tester.getCenter(find.byType(PlayerAvatar).first);
      rightCenter = tester.getCenter(find.byType(PlayerAvatar).last);

      leftDist = (vsCenter.dx - leftCenter.dx).abs();
      rightDist = (rightCenter.dx - vsCenter.dx).abs();
      expect((leftDist - rightDist).abs(), lessThanOrEqualTo(1.0));
      expect((leftCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));
      expect((rightCenter.dy - vsCenter.dy).abs(), lessThanOrEqualTo(1.0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '18. Tanıtım anında Vazgeç butonu ve üst kapat butonu gizlenir, sistem geri tuşu engellenir',
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
            onlineMatchmakingEnabledProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MatchmakingScreen(initialOpponentName: 'Deniz'),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MatchmakingScreen), findsOneWidget);

      // Arama aşamasında: Vazgeç butonu ve kapat butonu görünür, aktiftir
      expect(find.widgetWithText(SecondaryButton, AppStrings.cancel), findsOneWidget);
      expect(find.byType(AppIconButton), findsOneWidget);

      // Rakip bulundu
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_test_reveal',
          opponentName: 'Deniz',
        ),
      );
      await tester.pump();

      // Min arama süresini ilerlet ve tanıtımı başlat
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.opponentFound), findsOneWidget);

      // Tanıtım aşamasında: Vazgeç butonu ve üst kapat butonu GİZLENMİŞTİR
      expect(find.widgetWithText(SecondaryButton, AppStrings.cancel), findsNothing);
      expect(find.byType(AppIconButton), findsNothing);

      // Sistem geri hareketini (PopScope) tetikle: canPop false ve _isOpponentFound true olduğu için ekran kapanmamalıdır
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(mmClient.cancelCalled, isFalse);
      expect(find.byType(MatchmakingScreen), findsOneWidget);

      // 2 sn tanıtım tamamlanınca maça geçer
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MatchScreen), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '19. Rakip bulundu durumunda MatchTipCard yumuşak solma ile kaldırılır (findsNothing) ve "Birazdan başlıyoruz" hiçbir durumda görünmez',
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

      // 1. Arama Durumu: İpucu kartı var, "Birazdan başlıyoruz" YOK
      expect(find.byType(MatchTipCard), findsOneWidget);
      expect(find.text('Birazdan başlıyoruz'), findsNothing);

      // Rakip bulundu
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_19',
          opponentName: 'Deniz',
        ),
      );
      await tester.pump();

      // Min arama süresini tamamla ve tanıtımı başlat
      await tester.pump(const Duration(milliseconds: 1550));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text(AppStrings.opponentFound), findsOneWidget);

      // 2. Bulundu Durumu: MatchTipCard kaldırılmıştır (findsNothing), "Birazdan başlıyoruz" yine YOK
      expect(find.byType(MatchTipCard), findsNothing);
      expect(find.text('Birazdan başlıyoruz'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '20. Rakip bulundu durumunda "Sen" ve rakip adı ortak taban çizgisinde aynı dikey hizadadır, klasik çerçevede boşluk hesaplanan sabite uygundur',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          profileState: const ProfileState(
            nickname: 'Ahmet',
            equippedFrame: 'classic',
          ),
        ),
      );
      await tester.pump();

      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_20_classic',
          opponentName: 'M-1234',
          opponentFrame: 'classic',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1550));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.you), findsOneWidget);
      expect(find.text('M-1234'), findsOneWidget);

      final classicSenTop = tester.getTopLeft(find.text(AppStrings.you));
      final classicOppTop = tester.getTopLeft(find.text('M-1234'));

      // İki isim ortak taban çizgisinde tam aynı dikey hizadadır
      expect((classicSenTop.dy - classicOppTop.dy).abs(), lessThanOrEqualTo(0.5));

      // Klasik çerçevede avatar alt kenarı ile isim arası mesafe: tam AppDimens.matchmakingNameGap (8 dp)
      final leftAvatarCenter = tester.getCenter(find.byType(PlayerAvatar).first);
      final avatarCircleBottom = leftAvatarCenter.dy + (AppDimens.avatarSearch / 2.0);
      final classicGap = classicSenTop.dy - avatarCircleBottom;
      expect((classicGap - AppDimens.matchmakingNameGap).abs(), lessThanOrEqualTo(0.5));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '21. Görsel çerçevede (vine) ad ile avatar arası boşluk klasik çerçeveye göre daha geniştir',
    (tester) async {
      final botController = FakeMatchController();
      final onlineSession = FakeOnlineMatchSession();
      final mmClient = FakeMatchmakingClient();

      await tester.pumpWidget(
        _buildTestApp(
          botController: botController,
          onlineSession: onlineSession,
          matchmakingClient: mmClient,
          profileState: const ProfileState(
            nickname: 'Ahmet',
            equippedFrame: 'vine',
          ),
        ),
      );
      await tester.pump();

      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_21_vine',
          opponentName: 'M-5678',
          opponentFrame: 'classic',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1550));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.you), findsOneWidget);
      expect(find.text('M-5678'), findsOneWidget);

      final vineSenTop = tester.getTopLeft(find.text(AppStrings.you));
      final vineOppTop = tester.getTopLeft(find.text('M-5678'));

      // İki isim ortak taban çizgisinde tam aynı dikey hizadadır
      expect((vineSenTop.dy - vineOppTop.dy).abs(), lessThanOrEqualTo(0.5));

      // Sarmaşık çerçevede boşluk: çerçevenin taşma payı + AppDimens.matchmakingNameGap
      final vineAvatarCenter = tester.getCenter(find.byType(PlayerAvatar).first);
      final vineCircleBottom = vineAvatarCenter.dy + (AppDimens.avatarSearch / 2.0);
      final vineGap = vineSenTop.dy - vineCircleBottom;
      final vineOverflow = VisualFrameRegistry.getFrameOverflow(
        avatarSize: AppDimens.avatarSearch,
        frameId: 'vine',
      );
      final expectedVineGap = vineOverflow + AppDimens.matchmakingNameGap;

      expect((vineGap - expectedVineGap).abs(), lessThanOrEqualTo(0.5));
      expect(vineGap, greaterThan(AppDimens.matchmakingNameGap));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '22. Avatar satırının dikey konumu (dy) arama ve bulundu durumlarında aynıdır (tolerans <= 1 dp)',
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

      // Arama aşamasındaki avatar ve başlık dikey konumu
      final searchAvatarTop = tester.getTopLeft(find.byType(PlayerAvatar).first).dy;
      final searchTitleTop = tester.getTopLeft(find.text(AppStrings.searchingOpponent)).dy;

      // Rakip bulundu
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_22',
          opponentName: 'Deniz',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1550));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text(AppStrings.opponentFound), findsOneWidget);

      // Bulundu aşamasındaki avatar ve başlık dikey konumu
      final foundAvatarTop = tester.getTopLeft(find.byType(PlayerAvatar).first).dy;
      final foundTitleTop = tester.getTopLeft(find.text(AppStrings.opponentFound)).dy;

      // Tolerans <= 1 dp (zıplama yok)
      expect((searchAvatarTop - foundAvatarTop).abs(), lessThanOrEqualTo(1.0));
      expect((searchTitleTop - foundTitleTop).abs(), lessThanOrEqualTo(1.0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '23. Çevrim içi eşleşmede matched gelince arama süresi bitmeden vazgeç kilitlenir ve PopScope engellenir',
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
            onlineMatchmakingEnabledProvider.overrideWithValue(true),
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
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Arama aşamasında: buton aktiftir
      var cancelButton = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, AppStrings.cancel),
      );
      expect(cancelButton.onPressed, isNotNull);

      // Sunucudan matched gelir (minimum 1500 ms arama süresi bitmedi!)
      mmClient.emit(
        const MatchmakingMatched(
          matchId: 'match_lock_test',
          opponentName: 'Deniz',
        ),
      );
      await tester.pump();

      // Henüz arama aşamasında ("?" görünüyor, henüz tanıtım başlamadı)
      expect(find.text(AppStrings.questionMark), findsOneWidget);

      // BUTON KİLİTLENMİŞTİR: onPressed null, görsel olarak soluk (opacity 0.5)
      cancelButton = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, AppStrings.cancel),
      );
      expect(cancelButton.onPressed, isNull);

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.widgetWithText(SecondaryButton, AppStrings.cancel),
          matching: find.byType(AnimatedOpacity),
        ).first,
      );
      expect(animatedOpacity.opacity, 0.5);

      // Butona dokunulsa bile iptal tetiklenmez
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel), warnIfMissed: false);
      await tester.pump();
      expect(mmClient.cancelCalled, isFalse);
      expect(find.byType(MatchmakingScreen), findsOneWidget);

      // PopScope (sistem geri) tetiklense bile ekran kapanmaz
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(MatchmakingScreen), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    '24. Bot maçında arama bitene kadar vazgeç kilitlenmez ve basılınca ekran başarıyla kapanır',
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
            onlineMatchmakingEnabledProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => const MatchmakingScreen(
                        searchDuration: Duration(milliseconds: 3000),
                        initialOpponentName: 'Deniz',
                      ),
                    ),
                  );
                },
                child: const Text('OpenBot'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('OpenBot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Bot arama aşamasında: buton kilitli DEĞİLDİR, aktiftir
      final botCancelButton = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, AppStrings.cancel),
      );
      expect(botCancelButton.onPressed, isNotNull);

      // Bot maçında vazgeç basılınca ekran başarıyla kapanır
      await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MatchmakingScreen), findsNothing);
      expect(find.text('OpenBot'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
