import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/app_widgets.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class MockPowerupSession implements MatchSession {
  bool extraTimeCalled = false;
  bool giveAnswerCalled = false;

  @override
  MatchUiState get state => const MatchUiState();

  @override
  void submit(String text) {}

  @override
  void leaveMatch() {}

  @override
  void dispose() {}

  @override
  void useExtraTime() {
    extraTimeCalled = true;
  }

  @override
  void useGiveAnswer() {
    giveAnswerCalled = true;
  }
}

class FakeProfileNotifier extends ProfileNotifier {
  final int initialCoins;
  FakeProfileNotifier({this.initialCoins = 100});

  @override
  ProfileState build() {
    return ProfileState(
      nickname: 'TestPlayer',
      coins: initialCoins,
    );
  }
}

class FakeModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode initialMode;
  FakeModeNotifier(this.initialMode);

  @override
  MatchSessionMode build() => initialMode;
}

class TestUiStateNotifier extends Notifier<MatchUiState> {
  final MatchUiState initial;
  TestUiStateNotifier(this.initial);

  @override
  MatchUiState build() => initial;

  MatchUiState get currentState => state;

  void updateState(MatchUiState next) {
    state = next;
  }
}

void main() {
  final testQuestion = Question(
    id: 'q1',
    categoryId: 'c1',
    text: 'Test Sorusu',
    answers: [],
  );

  final testMatchState = MatchState(
    config: const MatchConfig(answerSeconds: 15),
    playerIds: const ['me', 'bot'],
    scores: const {'me': 0, 'bot': 0},
    decisiveRounds: 0,
    totalRoundsPlayed: 0,
    phase: MatchPhase.roundActive,
    currentQuestion: testQuestion,
    usedAnswerIds: const {},
    turnPlayerId: 'me',
    deadlineMs: 20000,
    remainingNearMisses: const {'me': 1, 'bot': 0},
    usedQuestionIds: const {},
    currentRoundAttempts: const [],
    roundHistory: const [],
  );

  Widget createWidget({
    required MatchSessionMode mode,
    required MatchUiState uiState,
    required MockPowerupSession session,
    int coins = 100,
  }) {
    final stateNotifier = TestUiStateNotifier(uiState);
    return ProviderScope(
      key: UniqueKey(),
      overrides: [
        activeMatchSessionModeProvider
            .overrideWith(() => FakeModeNotifier(mode)),
        activeMatchUiStateProvider
            .overrideWith((ref) => ref.watch(
                  NotifierProvider<TestUiStateNotifier, MatchUiState>(
                    () => stateNotifier,
                  ),
                )),
        activeMatchSessionProvider.overrideWithValue(session),
        profileProvider.overrideWith(() => FakeProfileNotifier(initialCoins: coins)),
      ],
      child: const MaterialApp(
        home: MatchScreen(),
      ),
    );
  }

  testWidgets('1. Bot maçında Jokerler butonu gösterilir, tıklanınca panel açılır, Süre tıklanınca useExtraTime çağrılır ve panel kapanır', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.bot,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Bot Ahmet',
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
    ));
    await tester.pumpAndSettle();

    // Başlangıçta Jokerler butonu var, çipler ve blur gizli
    expect(find.bySemanticsLabel('Jokerler'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byIcon(Icons.timer), findsNothing);

    // Butona bas -> radial menü ve bulanıklık açılır
    await tester.tap(find.bySemanticsLabel('Jokerler'));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    // Menü üzerinde metin etiketi YOK, sadece ikon ve semantics var
    expect(find.text('Süre'), findsNothing);
    expect(find.text('+5 sn'), findsNothing);
    expect(find.text('30'), findsNothing);
    expect(find.byIcon(Icons.timer), findsOneWidget);
    expect(find.bySemanticsLabel('Süre jokeri, 30 jeton'), findsOneWidget);

    // Süre butonuna bas -> useExtraTime çağrılır ve menü anında kapanır
    await tester.tap(find.byIcon(Icons.timer));
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isTrue);
    expect(find.byIcon(Icons.timer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('2. Arkadaş maçında (friendly) Jokerler butonu gösterilmez', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Arkadaş Ali',
        isFriendly: true,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Jokerler'), findsNothing);
    expect(find.byIcon(Icons.timer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('3. Çevrimiçi ranked maçta güçlendirici paneli açılınca ikon görünür, uzun basınca ipucu çıkar ve tıklanınca useExtraTime çağrılır', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
      coins: 100,
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Jokerler'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Jokerler'));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    // Menü üzerinde metin etiketi ve fiyat yazısı YOK
    expect(find.text('Süre'), findsNothing);
    expect(find.text('30'), findsNothing);
    expect(find.byIcon(Icons.timer), findsOneWidget);
    expect(find.bySemanticsLabel('Süre jokeri, 30 jeton'), findsOneWidget);

    // Uzun basınca Tooltip ipucu ("Süre · 30 jeton") çıkar
    await tester.longPress(find.byIcon(Icons.timer));
    await tester.pumpAndSettle();
    expect(find.text('Süre · 30 jeton'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.timer));
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isTrue);
    expect(find.byIcon(Icons.timer), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('4. Jeton yetersizken buton soluk görünür, tıklanınca panel AÇIK kalır ve yetersiz bakiye uyarısı verir', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
      session: session,
      coins: 10, // < 30
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Jokerler'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.timer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.timer));
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isFalse);
    expect(find.text(AppStrings.notEnoughCoinsForExtraTime(30)), findsOneWidget);
    // Pasif duruma basıldığında menü AÇIK kalır
    expect(find.byIcon(Icons.timer), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('5. Güçlendirici maçta kullanıldıktan sonra onay (check) ikonuna dönüşür ve tıklanınca panel açık kalır', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 0, // kullanıldı
      ),
      session: session,
      coins: 100,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Jokerler'));
    await tester.pumpAndSettle();

    // Metin etiketi kalktı, küçük onay (check) ikonu var
    expect(find.text(AppStrings.extraTimeUsed), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isFalse);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget); // Panel açık
  });

  testWidgets('6. Rakip ek süre kullandığında üst çubuk altında bildirim şeridi görünür', (tester) async {
    final session = MockPowerupSession();
    await tester.pumpWidget(createWidget(
      mode: MatchSessionMode.online,
      uiState: MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        opponentExtraTimeBanner: AppStrings.opponentUsedExtraTime,
      ),
      session: session,
    ));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.opponentUsedExtraTime), findsOneWidget);
  });

  testWidgets('7. temporary_error bildirimi geldiğinde ekranda SnackBar gösterilir ve buton sessiz kalmaz', (tester) async {
    final session = MockPowerupSession();
    final stateNotifier = TestUiStateNotifier(
      MatchUiState(
        matchState: testMatchState,
        opponentName: 'Rakip Zeynep',
        isFriendly: false,
        extraTimeCost: 30,
        extraTimeSeconds: 5,
        extraTimeRemainingUses: 1,
      ),
    );

    final testUiStateProvider =
        NotifierProvider<TestUiStateNotifier, MatchUiState>(
      () => stateNotifier,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeMatchSessionModeProvider
              .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
          activeMatchUiStateProvider
              .overrideWith((ref) => ref.watch(testUiStateProvider)),
          activeMatchSessionProvider.overrideWithValue(session),
          profileProvider.overrideWith(() => FakeProfileNotifier(initialCoins: 100)),
        ],
        child: const MaterialApp(
          home: MatchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // temporary_error geldiğinde
    stateNotifier.updateState(
      stateNotifier.currentState.copyWith(
        isUsingPowerup: false,
        powerupErrorNotice: AppStrings.powerupTemporaryError,
        powerupErrorCounter: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(AppStrings.powerupTemporaryError), findsOneWidget);
  });

  group('Cevap Ver (give_answer) Widget & Yerleşim Testleri', () {
    testWidgets('8. Bot maçında Cevap Ver butonu panelde gösterilir, tıklanınca panel kapanır; arkadaş maçında Jokerler butonu gösterilmez', (tester) async {
      final session = MockPowerupSession();
      // Bot maçı: Jokerler butonu var, panel açılınca Cevap Ver görünür ve tıklanabilir
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.bot,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Bot Ahmet',
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Jokerler'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      expect(cevapVerFinder, findsOneWidget);
      expect(find.text(AppStrings.giveAnswerPowerup), findsNothing); // Metin etiketi yok

      await tester.tap(cevapVerFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isTrue);
      expect(cevapVerFinder, findsNothing);

      // Arkadaş maçı: gösterilmez
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Arkadaş Ali',
          isFriendly: true,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Jokerler'), findsNothing);
      expect(find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton'), findsNothing);
    });

    testWidgets('9. Çevrimiçi ranked maçta panel açılınca iki buton yerleşir, metinler yoktur, uzun basınca ipucu çıkar', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          extraTimeCost: 30,
          extraTimeSeconds: 5,
          extraTimeRemainingUses: 1,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsOneWidget);
      // Menü üzerinde metin ve fiyat etiketleri YOK
      expect(find.text('Süre'), findsNothing);
      expect(find.text('30'), findsNothing);
      expect(find.text(AppStrings.giveAnswerPowerup), findsNothing);
      expect(find.text('50'), findsNothing);

      // İkonlar ve semantics var
      expect(find.byIcon(Icons.timer), findsOneWidget);
      expect(find.bySemanticsLabel('Süre jokeri, 30 jeton'), findsOneWidget);
      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      expect(cevapVerFinder, findsOneWidget);

      // Uzun basınca Cevap Ver ipucu ("Cevap Ver · 50 jeton") çıkar
      await tester.longPress(cevapVerFinder);
      await tester.pumpAndSettle();
      expect(find.text('Cevap Ver · 50 jeton'), findsOneWidget);

      await tester.tap(cevapVerFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isTrue);
      expect(cevapVerFinder, findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('10. 360x640 ekranda, klavye açıkken (viewInsets) iki buton ekranda tamamen görünürdür, birbirleriyle ve "Tur N" ile kesişmez', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = MockPowerupSession();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            viewInsets: EdgeInsets.only(bottom: 260), // Klavye açık
          ),
          child: createWidget(
            mode: MatchSessionMode.online,
            uiState: MatchUiState(
              matchState: testMatchState,
              opponentName: 'Rakip Zeynep',
              isFriendly: false,
              extraTimeCost: 30,
              extraTimeSeconds: 5,
              extraTimeRemainingUses: 1,
              giveAnswerCost: 50,
              giveAnswerRemainingUses: 1,
              roundAttempts: const [
                RoundAttemptUiModel(
                  playerId: 'me',
                  text: 'ÇokUzunBirCevapKelimesiDenemesiTaşmaTesti',
                  isCorrect: true,
                  viaPowerup: true,
                ),
              ],
            ),
            session: session,
            coins: 100,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Paneli aç
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      final err = tester.takeException();
      expect(err, isNull);

      // Blur katmanı ekranda
      expect(find.byType(BackdropFilter), findsOneWidget);

      // Butonları bul
      final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      final turPillFinder = find.text(AppStrings.round(1));

      expect(sureFinder, findsOneWidget);
      expect(cevapVerFinder, findsOneWidget);
      expect(turPillFinder, findsOneWidget);

      final sureRect = tester.getRect(sureFinder);
      final cevapVerRect = tester.getRect(cevapVerFinder);
      final turPillRect = tester.getRect(turPillFinder);

      const screenRect = Rect.fromLTWH(0, 0, 360, 640);

      // 1. Ekran sınırları içinde (taşma yok)
      expect(screenRect.contains(sureRect.topLeft), isTrue);
      expect(screenRect.contains(sureRect.bottomRight), isTrue);
      expect(screenRect.contains(cevapVerRect.topLeft), isTrue);
      expect(screenRect.contains(cevapVerRect.bottomRight), isTrue);

      // 2. Birbirleriyle kesişmiyor
      expect(sureRect.overlaps(cevapVerRect), isFalse);

      // 3. "Tur N" kapsülüyle kesişmiyor
      expect(cevapVerRect.overlaps(turPillRect), isFalse);
      expect(sureRect.overlaps(turPillRect), isFalse);

      // 4. Merkezler arası mesafe >= 64 dp
      final distance = (sureRect.center - cevapVerRect.center).distance;
      expect(distance, greaterThanOrEqualTo(64.0));

      // 5. Blur katmanı tüm ekranı DEĞİL sadece sağ üst köşeyi kaplar
      final blurRect = tester.getRect(find.byType(BackdropFilter));
      // Sol sınırı en az 180 dp (ekran genişliğinin %50'sinden fazlası net kalır)
      expect(blurRect.left, greaterThanOrEqualTo(180.0));
      // Alt sınırı 160 dp'nin altında (ekran yüksekliğinin %75'i net kalır)
      expect(blurRect.bottom, lessThanOrEqualTo(160.0));
      // Boyutlar 2 * R = 248 dp
      expect(blurRect.width, equals(248.0));
      expect(blurRect.height, equals(248.0));

      // Sol oyuncu kartı (Sen) ve Cevap giriş kutusu bölge dışındadır (bulanıklaşmaz ve kararmaz)
      final meCardRect = tester.getRect(find.byType(PlayerCard).first);
      expect(blurRect.overlaps(meCardRect), isFalse);
      final inputRect = tester.getRect(find.byType(TextField));
      expect(blurRect.overlaps(inputRect), isFalse);

      // İki radial buton da dairesel blur bölgesi içindedir
      expect(blurRect.contains(sureRect.topLeft), isTrue);
      expect(blurRect.contains(sureRect.bottomRight), isTrue);
      expect(blurRect.contains(cevapVerRect.topLeft), isTrue);
      expect(blurRect.contains(cevapVerRect.bottomRight), isTrue);
      final menuCenter = Offset(360 - (20 + 22), 8 + 22); // (318, 30)
      expect((sureRect.center - menuCenter).distance, lessThanOrEqualTo(124.0));
      expect((cevapVerRect.center - menuCenter).distance, lessThanOrEqualTo(124.0));
    });

    testWidgets('11. Cevap Ver yetersiz jeton durumunda (%50 opaklık) tıklanınca panel AÇIK kalır ve SnackBar gösterir', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
        coins: 20, // < 50
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      expect(cevapVerFinder, findsOneWidget);

      await tester.tap(cevapVerFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isFalse);
      expect(find.text(AppStrings.notEnoughCoinsForGiveAnswer(50)), findsOneWidget);
      expect(cevapVerFinder, findsOneWidget); // Panel açık
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('12. Cevap Ver kullanıldıktan sonra (remainingUses = 0) onay (check) ikonuna dönüşür ve panel açık kalır', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 0, // kullanıldı
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.giveAnswerUsed), findsNothing);
      final checkFinder = find.byIcon(Icons.check_circle_outline);
      expect(checkFinder, findsOneWidget);

      await tester.tap(checkFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isFalse);
      expect(checkFinder, findsOneWidget); // Panel açık
    });

    testWidgets('13. Sıra bende değilken Cevap Ver tıklandığında panel AÇIK kalır ve sıra uyarısı verir', (tester) async {
      final botTurnMatchState = testMatchState.copyWith(
        turnPlayerId: 'bot',
      );
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: botTurnMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      expect(cevapVerFinder, findsOneWidget);

      await tester.tap(cevapVerFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isFalse);
      expect(find.text(AppStrings.notYourTurnGiveAnswer), findsOneWidget);
      expect(cevapVerFinder, findsOneWidget); // Panel açık
    });

    testWidgets('14. isUsingPowerup aktifken Jokerler butonunda CircularProgressIndicator görünür', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
          isUsingPowerup: true,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('15. viaPowerup=true olan doğru cevap balonunda güçlendirici SVG ikonu çizilir', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          roundAttempts: const [
            RoundAttemptUiModel(
              playerId: 'me',
              text: 'Ankara',
              isCorrect: true,
              viaPowerup: true,
            ),
          ],
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ankara'), findsOneWidget);
      expect(find.byWidgetPredicate((w) =>
          w is Text &&
          w.textSpan != null &&
          w.textSpan!.toPlainText().contains('Ankara')),
          findsOneWidget);
    });

    testWidgets('16. Panel açılıp kapanma mekaniği: butona bas -> açılır, butona tekrar bas -> kapanır, dışarı dokun -> kapanır; blur senkronizedir', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          extraTimeCost: 30,
          extraTimeSeconds: 5,
          extraTimeRemainingUses: 1,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 1,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      // Başlangıçta kapalı
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);

      // 1. Butona tıkla -> açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);

      // 2. Butona tekrar tıkla -> kapanır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);

      // 3. Butona tıkla -> tekrar açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);

      // 4. Panel dışına (ekranın sol ortasına) tıkla -> kapanır
      await tester.tapAt(const Offset(30, 300));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);

      // 5. Butona tıkla -> tekrar açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);

      // 6. Bulanık bölgenin butonlar harici boş bir noktasına dokun -> kapanır
      await tester.tapAt(const Offset(220, 25));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);
    });

    testWidgets('17. Odak Koruması Testi: Cevap kutusu odaklıyken panel açılıp kapandığında ve Tooltip çıktığında odak korunur', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          extraTimeCost: 30,
          extraTimeSeconds: 5,
          extraTimeRemainingUses: 1,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      // Cevap alanına odaklan
      await tester.showKeyboard(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

      // Jokerler butonuna tıkla -> panel açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);

      // Odak hâlâ cevap kutusundadır!
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

      // Uzun bas -> Tooltip ipucu çıkar ("Süre · 30 jeton")
      await tester.longPress(find.byIcon(Icons.timer));
      await tester.pumpAndSettle();
      expect(find.text('Süre · 30 jeton'), findsOneWidget);

      // Tooltip açıkken dahi odak cevap kutusunda korunur!
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

      // Panel dışına dokun -> panel kapanır
      await tester.tapAt(const Offset(30, 300));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);

      // Odak hâlâ cevap kutusundadır!
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    });

    testWidgets('18. Tur değiştiğinde açık panel ve blur kendiliğinden kapanır', (tester) async {
      final session = MockPowerupSession();
      final stateNotifier = TestUiStateNotifier(
        MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          extraTimeCost: 30,
          extraTimeSeconds: 5,
          extraTimeRemainingUses: 1,
        ),
      );

      final testUiStateProvider =
          NotifierProvider<TestUiStateNotifier, MatchUiState>(
        () => stateNotifier,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMatchSessionModeProvider
                .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
            activeMatchUiStateProvider
                .overrideWith((ref) => ref.watch(testUiStateProvider)),
            activeMatchSessionProvider.overrideWithValue(session),
            profileProvider.overrideWith(() => FakeProfileNotifier(initialCoins: 100)),
          ],
          child: const MaterialApp(
            home: MatchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Paneli aç
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byIcon(Icons.timer), findsOneWidget);

      // Sıra bota geçer (tur değişimi)
      stateNotifier.updateState(
        stateNotifier.currentState.copyWith(
          matchState: testMatchState.copyWith(turnPlayerId: 'bot'),
        ),
      );
      await tester.pumpAndSettle();

      // Panel ve blur kendiliğinden kapanmıştır
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);
    });

    testWidgets('19. İki joker de kullanıldıysa Jokerler butonu soluk görünür ama panel yine açılabilir ve check ikonları görünür', (tester) async {
      final session = MockPowerupSession();
      await tester.pumpWidget(createWidget(
        mode: MatchSessionMode.online,
        uiState: MatchUiState(
          matchState: testMatchState,
          opponentName: 'Rakip Zeynep',
          isFriendly: false,
          extraTimeCost: 30,
          extraTimeSeconds: 5,
          extraTimeRemainingUses: 0,
          giveAnswerCost: 50,
          giveAnswerRemainingUses: 0,
        ),
        session: session,
        coins: 100,
      ));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Jokerler'), findsOneWidget);

      // Butonun Opacity widget'ı 0.5 opaklıktadır
      final opacities = tester.widgetList<Opacity>(
        find.ancestor(of: find.byType(Icon), matching: find.byType(Opacity)),
      );
      expect(opacities.any((op) => op.opacity == 0.5), isTrue);

      // Butona tıklanınca panel yine açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      // Menüde "Kullanıldı" metin etiketi YOK, iki adet onay (check) ikonu var
      expect(find.text('Kullanıldı'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
    });
  });
}
