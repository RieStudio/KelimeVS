import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
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

Finder findSvgAsset(String assetName) {
  return find.byWidgetPredicate((widget) {
    if (widget is SvgPicture) {
      final loader = widget.bytesLoader;
      if (loader is SvgAssetLoader) {
        return loader.assetName == assetName;
      }
    }
    return false;
  });
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
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);

    // Butona bas -> radial menü ve bulanıklık açılır
    await tester.tap(find.bySemanticsLabel('Jokerler'));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
    // Menü üzerinde metin etiketi YOK, sadece ikon ve semantics var
    expect(find.text('Süre'), findsNothing);
    expect(find.text('+5 sn'), findsNothing);
    expect(find.text('30'), findsNothing);
    // Radial menüde Icons.timer artık KULLANILMAZ
    expect(find.byIcon(Icons.timer), findsNothing);
    final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
    expect(sureFinder, findsOneWidget);
    final timeSvgFinder = findSvgAsset('assets/icons/powerup_time.svg');
    expect(timeSvgFinder, findsOneWidget);

    // Renk filtresi YOK, SVG kendi renkleriyle çizilir
    final timeSvg = tester.widget<SvgPicture>(timeSvgFinder);
    expect(timeSvg.colorFilter, isNull);
    expect(timeSvg.width, 28);
    expect(timeSvg.height, 28);

    // Kullanılabilir durumda buton zemini BEYAZ/krem (AppColors.card)
    final container = tester.widget<Container>(
      find.descendant(of: sureFinder, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.card);
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.border?.top.color, AppColors.ink);
    expect(decoration.boxShadow, isNotNull);

    // Süre butonuna bas -> useExtraTime çağrılır ve menü anında kapanır
    await tester.tap(sureFinder);
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isTrue);
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);
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
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);
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

    expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
    // Menü üzerinde metin etiketi ve fiyat yazısı YOK
    expect(find.text('Süre'), findsNothing);
    expect(find.text('30'), findsNothing);
    expect(find.byIcon(Icons.timer), findsNothing);
    final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
    expect(sureFinder, findsOneWidget);
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

    // Uzun basınca Tooltip ipucu ("Süre · 30 jeton") çıkar
    await tester.longPress(sureFinder);
    await tester.pumpAndSettle();
    expect(find.text('Süre · 30 jeton'), findsOneWidget);

    await tester.tap(sureFinder);
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isTrue);
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);
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

    final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
    expect(sureFinder, findsOneWidget);
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

    // Pasif durumda %50 opaklık doğrula
    final opacityWidget = tester.widget<Opacity>(
      find.ancestor(
        of: findSvgAsset('assets/icons/powerup_time.svg'),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacityWidget.opacity, 0.5);

    await tester.tap(sureFinder);
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isFalse);
    expect(find.text(AppStrings.notEnoughCoinsForExtraTime(30)), findsOneWidget);
    // Pasif duruma basıldığında menü AÇIK kalır
    expect(sureFinder, findsOneWidget);
    expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
  });

  testWidgets('5. Güçlendirici maçta kullanıldıktan sonra check ikonu kaldırılır, kendi SVG ikonu gri tonlamalı çizilir, gölge kalkar ve buton aşağı kayar', (tester) async {
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

    // Check (onay) ikonu artık GÖSTERİLMEZ
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);

    // Kendi SVG ikonu (powerup_time.svg) ColorFiltered ile gri tonlamalı çizilir
    final usedFinder = find.bySemanticsLabel('Süre jokeri, ${AppStrings.extraTimeUsed}');
    expect(usedFinder, findsOneWidget);

    final timeSvgFinder = find.descendant(
      of: usedFinder,
      matching: findSvgAsset('assets/icons/powerup_time.svg'),
    );
    expect(timeSvgFinder, findsOneWidget);

    final colorFilteredFinder = find.descendant(
      of: usedFinder,
      matching: find.byType(ColorFiltered),
    );
    expect(colorFilteredFinder, findsOneWidget);
    final colorFiltered = tester.widget<ColorFiltered>(colorFilteredFinder);
    expect(colorFiltered.colorFilter, const ColorFilter.matrix(kGrayscaleMatrix));

    // Kullanıldı durumunda soluk gri zemin (AppColors.surface)
    final container = tester.widget<Container>(
      find.descendant(of: usedFinder, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.surface);

    // Sert gölge KALDIRILMIŞTIR
    expect(decoration.boxShadow, isNull);

    // Buton gölge ofseti kadar (~2 dp) aşağı kaydırılmıştır (Transform.translate)
    final translateFinder = find.descendant(
      of: usedFinder,
      matching: find.byType(Transform),
    );
    expect(translateFinder, findsOneWidget);
    final transformWidget = tester.widget<Transform>(translateFinder);
    expect(transformWidget.transform.getTranslation().y, equals(2.0));

    // Kullanıldı butonuna tıklanınca işlem çağrılmaz ve menü açık kalır
    await tester.tap(usedFinder);
    await tester.pumpAndSettle();

    expect(session.extraTimeCalled, isFalse);
    expect(usedFinder, findsOneWidget); // Panel açık
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

      final answerSvgFinder = findSvgAsset('assets/icons/powerup_auto_answer.svg');
      expect(answerSvgFinder, findsOneWidget);
      final answerSvg = tester.widget<SvgPicture>(answerSvgFinder);
      expect(answerSvg.colorFilter, isNull);
      expect(answerSvg.width, 28);
      expect(answerSvg.height, 28);

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

      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      // Menü üzerinde metin ve fiyat etiketleri YOK
      expect(find.text('Süre'), findsNothing);
      expect(find.text('30'), findsNothing);
      expect(find.text(AppStrings.giveAnswerPowerup), findsNothing);
      expect(find.text('50'), findsNothing);

      // Radial menüde Icons.timer artık KULLANILMAZ
      expect(find.byIcon(Icons.timer), findsNothing);

      // İkonlar SVG olarak çizilir ve semantics var
      final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
      expect(sureFinder, findsOneWidget);
      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');
      expect(cevapVerFinder, findsOneWidget);

      final timeSvgFinder = findSvgAsset('assets/icons/powerup_time.svg');
      final answerSvgFinder = findSvgAsset('assets/icons/powerup_auto_answer.svg');
      expect(timeSvgFinder, findsOneWidget);
      expect(answerSvgFinder, findsOneWidget);

      // Renk boyaması (colorFilter) KALDIRILDI
      final timeSvg = tester.widget<SvgPicture>(timeSvgFinder);
      final answerSvg = tester.widget<SvgPicture>(answerSvgFinder);
      expect(timeSvg.colorFilter, isNull);
      expect(answerSvg.colorFilter, isNull);
      expect(timeSvg.width, 28);
      expect(answerSvg.width, 28);

      // Kullanılabilir durumda buton zeminleri BEYAZ (AppColors.card)
      final sureContainer = tester.widget<Container>(
        find.descendant(of: sureFinder, matching: find.byType(Container)).first,
      );
      final answerContainer = tester.widget<Container>(
        find.descendant(of: cevapVerFinder, matching: find.byType(Container)).first,
      );
      expect((sureContainer.decoration as BoxDecoration).color, AppColors.card);
      expect((answerContainer.decoration as BoxDecoration).color, AppColors.card);

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

      // Blur katmanı ekranda: 4 eşmerkezli halka
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));

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
      final menuCenter = Offset(360 - (20 + 22), 8 + 22); // (318, 30)
      final outermostBlurRect = tester.getRect(find.byType(BackdropFilter).first);

      // Üst sınır: Durum çubuğuna taşar (Y <= 0)
      expect(outermostBlurRect.top, lessThanOrEqualTo(0.0));
      // Sol sınırı en az 180 dp (ekran genişliğinin %50'sinden fazlası net kalır)
      expect(outermostBlurRect.left, greaterThanOrEqualTo(180.0));
      // Alt sınırı 170 dp'nin altında (ekran yüksekliğinin %70'inden fazlası net kalır)
      expect(outermostBlurRect.bottom, lessThanOrEqualTo(170.0));
      // En dış halkanın boyutları 2 * R = 272 dp (R = 136)
      expect(outermostBlurRect.width, equals(272.0));
      expect(outermostBlurRect.height, equals(272.0));

      // 4 halkanın da merkezi menuCenter'dadır ve yarıçapları kPowerupBlurRadii ile eşleşir
      for (int i = 0; i < kPowerupBlurRadii.length; i++) {
        final ringRect = tester.getRect(find.byType(BackdropFilter).at(i));
        final expectedR = kPowerupBlurRadii[i];
        expect(ringRect.width, equals(expectedR * 2));
        expect(ringRect.height, equals(expectedR * 2));
        expect(ringRect.center, equals(menuCenter));
      }

      // En dış halkanın yarıçapı butonların en uzak köşesinden en az 20 dp büyüktür (R >= 131 dp)
      final furthestCornerSure = [
        sureRect.topLeft,
        sureRect.topRight,
        sureRect.bottomLeft,
        sureRect.bottomRight,
      ].map((p) => (p - menuCenter).distance).reduce(math.max);
      final furthestCornerCevapVer = [
        cevapVerRect.topLeft,
        cevapVerRect.topRight,
        cevapVerRect.bottomLeft,
        cevapVerRect.bottomRight,
      ].map((p) => (p - menuCenter).distance).reduce(math.max);
      final furthestButtonCorner = math.max(furthestCornerSure, furthestCornerCevapVer);
      expect(kPowerupBlurRadii.first, greaterThanOrEqualTo(furthestButtonCorner + 20.0));

      // En iç halka (112 dp) butonları tamamen içine alır
      expect(kPowerupBlurRadii.last, greaterThanOrEqualTo(furthestButtonCorner));

      // Sol oyuncu kartı (Sen) ve Cevap giriş kutusu bölge dışındadır (bulanıklaşmaz ve kararmaz)
      final meCardRect = tester.getRect(find.byType(PlayerCard).first);
      expect(outermostBlurRect.overlaps(meCardRect), isFalse);
      final inputRect = tester.getRect(find.byType(TextField));
      expect(outermostBlurRect.overlaps(inputRect), isFalse);

      // İki radial buton da en dış dairesel blur bölgesi içindedir
      expect(outermostBlurRect.contains(sureRect.topLeft), isTrue);
      expect(outermostBlurRect.contains(sureRect.bottomRight), isTrue);
      expect(outermostBlurRect.contains(cevapVerRect.topLeft), isTrue);
      expect(outermostBlurRect.contains(cevapVerRect.bottomRight), isTrue);
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
      final answerSvgFinder = findSvgAsset('assets/icons/powerup_auto_answer.svg');
      expect(answerSvgFinder, findsOneWidget);

      // Pasif durumda %50 opaklık doğrula
      final opacityWidget = tester.widget<Opacity>(
        find.ancestor(
          of: answerSvgFinder,
          matching: find.byType(Opacity),
        ).first,
      );
      expect(opacityWidget.opacity, 0.5);

      await tester.tap(cevapVerFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isFalse);
      expect(find.text(AppStrings.notEnoughCoinsForGiveAnswer(50)), findsOneWidget);
      expect(cevapVerFinder, findsOneWidget); // Panel açık
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
    });

    testWidgets('12. Cevap Ver kullanıldıktan sonra (remainingUses = 0) check ikonu gösterilmez, gri tonlamalı ikon ve basılmış buton efekti oluşur', (tester) async {
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

      // Check ikonu gösterilmez
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      // Kendi SVG ikonu (powerup_auto_answer.svg) gri tonlamalı olarak bulunur
      final usedFinder = find.bySemanticsLabel('Cevap Ver jokeri, ${AppStrings.giveAnswerUsed}');
      expect(usedFinder, findsOneWidget);

      final answerSvgFinder = find.descendant(
        of: usedFinder,
        matching: findSvgAsset('assets/icons/powerup_auto_answer.svg'),
      );
      expect(answerSvgFinder, findsOneWidget);

      final colorFilteredFinder = find.descendant(
        of: usedFinder,
        matching: find.byType(ColorFiltered),
      );
      expect(colorFilteredFinder, findsOneWidget);
      expect(tester.widget<ColorFiltered>(colorFilteredFinder).colorFilter, const ColorFilter.matrix(kGrayscaleMatrix));

      // Kullanıldı durumunda soluk gri zemin (AppColors.surface)
      final container = tester.widget<Container>(
        find.descendant(of: usedFinder, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.surface);

      // Sert gölge kalkar ve buton 2 dp aşağı kayar
      expect(decoration.boxShadow, isNull);
      final transformFinder = find.descendant(
        of: usedFinder,
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
      expect(tester.widget<Transform>(transformFinder).transform.getTranslation().y, equals(2.0));

      await tester.tap(usedFinder);
      await tester.pumpAndSettle();

      expect(session.giveAnswerCalled, isFalse);
      expect(usedFinder, findsOneWidget); // Panel açık
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
      final answerSvgFinder = findSvgAsset('assets/icons/powerup_auto_answer.svg');
      expect(answerSvgFinder, findsOneWidget);

      // Pasif durumda %50 opaklık doğrula
      final opacityWidget = tester.widget<Opacity>(
        find.ancestor(
          of: answerSvgFinder,
          matching: find.byType(Opacity),
        ).first,
      );
      expect(opacityWidget.opacity, 0.5);

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
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);

      // 1. Butona tıkla -> açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      expect(find.byIcon(Icons.timer), findsNothing); // Radial menüde Icons.timer KULLANILMAZ
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

      // 2. Butona tekrar tıkla -> kapanır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);

      // 3. Butona tıkla -> tekrar açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

      // 4. Panel dışına (ekranın sol ortasına) tıkla -> kapanır
      await tester.tapAt(const Offset(30, 300));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);

      // 5. Butona tıkla -> tekrar açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

      // 6. Bulanık bölgenin butonlar harici boş bir noktasına dokun -> kapanır
      await tester.tapAt(const Offset(220, 25));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);
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
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      expect(find.byIcon(Icons.timer), findsNothing); // Radial menüde Icons.timer YOK

      final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
      expect(sureFinder, findsOneWidget);

      // Odak hâlâ cevap kutusundadır!
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

      // Uzun bas -> Tooltip ipucu çıkar ("Süre · 30 jeton")
      await tester.longPress(sureFinder);
      await tester.pumpAndSettle();
      expect(find.text('Süre · 30 jeton'), findsOneWidget);

      // Tooltip açıkken dahi odak cevap kutusunda korunur!
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);

      // Panel dışına dokun -> panel kapanır
      await tester.tapAt(const Offset(30, 300));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byIcon(Icons.timer), findsNothing);
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);

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
      expect(find.byType(BackdropFilter), findsNWidgets(kPowerupBlurRadii.length));
      expect(find.byIcon(Icons.timer), findsNothing);
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);

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
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsNothing);
    });

    testWidgets('19. İki joker de kullanıldıysa Jokerler butonu soluk görünür ama panel yine açılabilir ve gri tonlamalı basılmış butonlar görünür', (tester) async {
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

      // Ana buton SVG ikonunu içerir (Icons.auto_awesome YOK)
      expect(findSvgAsset(kPowerupMenuSvgPath), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);

      // Ana butonun Opacity widget'ı 0.5 opaklıktadır
      final opacities = tester.widgetList<Opacity>(
        find.ancestor(
          of: findSvgAsset(kPowerupMenuSvgPath),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities.any((op) => op.opacity == 0.5), isTrue);

      // Butona tıklanınca panel yine açılır
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      // Check ikonu KESİNLİKLE YOK, iki adet gri tonlamalı (ColorFiltered) ikon var
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byType(ColorFiltered), findsNWidgets(2));
      expect(findSvgAsset('assets/icons/powerup_time.svg'), findsOneWidget);
      expect(findSvgAsset('assets/icons/powerup_auto_answer.svg'), findsOneWidget);

      // İki buton da soluk zemin (AppColors.surface) ve 2 dp kaymış (Transform.translate)
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(Transform),
          matching: find.byType(Container),
        ),
      );
      expect(
        containers.where((c) => (c.decoration as BoxDecoration?)?.color == AppColors.surface).length,
        equals(2),
      );
    });

    testWidgets('20. Renkli SVG ikonlar, zemin renkleri ve kontur/gölge detayları: Icons.timer menüde yoktur, colorFilter boştur, beyaz zemin ve sert gölge korunur', (tester) async {
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

      // Paneli aç
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      // 1. Icons.timer menü butonunda KESİNLİKLE kullanılmaz
      expect(find.byIcon(Icons.timer), findsNothing);

      // 2. İki buton da SVG ikon kullanır
      final timeSvgFinder = findSvgAsset('assets/icons/powerup_time.svg');
      final answerSvgFinder = findSvgAsset('assets/icons/powerup_auto_answer.svg');
      expect(timeSvgFinder, findsOneWidget);
      expect(answerSvgFinder, findsOneWidget);

      final timeSvg = tester.widget<SvgPicture>(timeSvgFinder);
      final answerSvg = tester.widget<SvgPicture>(answerSvgFinder);

      // 3. Renk boyaması (colorFilter / color) KALDIRILMIŞTIR (null)
      expect(timeSvg.colorFilter, isNull);
      expect(answerSvg.colorFilter, isNull);
      expect(timeSvg.width, 28);
      expect(timeSvg.height, 28);
      expect(answerSvg.width, 28);
      expect(answerSvg.height, 28);

      // 4. KULLANILABİLİR durumdaki buton zeminleri sarı yerine BEYAZ (AppColors.card)
      final sureFinder = find.bySemanticsLabel('Süre jokeri, 30 jeton');
      final cevapVerFinder = find.bySemanticsLabel('Cevap Ver jokeri, 50 jeton');

      final sureContainer = tester.widget<Container>(
        find.descendant(of: sureFinder, matching: find.byType(Container)).first,
      );
      final answerContainer = tester.widget<Container>(
        find.descendant(of: cevapVerFinder, matching: find.byType(Container)).first,
      );

      final sureDecor = sureContainer.decoration as BoxDecoration;
      final answerDecor = answerContainer.decoration as BoxDecoration;

      expect(sureDecor.color, AppColors.card);
      expect(answerDecor.color, AppColors.card);

      // 5. Koyu yeşil çerçeve ve sert gölge korunmuştur
      expect(sureDecor.border?.top.color, AppColors.ink);
      expect(sureDecor.border?.top.width, AppDimens.borderThin);
      expect(sureDecor.boxShadow?.first.color, AppColors.ink);
      expect(sureDecor.boxShadow?.first.offset, const Offset(0, 2));

      expect(answerDecor.border?.top.color, AppColors.ink);
      expect(answerDecor.border?.top.width, AppDimens.borderThin);
      expect(answerDecor.boxShadow?.first.color, AppColors.ink);
      expect(answerDecor.boxShadow?.first.offset, const Offset(0, 2));
    });

    testWidgets('21. Ana buton: powerup_menu.svg ikonu (Icons.auto_awesome kullanılmaz), açıkken ~12-15° sağa yatar (45° değil), basılmış hissi (2 dp translate, gölge kalkar) verir ve kapanınca sıfırlanır', (tester) async {
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

      // 1. Ana buton ikonu SVG'dir, Icons.auto_awesome kullanılmaz
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      final menuSvgFinder = findSvgAsset(kPowerupMenuSvgPath);
      expect(menuSvgFinder, findsOneWidget);

      final menuSvg = tester.widget<SvgPicture>(menuSvgFinder);
      expect(menuSvg.colorFilter, isNull); // Renk boyaması yok
      expect(menuSvg.width, 26.0);
      expect(menuSvg.height, 26.0);

      // 2. Kapalı başlangıç durumu:
      // Rotasyon açısı = 0
      final initialRotateFinder = find.ancestor(
        of: menuSvgFinder,
        matching: find.byType(Transform),
      ).first;
      final initialRotate = tester.widget<Transform>(initialRotateFinder);
      final initialAngle = math.atan2(
        initialRotate.transform.storage[1],
        initialRotate.transform.storage[0],
      );
      expect(initialAngle, equals(0.0));

      // Translate offset = 0
      final initialBtnContainerFinder = find.descendant(
        of: find.bySemanticsLabel('Jokerler'),
        matching: find.byType(Container),
      ).first;
      final initialTranslateFinder = find.ancestor(
        of: initialBtnContainerFinder,
        matching: find.byType(Transform),
      ).first;
      final initialTranslate = tester.widget<Transform>(initialTranslateFinder);
      expect(initialTranslate.transform.getTranslation().y, equals(0.0));

      // Sert gölge var, zemin beyaz
      final initialDecor = tester.widget<Container>(initialBtnContainerFinder).decoration as BoxDecoration;
      expect(initialDecor.color, AppColors.card);
      expect(initialDecor.boxShadow, isNotNull);

      // 3. Menüyü aç
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      // Açıkken rotasyon açısı: ~14° (12°-15° arası, 45° değil!)
      final openRotate = tester.widget<Transform>(initialRotateFinder);
      final openAngle = math.atan2(
        openRotate.transform.storage[1],
        openRotate.transform.storage[0],
      );
      final openDegrees = openAngle * (180.0 / math.pi);
      expect(openDegrees, greaterThanOrEqualTo(12.0));
      expect(openDegrees, lessThanOrEqualTo(15.0));
      expect(openDegrees, isNot(closeTo(45.0, 1.0)));

      // Açıkken basılmış hissi: 2 dp aşağı kayar
      final openTranslate = tester.widget<Transform>(initialTranslateFinder);
      expect(openTranslate.transform.getTranslation().y, equals(2.0));

      // Açıkken sert gölge kalkar ve zemin altın sarısına döner
      final openDecor = tester.widget<Container>(initialBtnContainerFinder).decoration as BoxDecoration;
      expect(openDecor.color, AppColors.coin);
      expect(openDecor.boxShadow, isNull);

      // 4. Menüyü kapat
      await tester.tap(find.bySemanticsLabel('Jokerler'));
      await tester.pumpAndSettle();

      // Kapanınca rotasyon açısı 0'a döner
      final closedRotate = tester.widget<Transform>(initialRotateFinder);
      final closedAngle = math.atan2(
        closedRotate.transform.storage[1],
        closedRotate.transform.storage[0],
      );
      expect(closedAngle, closeTo(0.0, 0.001));

      // Kapanınca buton eski konumuna (0.0) döner ve gölgesi geri gelir
      final closedTranslate = tester.widget<Transform>(initialTranslateFinder);
      expect(closedTranslate.transform.getTranslation().y, equals(0.0));
      final closedDecor = tester.widget<Container>(initialBtnContainerFinder).decoration as BoxDecoration;
      expect(closedDecor.color, AppColors.card);
      expect(closedDecor.boxShadow, isNotNull);
    });
  });
}
