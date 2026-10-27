import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

Question _createQuestion({
  required String id,
  required String text,
  required Map<String, List<String>> answersMap,
}) {
  return Question(
    id: id,
    categoryId: 'test_category',
    text: text,
    answers: answersMap.entries.map((entry) {
      final normId = TextNormalizer.normalize(entry.key);
      final normAliases = {
        if (normId.isNotEmpty) normId,
        ...entry.value.map(TextNormalizer.normalize).where((s) => s.isNotEmpty),
      }.toList();

      return Answer(
        id: normId,
        display: entry.key,
        aliases: normAliases,
      );
    }).toList(),
  );
}

void main() {
  late List<Question> singleAnswerQuestions;

  setUp(() {
    singleAnswerQuestions = [
      _createQuestion(id: 'q1', text: 'Soru 1', answersMap: {'Ankara': []}),
      _createQuestion(id: 'q2', text: 'Soru 2', answersMap: {'İstanbul': []}),
      _createQuestion(id: 'q3', text: 'Soru 3', answersMap: {'İzmir': []}),
      _createQuestion(id: 'q4', text: 'Soru 4', answersMap: {'Bursa': []}),
      _createQuestion(id: 'q5', text: 'Soru 5', answersMap: {'Antalya': []}),
      _createQuestion(id: 'q6', text: 'Soru 6', answersMap: {'Adana': []}),
    ];
  });

  group('MADDE 1: MatchEngine.submit Sanitization & Length Boundary (Dart)', () {
    const config = MatchConfig(
      roundsToWin: 2,
      maxTotalRounds: 5,
      answerSeconds: 15,
      minSubmitIntervalMs: 0,
    );

    test('girdi boşlukları motora girmeden temizlenir', () {
      final start = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: singleAnswerQuestions,
        random: math.Random(42),
        nowMs: 1000,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5'],
      );

      final res = MatchEngine.submit(
        state: start.state,
        playerId: 'p1',
        rawInput: '   ankara \t \n  ',
        nowMs: 1100,
      );

      expect(res.events.any((e) => e is AnswerAccepted), isTrue);
      expect(res.state.currentRoundAttempts.first.rawInput, 'ankara');
      expect(res.state.currentRoundAttempts.first.displayText, 'Ankara');
    });

    test('40 karakteri aşan yanlış cevap 40 karaktere kırpılır ve WrongAnswer eventinde kırpılmış döner', () {
      final start = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: singleAnswerQuestions,
        random: math.Random(42),
        nowMs: 1000,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5'],
      );

      const longInput = 'bu cok ama cok uzun bir yanlis cevaptir kesinlikle 40 karakteri asiyor';
      final res = MatchEngine.submit(
        state: start.state,
        playerId: 'p1',
        rawInput: longInput,
        nowMs: 1100,
      );

      final wrongEvent = res.events.whereType<WrongAnswer>().firstOrNull;
      expect(wrongEvent, isNotNull);
      expect(wrongEvent!.rawInput.length, lessThanOrEqualTo(40));
      expect(wrongEvent.rawInput, longInput.substring(0, 40));
      expect(res.state.currentRoundAttempts.first.rawInput, longInput.substring(0, 40));
    });

    test('yalnızca boşluk içeren girdi empty_input döner', () {
      final start = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: singleAnswerQuestions,
        random: math.Random(42),
        nowMs: 1000,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5'],
      );

      final res = MatchEngine.submit(
        state: start.state,
        playerId: 'p1',
        rawInput: '   \t \n  ',
        nowMs: 1100,
      );

      expect(res.events.first, isA<Ignored>());
      expect((res.events.first as Ignored).reason, 'empty_input');
      expect(res.state.currentRoundAttempts, isEmpty);
    });
  });

  group('MADDE 3: Beraberlik Tavanı (maxTotalRounds = 5) Dart Motoru', () {
    const config = MatchConfig(
      roundsToWin: 2,
      maxTotalRounds: 5,
      answerSeconds: 15,
      minSubmitIntervalMs: 0,
    );

    test('5 tur berabere biterse maç draw_limit_reached ile sonuçlanır', () {
      var current = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: singleAnswerQuestions,
        random: math.Random(42),
        nowMs: 1000,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      );

      final answers = ['ankara', 'istanbul', 'izmir', 'bursa', 'antalya'];

      for (var r = 1; r <= 5; r++) {
        final activePlayer = current.state.turnPlayerId!;
        final submitRes = MatchEngine.submit(
          state: current.state,
          playerId: activePlayer,
          rawInput: answers[r - 1],
          nowMs: 1000 + r * 1000,
        );

        if (r < 5) {
          expect(submitRes.state.phase, MatchPhase.roundEnded);
          current = MatchEngine.startNextRound(
            state: submitRes.state,
            questions: singleAnswerQuestions,
            random: math.Random(42),
            nowMs: 1000 + r * 1000 + 500,
            questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
          );
        } else {
          current = submitRes;
        }
      }

      expect(current.state.phase, MatchPhase.matchFinished);
      expect(current.state.winnerId, isNull);
      expect(current.state.endedBy, 'draw_limit_reached');
      expect(current.state.totalRoundsPlayed, 5);
      expect(current.events.any((e) => e is MatchFinished && e.reason == 'draw_limit_reached'), isTrue);
    });

    test('5. turun sonunda skor eşit değilse (1-0) lider normal kazanır', () {
      var current = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: singleAnswerQuestions,
        random: math.Random(42),
        nowMs: 1000,
        questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
      );

      // 1. tur timeout ile p2'ye gitsin (0-1)
      final timeoutRes = MatchEngine.checkTimeout(
        state: current.state,
        nowMs: current.state.deadlineMs + 500,
      );
      expect(timeoutRes.state.phase, MatchPhase.roundEnded);

      current = timeoutRes;
      final answers = ['istanbul', 'izmir', 'bursa', 'antalya'];

      // Kalan 4 tur berabere bitsin
      for (var r = 2; r <= 5; r++) {
        current = MatchEngine.startNextRound(
          state: current.state,
          questions: singleAnswerQuestions,
          random: math.Random(42),
          nowMs: 20000 + r * 1000,
          questionOrder: ['q1', 'q2', 'q3', 'q4', 'q5', 'q6'],
        );

        final activePlayer = current.state.turnPlayerId!;
        current = MatchEngine.submit(
          state: current.state,
          playerId: activePlayer,
          rawInput: answers[r - 2],
          nowMs: 20000 + r * 1000 + 500,
        );
      }

      expect(current.state.phase, MatchPhase.matchFinished);
      expect(current.state.winnerId, 'p2');
      expect(current.state.endedBy, 'normal');
      expect(current.state.totalRoundsPlayed, 5);
    });
  });

  group('MADDE 3: MatchController & Protocol draw_limit_reached Voided', () {
    test('VoidedServerMessage draw_limit_reached sebebini doğru ayrıştırır', () {
      final msg = parseServerMessage('{"t":"voided","reason":"draw_limit_reached"}');

      expect(msg, isA<VoidedServerMessage>());
      expect((msg as VoidedServerMessage).reason, 'draw_limit_reached');
    });

    test('VoidedServerMessage bilinmeyen gelecekteki bir sebep geldiğinde geriye dönük uyumlulukla ayrıştırır', () {
      final msg = parseServerMessage('{"t":"voided","reason":"server_maintenance_shutdown"}');

      expect(msg, isA<VoidedServerMessage>());
      expect((msg as VoidedServerMessage).reason, 'server_maintenance_shutdown');
    });

    test('MatchController draw_limit_reached ile biten maçta isVoided=true yapar', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(matchControllerProvider.notifier);

      // draw_limit_reached ile biten bir MatchState oluştur
      const state = MatchState(
        config: MatchConfig(roundsToWin: 2, maxTotalRounds: 5),
        playerIds: ['p1', 'bot'],
        scores: {'p1': 0, 'bot': 0},
        decisiveRounds: 0,
        totalRoundsPlayed: 5,
        phase: MatchPhase.matchFinished,
        currentQuestion: null,
        usedAnswerIds: {},
        turnPlayerId: null,
        deadlineMs: 0,
        remainingNearMisses: {},
        usedQuestionIds: {},
        roundHistory: [],
        currentRoundAttempts: [],
        winnerId: null,
        endedBy: 'draw_limit_reached',
      );

      controller.applyEngineResultForTesting(
        const EngineResult(state, [MatchFinished(null, 'draw_limit_reached')]),
      );

      expect(container.read(matchControllerProvider).isVoided, isTrue);
      expect(container.read(matchControllerProvider).isLoading, isFalse);
    });
  });
}
