import 'package:app/core/ads/ad_providers.dart';
import 'package:app/core/ads/ad_service.dart';
import 'package:app/core/config/ad_config.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/answer_input_bar.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OnlineNetworkNotifier extends NetworkStatusNotifier {
  @override
  NetworkState build() => const NetworkState(status: NetworkStatus.online);
}

class _TestAdConsentNotifier extends AdConsentNotifier {
  final AdConsentState _state;
  _TestAdConsentNotifier(this._state) : super(isAdsEnabledOverride: () => true);

  @override
  AdConsentState build() => _state;
}

class _TestProfileNotifier extends ProfileNotifier {
  @override
  ProfileState build() => const ProfileState(
        nickname: 'Oyuncu',
        coins: 100,
        isLoaded: true,
      );
}

class _TestMatchSession implements MatchSession {
  @override
  MatchUiState get state => const MatchUiState();
  @override
  void submit(String text) {}
  @override
  void leaveMatch() {}
  @override
  void useExtraTime() {}
  @override
  void useGiveAnswer() {}
  @override
  void dispose() {}
}

class _TestMatchSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  @override
  MatchSessionMode build() => MatchSessionMode.online;
}

class _TestMatchController extends MatchController {
  final MatchUiState _initial;
  _TestMatchController(this._initial);

  @override
  MatchUiState build() => _initial;

  void setStateForTest(MatchUiState next) {
    state = next;
  }
}

MatchUiState _activeMatchUiState({
  bool isMatchFinished = false,
  MatchFeedbackType? feedback,
  int feedbackCounter = 0,
}) {
  const q = Question(
    id: 'q1',
    categoryId: 'genel',
    text: 'Başkentimiz neresidir?',
    answers: [Answer(id: 'a1', display: 'Ankara', aliases: ['ankara'])],
  );
  return MatchUiState(
    matchState: MatchState(
      config: const MatchConfig(),
      playerIds: const ['me', 'bot'],
      scores: const {'me': 0, 'bot': 0},
      decisiveRounds: 0,
      totalRoundsPlayed: 0,
      phase: isMatchFinished ? MatchPhase.matchFinished : MatchPhase.roundActive,
      currentQuestion: q,
      usedAnswerIds: const {},
      turnPlayerId: 'me',
      deadlineMs: 0,
      remainingNearMisses: const {'me': 1, 'bot': 1},
      usedQuestionIds: const {'q1'},
      roundHistory: const [],
      currentRoundAttempts: const [],
    ),
    myPlayerId: 'me',
    opponentName: 'Rakip',
    remainingMs: 12000,
    lastFeedback: feedback,
    feedbackCounter: feedbackCounter,
  );
}

void main() {
  Widget buildMatchHost({
    required FakeAdService fakeAdService,
    required MatchUiState uiState,
    _TestMatchController? controllerOverride,
    Size screenSize = const Size(412, 915),
    EdgeInsets viewInsets = EdgeInsets.zero,
    bool? isAdsEnabledOverride = true,
  }) {
    final controller = controllerOverride ?? _TestMatchController(uiState);
    return ProviderScope(
      key: controllerOverride == null ? UniqueKey() : null,
      overrides: [
        adServiceProvider.overrideWithValue(fakeAdService),
        networkStatusProvider.overrideWith(_OnlineNetworkNotifier.new),
        adConsentProvider.overrideWith(
          () => _TestAdConsentNotifier(
            const AdConsentState(
              isConsentChecked: true,
              canRequestAds: true,
              isSdkInitialized: true,
            ),
          ),
        ),
        profileProvider.overrideWith(_TestProfileNotifier.new),
        activeMatchSessionModeProvider.overrideWith(
          _TestMatchSessionModeNotifier.new,
        ),
        matchControllerProvider.overrideWith(() => controller),
        activeMatchUiStateProvider
            .overrideWith((ref) => ref.watch(matchControllerProvider)),
        activeMatchSessionProvider.overrideWithValue(_TestMatchSession()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screenSize, viewInsets: viewInsets),
          child: MatchScreen(isAdsEnabledOverride: isAdsEnabledOverride),
        ),
      ),
    );
  }

  testWidgets(
      'banner hazırken görünür kutu çizgisinin tam 24 dp üstünde durur (klavye açık/kapalı) ve çıkınca dispose edilir',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeAd = FakeAdService(
      initialInMatchBannerLoaded: true,
      initialBannerLoaded: true,
    );
    final controller = _TestMatchController(_activeMatchUiState());

    // 1. Klavye kapalıyken tam 24 dp
    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(),
        controllerOverride: controller,
      ),
    );
    await tester.pump();

    final bannerSlot = find.byKey(const Key('in_match_banner_slot'));
    final inputBox = find.byKey(const Key('answer_input_box'));
    expect(bannerSlot, findsOneWidget);
    expect(
      find.byKey(const Key('fake_in_match_banner_ad_widget')),
      findsOneWidget,
    );

    final bannerRectClosed = tester.getRect(bannerSlot);
    final inputBoxRectClosed = tester.getRect(inputBox);
    expect(bannerRectClosed.height, AdConfig.inMatchBannerHeight);
    expect(
      inputBoxRectClosed.top - bannerRectClosed.bottom,
      closeTo(AdConfig.inMatchBannerBottomGap, 0.01),
    );

    // 2. Klavye açıkken de tam 24 dp
    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(),
        controllerOverride: controller,
        viewInsets: const EdgeInsets.only(bottom: 280),
      ),
    );
    await tester.pump();

    final bannerRectOpen = tester.getRect(bannerSlot);
    final inputBoxRectOpen = tester.getRect(inputBox);
    expect(
      inputBoxRectOpen.top - bannerRectOpen.bottom,
      closeTo(AdConfig.inMatchBannerBottomGap, 0.01),
    );

    // Maçtan çıkınca yalnızca in-match banner dispose edilir, MainShell banner'ı etkilenmez
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(fakeAd.disposeInMatchBannerCallCount, 1);
    expect(fakeAd.isBannerLoadedListenable.value, isTrue);
  });

  testWidgets(
      'geri bildirim gösterilince banner yerinden oynamaz ve geri bildirim görünür kalır',
      (tester) async {
    final fakeAd = FakeAdService(initialInMatchBannerLoaded: true);
    final controller = _TestMatchController(_activeMatchUiState());

    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(),
        controllerOverride: controller,
      ),
    );
    await tester.pump();

    final bannerBefore =
        tester.getRect(find.byKey(const Key('in_match_banner_slot')));
    final boxBefore =
        tester.getRect(find.byKey(const Key('answer_input_box')));

    controller.setStateForTest(
      _activeMatchUiState(
        feedback: MatchFeedbackType.wrong,
        feedbackCounter: 1,
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.wrongAnswer), findsOneWidget);
    final bannerAfter =
        tester.getRect(find.byKey(const Key('in_match_banner_slot')));
    final boxAfter =
        tester.getRect(find.byKey(const Key('answer_input_box')));
    final feedbackRect = tester.getRect(find.text(AppStrings.wrongAnswer));

    expect(bannerAfter, bannerBefore);
    expect(boxAfter, boxBefore);
    expect(feedbackRect.bottom, lessThanOrEqualTo(bannerAfter.top));
  });

  testWidgets(
      'banner hazır değilse çizilmez ve sonradan yüklense bile maç ortasında görünmez',
      (tester) async {
    final fakeAd = FakeAdService(initialInMatchBannerLoaded: false);

    await tester.pumpWidget(
      buildMatchHost(fakeAdService: fakeAd, uiState: _activeMatchUiState()),
    );
    await tester.pump();

    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);

    // Maç sırasında geç yüklense bile karar kilitli olduğundan yer açılmaz
    fakeAd.setInMatchBannerLoaded(true);
    await tester.pump();

    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);
  });

  testWidgets('düşük yükseklikli ekranda (<760 dp) banner otomatik gizlenir',
      (tester) async {
    final fakeAd = FakeAdService(initialInMatchBannerLoaded: true);

    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(),
        screenSize: const Size(360, 680),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);
  });

  testWidgets('ads kapalıyken banner hiç çizilmez', (tester) async {
    final fakeAd = FakeAdService(initialInMatchBannerLoaded: true);

    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(),
        isAdsEnabledOverride: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);
  });

  testWidgets(
      'Maç sonu (MatchEndView) ve eşleşme (MatchmakingScreen) ekranlarında in-match banner yoktur',
      (tester) async {
    final fakeAd = FakeAdService(initialInMatchBannerLoaded: true);

    await tester.pumpWidget(
      buildMatchHost(
        fakeAdService: fakeAd,
        uiState: _activeMatchUiState(isMatchFinished: true),
      ),
    );
    await tester.pump();

    expect(find.byType(MatchEndView), findsOneWidget);
    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          adServiceProvider.overrideWithValue(fakeAd),
          networkStatusProvider.overrideWith(_OnlineNetworkNotifier.new),
          profileProvider.overrideWith(_TestProfileNotifier.new),
        ],
        child: const MaterialApp(
          home: MatchmakingScreen(forceBotFallback: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('in_match_banner_slot')), findsNothing);
  });
}
