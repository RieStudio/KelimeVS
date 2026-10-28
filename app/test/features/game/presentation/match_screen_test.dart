import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/answer_bubble.dart';
import 'package:app/core/widgets/player_card.dart';
import 'package:app/core/widgets/question_card.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';

class FakeMatchController extends MatchController {
  final MatchUiState _initialState;
  bool submitCalled = false;
  String? lastSubmittedText;
  bool leaveMatchCalled = false;
  bool startMatchCalled = false;

  FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;

  @override
  void submit(String text) {
    submitCalled = true;
    lastSubmittedText = text;
  }

  @override
  void leaveMatch() {
    leaveMatchCalled = true;
  }

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
  }) async {
    startMatchCalled = true;
  }
}

Widget _buildTestApp(FakeMatchController controller, {Key? key}) {
  return ProviderScope(
    key: key ?? ValueKey(controller),
    overrides: [
      matchControllerProvider.overrideWith(() => controller),
    ],
    child: const MaterialApp(
      home: MatchScreen(),
    ),
  );
}

void main() {
  const testQuestion = Question(
    id: 'q_test_1',
    categoryId: 'hayvanlar',
    text: 'B ile başlayan hayvanlar',
    answers: [
      Answer(id: 'boga', display: 'Boğa', aliases: ['boga']),
      Answer(id: 'baykus', display: 'Baykuş', aliases: ['baykus']),
    ],
  );

  const testMatchState = MatchState(
    config: MatchConfig(totalDecisiveRounds: 3, answerSeconds: 15),
    playerIds: ['me', 'bot'],
    scores: {'me': 1, 'bot': 0},
    decisiveRounds: 1,
    totalRoundsPlayed: 1,
    phase: MatchPhase.roundActive,
    currentQuestion: testQuestion,
    usedAnswerIds: {'boga', 'baykus'},
    turnPlayerId: 'me',
    deadlineMs: 15000,
    remainingNearMisses: {'me': 1, 'bot': 1},
    usedQuestionIds: {'q_test_1'},
    currentRoundAttempts: [],
    roundHistory: [],
  );

  testWidgets('1. Ekran çizilir, kartlar ve tur hapı doğru görünür', (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 11000,
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    // Tur hapı (decisiveRounds = 1 -> Tur 2)
    expect(find.text(AppStrings.round(2)), findsOneWidget);

    // Kapat butonu
    expect(find.bySemanticsLabel(AppStrings.leaveMatch), findsOneWidget);

    // Oyuncu kartları
    expect(find.text(AppStrings.you), findsOneWidget);
    expect(find.text('Ahmet'), findsOneWidget);

    // Soru kartı
    expect(find.byType(QuestionCard), findsOneWidget);
    expect(find.text('B ile başlayan hayvanlar'), findsOneWidget);

    // Giriş alanı
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('2. Sıra bendeyken giriş etkin, rakipteyken salt okunur', (tester) async {
    // A: Sıra bende (turnPlayerId = 'me')
    final myTurnState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final myController = FakeMatchController(myTurnState);

    await tester.pumpWidget(_buildTestApp(myController));
    await tester.pump();

    final myTextField = tester.widget<TextField>(find.byType(TextField));
    expect(myTextField.readOnly, isFalse);
    expect(myTextField.decoration?.hintText, AppStrings.inputPlaceholder);

    // B: Sıra rakipte (turnPlayerId = 'bot')
    final botTurnState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'bot'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final botController = FakeMatchController(botTurnState);

    await tester.pumpWidget(_buildTestApp(botController));
    await tester.pump();

    final botTextField = tester.widget<TextField>(find.byType(TextField));
    expect(botTextField.readOnly, isTrue);
    expect(botTextField.decoration?.hintText, AppStrings.turnOpponentHint);
  });

  testWidgets('3. Kendi ve rakip balonları doğru tarafta', (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 10000,
      acceptedAnswers: const [
        AcceptedAnswerUiModel(playerId: 'bot', display: 'Baykuş'),
        AcceptedAnswerUiModel(playerId: 'me', display: 'Boğa'),
      ],
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    expect(find.byType(AnswerBubble), findsNWidgets(2));

    final bubbleBaykusFinder = find.ancestor(
      of: find.text('Baykuş'),
      matching: find.byType(AnswerBubble),
    );
    final bubbleBogaFinder = find.ancestor(
      of: find.text('Boğa'),
      matching: find.byType(AnswerBubble),
    );

    final bubbleBaykus = tester.widget<AnswerBubble>(bubbleBaykusFinder);
    expect(bubbleBaykus.isMe, isFalse);

    final bubbleBoga = tester.widget<AnswerBubble>(bubbleBogaFinder);
    expect(bubbleBoga.isMe, isTrue);

    // Hizalamaları kontrol et (AnswerBubble içindeki Align)
    final alignBaykus = tester.widget<Align>(
      find.descendant(of: bubbleBaykusFinder, matching: find.byType(Align)).first,
    );
    expect(alignBaykus.alignment, Alignment.centerLeft);

    final alignBoga = tester.widget<Align>(
      find.descendant(of: bubbleBogaFinder, matching: find.byType(Align)).first,
    );
    expect(alignBoga.alignment, Alignment.centerRight);
  });

  testWidgets('4. Boş gönderim controllerı çağırmaz, geçerli gönderim çağırır ve temizler',
      (tester) async {
    final state = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    // A: Tamamen boşken gönder
    await tester.tap(find.bySemanticsLabel(AppStrings.send));
    await tester.pump();
    expect(controller.submitCalled, isFalse);

    // B: Yalnızca boşluk karakterleri varken gönder
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.bySemanticsLabel(AppStrings.send));
    await tester.pump();
    expect(controller.submitCalled, isFalse);

    // C: Geçerli metin gönder
    await tester.enterText(find.byType(TextField), 'boğa');
    await tester.tap(find.bySemanticsLabel(AppStrings.send));
    await tester.pump();

    expect(controller.submitCalled, isTrue);
    expect(controller.lastSubmittedText, 'boğa');

    // Alan temizlenmiş olmalı
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('5. Kapat -> dialog -> onay leaveMatch çağırır, vazgeç çağırmaz',
      (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    // A: Kapat ikonuna bas -> Vazgeç
    await tester.tap(find.bySemanticsLabel(AppStrings.leaveMatch));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.leaveMatchConfirmTitle), findsOneWidget);
    expect(find.text(AppStrings.leaveMatchPrompt), findsOneWidget);

    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.leaveMatchConfirmTitle), findsNothing);
    expect(controller.leaveMatchCalled, isFalse);

    // B: Kapat ikonuna bas -> Onay (Çık)
    await tester.tap(find.bySemanticsLabel(AppStrings.leaveMatch));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.exit));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.leaveMatchConfirmTitle), findsNothing);
    expect(controller.leaveMatchCalled, isTrue);
  });

  testWidgets('6. Kalan süre 5 sn altında dolgu danger tonuna geçer', (tester) async {
    // A: 11 saniye (>= 5 sn) -> bright zemin
    final normalState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 11000,
    );
    final normalController = FakeMatchController(normalState);

    await tester.pumpWidget(_buildTestApp(normalController));
    await tester.pump();

    final normalCards = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).toList();
    final myNormalCard = normalCards.firstWhere((c) => c.name == AppStrings.you);
    expect(myNormalCard.isActive, isTrue);
    expect(myNormalCard.remainingSeconds, 11);

    // AnimatedContainer rengini kontrol et
    final brightContainerFinder = find.descendant(
      of: find.byType(PlayerCard).first,
      matching: find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            (w.decoration as BoxDecoration?)?.color == AppColors.bright,
      ),
    );
    expect(brightContainerFinder, findsOneWidget);

    // B: 4 saniye (<= 5 sn) -> dangerSoft zemin
    final dangerState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 4000,
    );
    final dangerController = FakeMatchController(dangerState);

    await tester.pumpWidget(_buildTestApp(dangerController));
    await tester.pump();

    final dangerCards = tester.widgetList<PlayerCard>(find.byType(PlayerCard)).toList();
    final myDangerCard = dangerCards.firstWhere((c) => c.name == AppStrings.you);
    expect(myDangerCard.remainingSeconds, 4);

    final dangerContainerFinder = find.descendant(
      of: find.byType(PlayerCard).first,
      matching: find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            (w.decoration as BoxDecoration?)?.color == AppColors.dangerSoft,
      ),
    );
    expect(dangerContainerFinder, findsOneWidget);
  });

  testWidgets('7. Reddedilen cevaplar (rejected) kırmızı kenarlık ile gösterilir, kendi sağda rakip solda',
      (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 10000,
      roundAttempts: const [
        RoundAttemptUiModel(playerId: 'bot', text: 'YanlışCevap1', isCorrect: false),
        RoundAttemptUiModel(playerId: 'me', text: 'YanlışCevap2', isCorrect: false),
        RoundAttemptUiModel(playerId: 'me', text: 'Boğa', isCorrect: true),
      ],
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    final bubbles = tester.widgetList<AnswerBubble>(find.byType(AnswerBubble)).toList();
    expect(bubbles.length, 3);

    // 1. Rakibin reddedilen cevabı: isMe: false, isRejected: true, showTail: true (ilk)
    expect(bubbles[0].text, 'YanlışCevap1');
    expect(bubbles[0].isMe, isFalse);
    expect(bubbles[0].isRejected, isTrue);
    expect(bubbles[0].showTail, isTrue);

    // 2. Kendi reddedilen cevabım: isMe: true, isRejected: true, showTail: true (yeni gönderici)
    expect(bubbles[1].text, 'YanlışCevap2');
    expect(bubbles[1].isMe, isTrue);
    expect(bubbles[1].isRejected, isTrue);
    expect(bubbles[1].showTail, isTrue);

    // 3. Kendi doğru cevabım: isMe: true, isRejected: false, showTail: false (aynı göndericinin devamı)
    expect(bubbles[2].text, 'Boğa');
    expect(bubbles[2].isMe, isTrue);
    expect(bubbles[2].isRejected, isFalse);
    expect(bubbles[2].showTail, isFalse);
  });

  testWidgets('7b. WhatsApp tarzı çentik gruplaması: art arda gelen aynı göndericinin yalnızca ilk balonunda çentik gösterilir',
      (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 10000,
      roundAttempts: const [
        RoundAttemptUiModel(playerId: 'me', text: 'Cevap1', isCorrect: true),
        RoundAttemptUiModel(playerId: 'me', text: 'Cevap2', isCorrect: true),
        RoundAttemptUiModel(playerId: 'bot', text: 'Cevap3', isCorrect: true),
        RoundAttemptUiModel(playerId: 'bot', text: 'Cevap4', isCorrect: true),
        RoundAttemptUiModel(playerId: 'me', text: 'Cevap5', isCorrect: true),
      ],
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    final bubbles = tester.widgetList<AnswerBubble>(find.byType(AnswerBubble)).toList();
    expect(bubbles.length, 5);

    expect(bubbles[0].showTail, isTrue);
    expect(bubbles[1].showTail, isFalse);
    expect(bubbles[2].showTail, isTrue);
    expect(bubbles[3].showTail, isFalse);
    expect(bubbles[4].showTail, isTrue);
  });

  testWidgets('8. Giriş alanında en fazla 40 karakter girilebilir ve sayaç görünmez',
      (tester) async {
    final state = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    // 50 karakterlik metin gir
    final longInput = 'a' * 50;
    await tester.enterText(find.byType(TextField), longInput);
    await tester.pump();

    // TextField controllerında en fazla 40 karakter olmalı
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text.length, 40);
    expect(textField.maxLength, 40);

    // Sayaç metni ("/40") görünmemeli
    expect(find.textContaining('/40'), findsNothing);
  });

  testWidgets('9. Çok yakın ipucu hapı sadece KENDİ denememizde görünür, rakipte görünmez',
      (tester) async {
    // A: Kendi denemem yakın -> lastFeedback nearMiss -> ipucu hapı görünür
    final myNearMissState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'me'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
      lastFeedback: MatchFeedbackType.nearMiss,
      feedbackCounter: 1,
    );
    final myController = FakeMatchController(myNearMissState);

    await tester.pumpWidget(_buildTestApp(myController));
    await tester.pump();

    expect(find.text(AppStrings.nearMiss), findsOneWidget);

    // B: Rakibin denemesi yakın -> lastFeedback null (mevcut mantık) -> ipucu hapı görünmez
    final opponentNearMissState = MatchUiState(
      matchState: testMatchState.copyWith(turnPlayerId: 'bot'),
      opponentName: 'Ahmet',
      remainingMs: 10000,
      roundAttempts: const [
        RoundAttemptUiModel(playerId: 'bot', text: 'Boğ', isCorrect: false),
      ],
      lastFeedback: null,
      feedbackCounter: 0,
    );
    final opponentController = FakeMatchController(opponentNearMissState);

    await tester.pumpWidget(_buildTestApp(opponentController, key: const ValueKey('opponent')));
    await tester.pump();

    expect(find.text(AppStrings.nearMiss), findsNothing);
    // Ama solda reddedilen balon görünür
    final bubble = tester.widget<AnswerBubble>(find.byType(AnswerBubble));
    expect(bubble.text, 'Boğ');
    expect(bubble.isMe, isFalse);
    expect(bubble.isRejected, isTrue);
  });

  testWidgets('10. Android sistem geri tuşuna basıldığında terk onay penceresi açılır', (tester) async {
    final state = MatchUiState(
      matchState: testMatchState,
      opponentName: 'Ahmet',
      remainingMs: 10000,
    );
    final controller = FakeMatchController(state);

    await tester.pumpWidget(_buildTestApp(controller));
    await tester.pump();

    expect(find.text(AppStrings.leaveMatchConfirmTitle), findsNothing);

    // Sistem geri tuşunu simüle et
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.leaveMatchConfirmTitle), findsOneWidget);
    expect(find.text(AppStrings.leaveMatchPrompt), findsOneWidget);
  });
}
