import 'dart:async';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/friend_match/presentation/friend_reveal_screen.dart';
import 'package:app/features/match_request/application/match_requests_notifier.dart';
import 'package:app/features/match_request/application/match_requests_providers.dart';
import 'package:app/features/match_request/application/presence_controller.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:app/features/match_request/presentation/global_match_request_overlay.dart';
import 'package:app/features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import 'package:app/features/match_request/presentation/widgets/outgoing_match_request_chip.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockOnlineMatchSession extends OnlineMatchSession {
  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    String? opponentUid,
    String opponentFrame = 'classic',
    bool isFriendly = false,
    OnlineMatchClient? client,
  }) async {}
}

class TestProfileNotifier extends ProfileNotifier {
  final ProfileState _initialState;

  TestProfileNotifier([ProfileState? state])
      : _initialState = state ??
            const ProfileState(
              nickname: 'TestUser',
              coins: 100,
              energy: EnergyState(enabled: true, current: 5, max: 5),
            );

  @override
  ProfileState build() => _initialState;

  @override
  Future<bool> syncWithServer({bool force = false}) async => true;
}

void main() {
  group('GlobalMatchRequestOverlay Widget Tests', () {
    testWidgets('gelen istek olduğunda üstte bildirim bandı gösterilir', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final req = IncomingMatchRequest(
        id: 'in_1',
        fromUid: 'u_1',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(incoming: req);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IncomingMatchRequestBanner), findsOneWidget);
      expect(find.text(AppStrings.matchRequestTitleProfile('Ahmet')), findsOneWidget);
    });

    testWidgets('giden istek olduğunda üstte kompakt çip gösterilir', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final outReq = OutgoingMatchRequest(
        id: 'out_1',
        toUid: 'u_2',
        toNickname: 'Zeynep',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(outgoing: outReq);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OutgoingMatchRequestChip), findsOneWidget);
      expect(find.text(AppStrings.matchRequestOutgoingChip('Zeynep', 45)), findsOneWidget);
    });

    testWidgets('hem gelen hem giden istek varken ikisi de alt alta gösterilir', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final req = IncomingMatchRequest(
        id: 'in_1',
        fromUid: 'u_1',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      final outReq = OutgoingMatchRequest(
        id: 'out_1',
        toUid: 'u_2',
        toNickname: 'Zeynep',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(incoming: req, outgoing: outReq);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IncomingMatchRequestBanner), findsOneWidget);
      expect(find.byType(OutgoingMatchRequestChip), findsOneWidget);
    });

    testWidgets('kullanıcı busy iken gelen ve giden istekler bastırılır (görünmez)',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final req = IncomingMatchRequest(
        id: 'in_1',
        fromUid: 'u_1',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(incoming: req);

      // Meşgul duruma geç
      container.read(presenceControllerProvider.notifier).acquireBusy('in_match');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Meşgulken banner gösterilmemeli
      expect(find.byType(IncomingMatchRequestBanner), findsNothing);
    });

    testWidgets('kullanıcı henüz takma ad seçmemişken (onboarding) istekler bastırılır',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(
            () => TestProfileNotifier(
              const ProfileState(nickname: ''),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final req = IncomingMatchRequest(
        id: 'in_1',
        fromUid: 'u_1',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(incoming: req);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IncomingMatchRequestBanner), findsNothing);
    });

    testWidgets('giden istek reddedildiğinde danger tostu gösterilir ve tek seferlik tüketilir',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reddedildi durumu gelsin
      container.read(matchRequestsProvider.notifier).state =
          const MatchRequestsState(
        lastEndStatus: MatchRequestEndStatusInfo(
          id: 'out_1',
          status: MatchRequestEndStatus.declined,
          isOutgoing: true,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.matchRequestDeclinedToast), findsOneWidget);

      // Durum temizlenmiş olmalı (tek seferlik tüketim)
      expect(container.read(matchRequestsProvider).lastEndStatus, isNull);
    });

    testWidgets('giden istek süresi dolduğunda yanıtsız kaldı tostu gösterilir',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(matchRequestsProvider.notifier).state =
          const MatchRequestsState(
        lastEndStatus: MatchRequestEndStatusInfo(
          id: 'out_1',
          status: MatchRequestEndStatus.expired,
          isOutgoing: true,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.matchRequestExpiredToast), findsOneWidget);
    });

    testWidgets('kullanıcı kendi isteğini iptal ettiğinde tost gösterilmez',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(matchRequestsProvider.notifier).state =
          const MatchRequestsState(
        lastEndStatus: MatchRequestEndStatusInfo(
          id: 'out_1',
          status: MatchRequestEndStatus.cancelled,
          isOutgoing: true,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.matchRequestDeclinedToast), findsNothing);
      expect(find.text(AppStrings.matchRequestExpiredToast), findsNothing);
    });

    testWidgets('noEnergy hatası geldiğinde EnergyDepletedBottomSheet açılır',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(
            () => TestProfileNotifier(
              const ProfileState(
                nickname: 'TestUser',
                coins: 50,
                energy: EnergyState(enabled: true, current: 0, max: 5),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(matchRequestsProvider.notifier).state =
          const MatchRequestsState(
        lastError: MatchRequestErrorInfo(
          code: MatchRequestErrorCode.noEnergy,
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(EnergyDepletedBottomSheet), findsOneWidget);
    });

    testWidgets('cooldownActive hatasında kalan süreli tost gösterilir', (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) =>
                GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(matchRequestsProvider.notifier).state =
          const MatchRequestsState(
        lastError: MatchRequestErrorInfo(
          code: MatchRequestErrorCode.cooldownActive,
          retryAfterSec: 25,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(AppStrings.matchRequestCooldownToast(25)), findsOneWidget);
    });

    testWidgets('matched olayı geldiğinde FriendMatchRevealScreen açılır ve dialogları kapatır',
        (tester) async {
      final matchedController = StreamController<MatchedEvent>.broadcast();
      addTearDown(matchedController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => TestProfileNotifier()),
            matchedEventsProvider.overrideWith((ref) => matchedController.stream),
            onlineMatchSessionProvider.overrideWith(MockOnlineMatchSession.new),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => GlobalMatchRequestOverlay(
              revealDurationForTesting: const Duration(seconds: 10),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: ctx,
                      builder: (_) => const AlertDialog(title: Text('OpenDialog')),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bir diyalog açalım
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('OpenDialog'), findsOneWidget);

      // matched olayı yay
      matchedController.add(
        const MatchedEvent(
          matchId: 'match_999',
          opponentName: 'Deniz',
          opponentFrame: 'mint',
          opponentUid: 'u_deniz',
          isFriendly: false,
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Diyalog kapatılmış ve FriendMatchRevealScreen açılmış olmalı!
      expect(find.text('OpenDialog'), findsNothing);
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      expect(find.text('Deniz'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('aynı matchId için mükerrer navigasyon engellenir', (tester) async {
      final matchedController = StreamController<MatchedEvent>.broadcast();
      addTearDown(matchedController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => TestProfileNotifier()),
            matchedEventsProvider.overrideWith((ref) => matchedController.stream),
            onlineMatchSessionProvider.overrideWith(MockOnlineMatchSession.new),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => GlobalMatchRequestOverlay(
              revealDurationForTesting: const Duration(seconds: 10),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Matched olayı
      matchedController.add(
        const MatchedEvent(
          matchId: 'match_dup_1',
          opponentName: 'Deniz',
          opponentFrame: 'mint',
          opponentUid: 'u_deniz',
          isFriendly: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);

      // 2. Mükerrer matched olayı (aynı matchId)
      matchedController.add(
        const MatchedEvent(
          matchId: 'match_dup_1',
          opponentName: 'Deniz',
          opponentFrame: 'mint',
          opponentUid: 'u_deniz',
          isFriendly: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Ekran hala 1 tane olmalı, çift push olmamalı
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reduce motion devredeyken (disableAnimations: true) animasyonsuz doğrudan render eder',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => TestProfileNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final req = IncomingMatchRequest(
        id: 'in_motion',
        fromUid: 'u_1',
        fromNickname: 'Kemal',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      container.read(matchRequestsProvider.notifier).state =
          MatchRequestsState(incoming: req);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              builder: (context, child) =>
                  GlobalMatchRequestOverlay(child: child ?? const SizedBox.shrink()),
              home: const Scaffold(body: Text('Home')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(IncomingMatchRequestBanner), findsOneWidget);
      expect(find.text(AppStrings.matchRequestTitleProfile('Kemal')), findsOneWidget);
    });
  });
}
