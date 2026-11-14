import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/config/app_config.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/match_result_icon.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/game/application/match_session.dart';

class _TestSessionModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode _mode;
  _TestSessionModeNotifier(this._mode);
  @override
  MatchSessionMode build() => _mode;
}

class FakeMatchController extends MatchController {
  final MatchUiState _initialState;
  bool startMatchCalled = false;

  FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
    String? initialTurnPlayerId,
    BotConfig? botConfig,
    String? preselectedQuestionId,
    List<String>? questionOrder,
  }) async {
    startMatchCalled = true;
  }
}

Widget _buildTestApp(
  FakeMatchController controller, {
  bool disableAnimations = false,
  NavigatorObserver? navigatorObserver,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(
      navigatorObservers: navigatorObserver != null ? [navigatorObserver] : [],
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(
          body: MatchEndView(),
        ),
      ),
    ),
  );
}

void main() {
  const testQuestion = Question(
    id: 'q_test_1',
    categoryId: 'hayvanlar',
    text: 'B ile başlayan hayvanlar',
    answers: [],
  );

  MatchState createMatchState({
    required Map<String, int> scores,
    required String winnerId,
    String? endedBy = 'normal',
  }) {
    return MatchState(
      config: const MatchConfig(totalDecisiveRounds: 3, answerSeconds: 15),
      playerIds: const ['me', 'bot'],
      scores: scores,
      decisiveRounds: scores.values.fold(0, (a, b) => a + b),
      totalRoundsPlayed: 3,
      phase: MatchPhase.matchFinished,
      currentQuestion: testQuestion,
      endedBy: endedBy,
      usedAnswerIds: const {},
      turnPlayerId: 'me',
      deadlineMs: 20000,
      remainingNearMisses: const {'me': 1, 'bot': 1},
      usedQuestionIds: const {'q_test_1'},
      currentRoundAttempts: const [],
      roundHistory: const [],
      winnerId: winnerId,
    );
  }

  testWidgets('1. Maç kazanıldığında (win): match_win.svg ikonu, "Kazandın!", +30 jeton, skor doğru', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      coinsAwarded: AppConfig.matchWinCoinReward,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // MatchResultIcon: win varyantı, match_win.svg
    final iconFinder = find.byType(MatchResultIcon);
    expect(iconFinder, findsOneWidget);
    final icon = tester.widget<MatchResultIcon>(iconFinder);
    expect(icon.variant, MatchResultVariant.win);
    expect(icon.assetPath, MatchResultIcon.winAsset);

    // Başlık
    expect(find.text(AppStrings.wonExclamation), findsOneWidget);

    // Skor satırı: "Sen", "2 – 1", "Ahmet"
    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
    expect(find.text('Ahmet'), findsOneWidget);

    // Jeton ödülü kartı (+30 jeton)
    expect(
      find.text('+${AppConfig.matchWinCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );

    // Terk notu olmamalı
    expect(find.text(AppStrings.opponentLeftMatch), findsNothing);
    expect(find.text(AppStrings.youLeftMatch), findsNothing);
  });

  testWidgets('2. Maç kaybedildiğinde (lose): match_lose.svg ikonu, "Kaybettin", +10 jeton, skor doğru', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 2},
      winnerId: 'bot',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      coinsAwarded: AppConfig.matchLoseCoinReward,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    // MatchResultIcon: lose varyantı, match_lose.svg
    final iconFinder = find.byType(MatchResultIcon);
    expect(iconFinder, findsOneWidget);
    final icon = tester.widget<MatchResultIcon>(iconFinder);
    expect(icon.variant, MatchResultVariant.lose);
    expect(icon.assetPath, MatchResultIcon.loseAsset);

    // Başlık (ünlemsiz)
    expect(find.text(AppStrings.lost), findsOneWidget);

    // Skor satırı
    expect(find.text('1${AppStrings.scoreDash}2'), findsOneWidget);

    // Jeton ödülü kartı (+10 jeton)
    expect(
      find.text('+${AppConfig.matchLoseCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('3. Rakip terk ettiğinde (forfeit win): "Rakip maçtan ayrıldı" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      endedBy: 'forfeit',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      coinsAwarded: AppConfig.matchWinCoinReward,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
    expect(find.text(AppStrings.opponentLeftMatch), findsOneWidget);
    expect(
      find.text('+${AppConfig.matchWinCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('4. Ben terk ettiğimde (forfeit lose): "Maçı terk ettin" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 0, 'bot': 0},
      winnerId: 'bot',
      endedBy: 'forfeit',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      coinsAwarded: AppConfig.matchLoseCoinReward,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lost), findsOneWidget);
    expect(find.text(AppStrings.youLeftMatch), findsOneWidget);
    expect(
      find.text('+${AppConfig.matchLoseCoinReward}${AppStrings.coinSuffix}'),
      findsOneWidget,
    );
  });

  testWidgets('5. "Tekrar Oyna" butonuna tıklandığında MatchmakingScreen açılır', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.byType(MatchmakingScreen), findsNothing);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.playAgain));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MatchmakingScreen), findsOneWidget);
  });

  testWidgets('6. "Maç Detayı" butonu ekranda ikincil buton olarak bulunur', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SecondaryButton, AppStrings.matchDetail), findsOneWidget);
  });

  testWidgets('7. Kapat ikonu tıklandığında Navigator.pop çalışır', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MatchEndView(),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Open MatchEndView
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchEndView), findsOneWidget);

    // Tap Close icon button
    await tester.tap(find.bySemanticsLabel(AppStrings.close));
    await tester.pumpAndSettle();

    expect(find.byType(MatchEndView), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('8. disableAnimations aktifken FadeTransition olmadan doğrudan çizilir', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller, disableAnimations: true));

    expect(
      find.descendant(
        of: find.byType(MatchEndView),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
  });

  testWidgets('9. baglantiKoptu durumunda: "Bağlantın koptu" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 0, 'bot': 0},
      winnerId: 'bot',
      endedBy: 'forfeit',
    );
    final historyEntry = MatchHistoryEntry(
      id: 'm_disc_test',
      matchId: 'm_disc_test',
      opponentName: 'Ahmet',
      finishedAtMs: 1000,
      myScore: 0,
      opponentScore: 0,
      result: MatchResult.lose,
      endType: MatchEndType.forfeit,
      endReason: MatchEndReason.baglantiKoptu,
      roundRecords: const [],
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      lastSavedMatch: historyEntry,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lost), findsOneWidget);
    expect(find.text(AppStrings.yourConnectionLost), findsOneWidget);
  });

  testWidgets('10. rakipBaglantiKoptu durumunda: "Rakibin bağlantısı koptu" notu görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 0},
      winnerId: 'me',
      endedBy: 'forfeit',
    );
    final historyEntry = MatchHistoryEntry(
      id: 'm_opp_disc_test',
      matchId: 'm_opp_disc_test',
      opponentName: 'Ahmet',
      finishedAtMs: 1000,
      myScore: 1,
      opponentScore: 0,
      result: MatchResult.win,
      endType: MatchEndType.forfeit,
      endReason: MatchEndReason.rakipBaglantiKoptu,
      roundRecords: const [],
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
      lastSavedMatch: historyEntry,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
    expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);
  });

  testWidgets('11. Normal galibiyet (rakip süre aşımı): "Rakibin süresi doldu" alt satır olarak görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 0},
      winnerId: 'me',
    ).copyWith(
      roundHistory: [
        const RoundRecord(
          questionId: 'q_test_1',
          starterPlayerId: 'me',
          attempts: [],
          winnerId: 'me',
          reason: RoundEndReason.timeout,
        ),
      ],
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
    expect(find.text(AppStrings.reasonOpponentTimeout), findsOneWidget);
  });

  testWidgets('12. Normal mağlubiyet (kendi süre aşımım): "Süren doldu" alt satır olarak görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 0, 'bot': 2},
      winnerId: 'bot',
    ).copyWith(
      roundHistory: [
        const RoundRecord(
          questionId: 'q_test_1',
          starterPlayerId: 'me',
          attempts: [],
          winnerId: 'bot',
          reason: RoundEndReason.timeout,
        ),
      ],
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lost), findsOneWidget);
    expect(find.text(AppStrings.reasonMyTimeout), findsOneWidget);
  });

  testWidgets('13. Tur sınırına ulaşıldığında (5. tur berabere, skor üstünlüğüyle bitiş): "Tur sınırına ulaşıldı" görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    ).copyWith(
      totalRoundsPlayed: 5,
      roundHistory: [
        const RoundRecord(
          questionId: 'q_test_1',
          starterPlayerId: 'me',
          attempts: [],
          winnerId: null,
          reason: RoundEndReason.exhausted,
        ),
      ],
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Ahmet',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.wonExclamation), findsOneWidget);
    expect(find.text(AppStrings.reasonRoundLimitReached), findsOneWidget);
  });

  testWidgets('14. Online ranked maçta final henüz gelmemişken jeton kartı gizlidir, takılma olmaz', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 0},
      winnerId: 'me',
    );
    final historyEntry = MatchHistoryEntry(
      id: 'm_online_ranked_test',
      matchId: 'm_online_ranked_test',
      opponentName: 'Zeynep',
      finishedAtMs: 1000,
      myScore: 2,
      opponentScore: 0,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      endReason: MatchEndReason.normal,
      roundRecords: const [],
      botlaOynandi: false,
      isFriendly: false,
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'Zeynep',
      lastSavedMatch: historyEntry,
      coinsAwarded: null, // Henüz sunucudan final gelmedi
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
          activeMatchSessionModeProvider.overrideWith(
            () => _TestSessionModeNotifier(MatchSessionMode.online),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MatchEndView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label?.startsWith('Jeton ödülü') == true,
      ),
      findsNothing,
    );
  });

  testWidgets('15. Skor satırında bot adı (M-1234) başarıyla görünür', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'M-1234',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
    expect(find.text('M-1234'), findsOneWidget);
  });

  testWidgets('16. Skor satırında uzun ad (20 karakter) görünür ve FittedBox ile sığdırılır', (tester) async {
    const longName = 'MustafaKemalettin123'; // 20 karakter
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 0},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: longName,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('17. Rakip adı boş veya sadece boşluklardan oluştuğunda "Rakip" fallback etiketi kullanılır', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 1, 'bot': 2},
      winnerId: 'bot',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: '   ',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('1${AppStrings.scoreDash}2'), findsOneWidget);
    expect(find.text(AppStrings.opponent), findsOneWidget);
  });

  testWidgets('18. 360 dp ekranda ve 1.3 yazı ölçeğinde M-9999 ile sıfır taşma oluşur ve didExceedMaxLines false kalır', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'M-9999',
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final mFinder = find.text('M-9999');
    expect(mFinder, findsOneWidget);

    final renderParagraph = tester.renderObject<RenderParagraph>(mFinder);
    expect(renderParagraph.didExceedMaxLines, isFalse);
  });

  testWidgets('19. 360 dp ekranda ve 1.3 yazı ölçeğinde uzun ad (20 karakter) ile sıfır taşma oluşur', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const longName = 'MustafaKemalettin123'; // 20 karakter
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: longName,
    );
    final controller = FakeMatchController(uiState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: MatchEndView(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(longName), findsOneWidget);
  });

  testWidgets('20. Online maçta rakip kartı ve Engelle butonu bulunmaz (findsNothing); skor, jeton bilgisi, Tekrar Oyna ve Maç Detayı bulunur', (tester) async {
    final matchState = createMatchState(
      scores: {'me': 2, 'bot': 1},
      winnerId: 'me',
    );
    final historyEntry = MatchHistoryEntry(
      id: 'online_123',
      matchId: 'match_server_123',
      opponentName: 'CanliRakip',
      finishedAtMs: 1000,
      myScore: 2,
      opponentScore: 1,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      roundRecords: const [],
      botlaOynandi: false, // Online maç
    );
    final uiState = MatchUiState(
      matchState: matchState,
      opponentName: 'CanliRakip',
      lastSavedMatch: historyEntry,
      coinsAwarded: 30,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMatchUiStateProvider.overrideWithValue(uiState),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MatchEndView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rakip kartı ve Engelle butonu kaldırıldı -> ASLA bulunmaz
    expect(find.text(AppStrings.blockAction), findsNothing);
    expect(find.text(AppStrings.blockedStatus), findsNothing);
    expect(find.text('Bildir'), findsNothing);

    // Skor, jeton ödülü, Tekrar Oyna ve Maç Detayı butonları bulunur
    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('2${AppStrings.scoreDash}1'), findsOneWidget);
    expect(find.text('CanliRakip'), findsOneWidget); // Sadece skor satırında (kartta değil)
    expect(find.text('+30${AppStrings.coinSuffix}'), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, AppStrings.playAgain), findsOneWidget);
    expect(find.widgetWithText(SecondaryButton, AppStrings.matchDetail), findsOneWidget);
  });

  testWidgets('21. 320 dp ve 360 dp genişlikte 1.3 yazı ölçeğinde sıfır taşma oluşur', (tester) async {
    for (final width in [320.0, 360.0]) {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1.0;

      final matchState = createMatchState(
        scores: {'me': 2, 'bot': 1},
        winnerId: 'me',
      );
      final uiState = MatchUiState(
        matchState: matchState,
        opponentName: 'UzunOyuncuAdi123',
        coinsAwarded: 30,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchUiStateProvider.overrideWithValue(uiState),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 640),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: const Scaffold(
                body: MatchEndView(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.blockAction), findsNothing);
      expect(find.widgetWithText(PrimaryButton, AppStrings.playAgain), findsOneWidget);
      expect(find.widgetWithText(SecondaryButton, AppStrings.matchDetail), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
  });
}
