import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

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
  late List<Question> sampleQuestions;

  setUp(() {
    sampleQuestions = [
      _createQuestion(
        id: 'q1',
        text: 'Araba markaları',
        answersMap: {
          'Audi': ['aude_alias'],
          'BMW': [],
          'Mercedes': ['merco'],
          'Volkswagen': [],
        },
      ),
      _createQuestion(
        id: 'q2',
        text: 'Avrupa başkentleri',
        answersMap: {
          'Paris': ['parsi_alias'],
          'Berlin': [],
          'Roma': [],
          'Madrid': [],
        },
      ),
      _createQuestion(
        id: 'q3',
        text: 'Programlama dilleri',
        answersMap: {
          'Dart': [],
          'Python': [],
          'JavaScript': ['js'],
        },
      ),
      _createQuestion(
        id: 'q4',
        text: 'Meyveler',
        answersMap: {
          'Elma': [],
          'Armut': [],
        },
      ),
    ];
  });

  group('MatchEngine Testleri', () {
    test('1. 3 sonuçlanan tur tamamlandığında maç biter (2-0 olsa bile 3. tur oynanır)', () {
      final config = const MatchConfig(totalDecisiveRounds: 3);
      final random = math.Random(1);

      // Başlangıç: Tur 1
      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      expect(state.phase, equals(MatchPhase.roundActive));
      expect(state.decisiveRounds, equals(0));

      // 1. Tur: p1 doğru cevap verir, p2 süre aşımına uğrar -> p1 kazanır
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'audi', nowMs: 2000);
      state = res.state;
      expect(res.events.first, isA<AnswerAccepted>());

      // p2 süre aşımı
      res = MatchEngine.checkTimeout(state: state, nowMs: 2000 + config.answerSeconds * 1000 + 10);
      state = res.state;
      expect(res.events.first, isA<RoundWon>());
      expect((res.events.first as RoundWon).winnerId, equals('p1'));
      expect(state.phase, equals(MatchPhase.roundEnded));
      expect(state.scores['p1'], equals(1));
      expect(state.scores['p2'], equals(0));
      expect(state.decisiveRounds, equals(1));

      // 2. Tur başlat: Skor 1 - 0
      res = MatchEngine.startNextRound(state: state, questions: sampleQuestions, random: random, nowMs: 25000);
      state = res.state;
      expect(state.phase, equals(MatchPhase.roundActive));

      // 2. Tur: p2 başlar, p2 süre aşımı -> p1 kazanır (2 - 0)
      res = MatchEngine.checkTimeout(state: state, nowMs: 25000 + config.answerSeconds * 1000 + 10);
      state = res.state;
      expect(res.events.first, isA<RoundWon>());
      expect(state.scores['p1'], equals(2));
      expect(state.scores['p2'], equals(0));
      expect(state.decisiveRounds, equals(2));

      // 2 tur bitmesine rağmen maç bitmemelidir (3 sonuçlanan tur kuralı)
      expect(res.events.any((e) => e is MatchFinished), isFalse);

      // 3. Tur başlat: Skor 1 - 1
      res = MatchEngine.startNextRound(state: state, questions: sampleQuestions, random: random, nowMs: 50000);
      state = res.state;
      expect(state.phase, equals(MatchPhase.roundActive));

      // 3. Tur: Başlayan oyuncu p1 süre aşımına uğrar -> p2 kazanır (Skor: 2 - 1)
      final activeStarter = state.turnPlayerId!;
      final opponent = state.opponentOf(activeStarter);
      res = MatchEngine.checkTimeout(state: state, nowMs: 50000 + config.answerSeconds * 1000 + 10);
      state = res.state;
      expect((res.events.first as RoundWon).winnerId, equals(opponent));
      expect(state.scores['p1'], equals(2));
      expect(state.scores['p2'], equals(1));

      // 3 sonuçlanan tur bitti, maç bitmeli
      expect(state.phase, equals(MatchPhase.matchFinished));
      expect(state.decisiveRounds, equals(3));
      expect(res.events.any((e) => e is MatchFinished), isTrue);
      final finishEvent = res.events.firstWhere((e) => e is MatchFinished) as MatchFinished;
      expect(finishEvent.winnerId, equals(activeStarter));
      expect(state.winnerId, equals(activeStarter));
      expect(state.endedBy, equals('normal'));
    });

    test('2. Yanlış ve tekrar cevap sırayı ve deadlineı değiştirmez, yalnızca süre dolunca tur kaybedilir', () {
      final config = const MatchConfig(answerSeconds: 15, graceMs: 0);
      final random = math.Random(42);

      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [sampleQuestions[0]],
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      final initialDeadline = state.deadlineMs;
      expect(state.turnPlayerId, equals('p1'));

      // 1. Yanlış cevap gönderilir: tur kaybedilmez, sıra ve deadline aynı kalır
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'tamamen_yanlis_bir_cevap',
        nowMs: 2000,
      );
      state = res.state;
      expect(res.events.first, isA<WrongAnswer>());
      expect((res.events.first as WrongAnswer).playerId, equals('p1'));
      expect(state.turnPlayerId, equals('p1'));
      expect(state.deadlineMs, equals(initialDeadline));
      expect(state.phase, equals(MatchPhase.roundActive));
      expect(state.currentRoundAttempts.length, equals(1));
      expect(state.currentRoundAttempts.first.resultType, equals(AttemptResultType.wrong));

      // 2. Bir başka yanlış cevap daha gönderilir: yine sıra ve deadline aynı
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'ikinci_yanlis_cevap',
        nowMs: 3000,
      );
      state = res.state;
      expect(res.events.first, isA<WrongAnswer>());
      expect(state.turnPlayerId, equals('p1'));
      expect(state.deadlineMs, equals(initialDeadline));

      // 3. Oyuncu ardından doğru cevap verir: cevap kabul edilir ve sıra rakibe geçer!
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 4000,
      );
      state = res.state;
      expect(res.events.first, isA<AnswerAccepted>());
      expect(state.turnPlayerId, equals('p2'));
      expect(state.usedAnswerIds, contains('audi'));

      // 4. p2 daha önce söylenmiş cevabı ("audi") söyler: kabul edilmez ama tur kaybedilmez
      final p2Deadline = state.deadlineMs;
      res = MatchEngine.submit(
        state: state,
        playerId: 'p2',
        rawInput: 'audi',
        nowMs: 5000,
      );
      state = res.state;
      expect(res.events.first, isA<AlreadySaid>());
      expect((res.events.first as AlreadySaid).playerId, equals('p2'));
      expect(state.turnPlayerId, equals('p2'));
      expect(state.deadlineMs, equals(p2Deadline));

      // 5. p2 süresini geçirir -> Yalnızca bu durumda tur kaybedilir!
      res = MatchEngine.checkTimeout(state: state, nowMs: p2Deadline + 1);
      state = res.state;
      expect(res.events.first, isA<RoundWon>());
      final roundWonTimeout = res.events.first as RoundWon;
      expect(roundWonTimeout.winnerId, equals('p1'));
      expect(roundWonTimeout.reason, equals(RoundEndReason.timeout));
      expect(state.phase, equals(MatchPhase.roundEnded));
      expect(state.scores['p1'], equals(1));
    });

    test('3. Kötüye kullanım sınırları: 600 msden hızlı deneme ve 25 deneme sonrası yoksayılır, sıra değişince sayaç sıfırlanır', () {
      final config = const MatchConfig(answerSeconds: 60, minSubmitIntervalMs: 600, maxAttemptsPerTurn: 25);
      final random = math.Random(10);

      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [sampleQuestions[0]],
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      expect(state.turnPlayerId, equals('p1'));

      // 1. Sırası olmayan p2 dener -> not_player_turn
      final outOfTurnRes = MatchEngine.submit(
        state: state,
        playerId: 'p2',
        rawInput: 'audi',
        nowMs: 2000,
      );
      expect(outOfTurnRes.events.first, isA<Ignored>());
      expect((outOfTurnRes.events.first as Ignored).reason, equals('not_player_turn'));

      // 2. p1 geçerli bir deneme yapar (t = 2000)
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'yanlis_1',
        nowMs: 2000,
      );
      state = res.state;
      expect(res.events.first, isA<WrongAnswer>());
      expect(state.currentTurnAttempts, equals(1));

      // 3. p1 400 ms sonra (600 ms dolmadan) tekrar dener (t = 2400) -> ignored(tooFast)
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'yanlis_2',
        nowMs: 2400,
      );
      expect(res.events.first, isA<Ignored>());
      expect((res.events.first as Ignored).reason, equals('tooFast'));
      // Sayaca ve RoundRecord'a eklenmez
      expect(res.state.currentTurnAttempts, equals(1));
      expect(res.state.currentRoundAttempts.length, equals(1));

      // 4. p1 600 ms dolduktan sonra dener (t = 2650) -> geçerli
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'yanlis_2',
        nowMs: 2650,
      );
      state = res.state;
      expect(res.events.first, isA<WrongAnswer>());
      expect(state.currentTurnAttempts, equals(2));

      // 5. 25 deneme sınırına kadar yanlış cevap gönder
      int currentNow = 3300;
      while (state.currentTurnAttempts < 25) {
        res = MatchEngine.submit(
          state: state,
          playerId: 'p1',
          rawInput: 'yanlis_${state.currentTurnAttempts + 1}',
          nowMs: currentNow,
        );
        state = res.state;
        currentNow += 700;
      }
      expect(state.currentTurnAttempts, equals(25));

      // 6. 26. deneme -> ignored(tooManyAttempts)
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: currentNow,
      );
      expect(res.events.first, isA<Ignored>());
      expect((res.events.first as Ignored).reason, equals('tooManyAttempts'));
      expect(res.state.turnPlayerId, equals('p1'));

      // 7. p1 süre aşımına uğrar, 2. tur başlar ve sıra değişince sayaç 0 olur
      final timeoutRes = MatchEngine.checkTimeout(state: state, nowMs: state.deadlineMs + 1);
      final nextRoundRes = MatchEngine.startNextRound(
        state: timeoutRes.state,
        questions: sampleQuestions,
        random: random,
        nowMs: state.deadlineMs + 2000,
      );
      expect(nextRoundRes.state.currentTurnAttempts, equals(0));
      expect(nextRoundRes.state.turnPlayerId, equals('p2'));
    });

    test('4. Çok Yakın (Near Miss) ipucu turda oyuncu başına 1 kez verilir, sonraki yakın cevaplar normal yanlış sayılır, tur kaybedilmez', () {
      final config = const MatchConfig(nearMissPerRound: 1, answerSeconds: 15);
      final random = math.Random(1);

      final testQ = _createQuestion(
        id: 'q_near',
        text: 'Test Sorusu',
        answersMap: {
          'Audi': [], // 4 harf -> 1 düzenleme tolerans
          'Bmw': [], // 3 harf -> 0 tolerans (kapalı)
          'Volkswagen': [], // 10 harf -> 2 düzenleme tolerans
        },
      );

      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [testQ],
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      final initialDeadline = state.deadlineMs;

      // 4.1: "aude" -> "Audi" (4 harf, 1 düzenleme) -> NearMiss
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'aude',
        nowMs: 2000,
      );
      state = res.state;
      expect(res.events.length, equals(1));
      expect(res.events.first, isA<NearMiss>());
      expect((res.events.first as NearMiss).playerId, equals('p1'));
      // Süre sıfırlanmaz, deadline ve sıra aynı kalır, hak düşer
      expect(state.deadlineMs, equals(initialDeadline));
      expect(state.turnPlayerId, equals('p1'));
      expect(state.remainingNearMisses['p1'], equals(0));

      // 4.2: İkinci kez yakın hata yapıldığında hakkı bittiği için artık WrongAnswer döner, TUR KAYBEDİLMEZ!
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'aude',
        nowMs: 3000,
      );
      state = res.state;
      expect(res.events.first, isA<WrongAnswer>());
      expect(state.turnPlayerId, equals('p1'));
      expect(state.phase, equals(MatchPhase.roundActive));

      // 4.3: 3 harf ve altı tolerans kapalıdır -> direkt WrongAnswer döner
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'bmv',
        nowMs: 4000,
      );
      expect(res.events.first, isA<WrongAnswer>());
    });

    test('5. Cevapların tükenmesiyle turun berabere bitmesi, karar turu sayılmaması ve maçı uzatması', () {
      final config = const MatchConfig(totalDecisiveRounds: 3);
      final random = math.Random(7);

      final fruitQ = _createQuestion(
        id: 'q_fruit',
        text: 'İki Meyve',
        answersMap: {
          'Elma': [],
          'Armut': [],
        },
      );

      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [fruitQ],
        random: random,
        nowMs: 1000,
      );
      var state = res.state;

      // 1. Cevap: p1 'elma'
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'elma', nowMs: 2000);
      state = res.state;
      expect(res.events.first, isA<AnswerAccepted>());

      // 2. Cevap: p2 'armut' -> Soru tükendi!
      res = MatchEngine.submit(state: state, playerId: 'p2', rawInput: 'armut', nowMs: 3000);
      state = res.state;

      // Beraberlik olayları ve durumu
      expect(res.events.any((e) => e is RoundDrawn), isTrue);
      final drawEvent = res.events.firstWhere((e) => e is RoundDrawn) as RoundDrawn;
      expect(drawEvent.reason, equals(RoundEndReason.exhausted));

      // Beraberlik karar turu sayılmaz
      expect(state.decisiveRounds, equals(0));
      expect(state.totalRoundsPlayed, equals(1));
      expect(state.scores['p1'], equals(0));
      expect(state.scores['p2'], equals(0));
      expect(state.phase, equals(MatchPhase.roundEnded));
      expect(state.winnerId, isNull);
    });

    test('6. forfeit() maçı hemen bitirir, kazanan rakip olur ve sebep forfeit olur', () {
      final config = const MatchConfig();
      final random = math.Random(1);

      final startRes = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random,
        nowMs: 1000,
      );

      // p1 maçı terk eder
      final forfeitRes = MatchEngine.forfeit(
        state: startRes.state,
        playerId: 'p1',
        nowMs: 2500,
      );

      final state = forfeitRes.state;
      expect(state.phase, equals(MatchPhase.matchFinished));
      expect(state.winnerId, equals('p2'));
      expect(state.endedBy, equals('forfeit'));

      expect(forfeitRes.events.length, equals(1));
      expect(forfeitRes.events.first, isA<MatchFinished>());
      final finishEvent = forfeitRes.events.first as MatchFinished;
      expect(finishEvent.winnerId, equals('p2'));
      expect(finishEvent.reason, equals('forfeit'));

      expect(state.roundHistory.length, equals(1));
      expect(state.roundHistory.first.reason, equals(RoundEndReason.forfeit));
      expect(state.roundHistory.first.winnerId, equals('p2'));
    });

    test('7. Grace period sınır testleri (tam sınırda geçerli, 1ms sonrasında timeout)', () {
      final config = const MatchConfig(answerSeconds: 10, graceMs: 500);
      final random = math.Random(1);

      final res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random,
        nowMs: 1000,
      );
      final state = res.state;

      // Tam sınırda gönderilen cevap kabul edilmelidir
      final borderValidRes = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 11500,
      );
      expect(borderValidRes.events.first, isA<AnswerAccepted>());

      // Sınırı 1ms geçen gönderim timeout olmalıdır
      final borderOverRes = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'audi',
        nowMs: 11501,
      );
      expect(borderOverRes.events.first, isA<RoundWon>());
      expect((borderOverRes.events.first as RoundWon).reason, equals(RoundEndReason.timeout));

      // checkTimeout için de tam sınırda timeout oluşmamalı, 1ms sonrasında oluşmalı
      final checkBorderValid = MatchEngine.checkTimeout(state: state, nowMs: 11500);
      expect(checkBorderValid.events, isEmpty);

      final checkBorderOver = MatchEngine.checkTimeout(state: state, nowMs: 11501);
      expect(checkBorderOver.events.first, isA<RoundWon>());
      expect((checkBorderOver.events.first as RoundWon).reason, equals(RoundEndReason.timeout));
    });

    test('8. RoundRecord tüm denemeleri ve sonucu eksiksiz kaydeder', () {
      final config = const MatchConfig(answerSeconds: 15, nearMissPerRound: 1);
      final random = math.Random(1);

      final testQ = _createQuestion(
        id: 'q_history',
        text: 'Tarih Sorusu',
        answersMap: {
          'Ankara': ['ank'],
          'Paris': [],
          'Berlin': [],
        },
      );

      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [testQ],
        random: random,
        nowMs: 1000,
      );
      var state = res.state;

      // 1. Deneme: p1 doğru (ankara) t=2000
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'ankara', nowMs: 2000);
      state = res.state;

      // 2. Deneme: p2 near miss (parsi) t=5000
      res = MatchEngine.submit(state: state, playerId: 'p2', rawInput: 'parsi', nowMs: 5000);
      state = res.state;

      // 3. Deneme: p2 doğru (paris) t=8000
      res = MatchEngine.submit(state: state, playerId: 'p2', rawInput: 'paris', nowMs: 8000);
      state = res.state;

      // 4. Deneme: p1 yanlış (xyz) t=11000
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'xyz', nowMs: 11000);
      state = res.state;

      // 5. p1 süre aşımı -> Tur biter
      res = MatchEngine.checkTimeout(state: state, nowMs: state.deadlineMs + 10);
      state = res.state;

      expect(state.roundHistory.length, equals(1));
      final record = state.roundHistory.first;

      expect(record.questionId, equals('q_history'));
      expect(record.starterPlayerId, equals('p1'));
      expect(record.winnerId, equals('p2'));
      expect(record.reason, equals(RoundEndReason.timeout));

      expect(record.attempts.length, equals(5));
      expect(record.attempts[0].resultType, equals(AttemptResultType.correct));
      expect(record.attempts[1].resultType, equals(AttemptResultType.nearMiss));
      expect(record.attempts[2].resultType, equals(AttemptResultType.correct));
      expect(record.attempts[3].resultType, equals(AttemptResultType.wrong));
      expect(record.attempts[4].resultType, equals(AttemptResultType.timeout));
    });

    test('9. minAnswersPerQuestion eşiğinin altındaki soru hiç seçilmez', () {
      final qFew = _createQuestion(
        id: 'q_few',
        text: 'Az Cevaplı Soru (2 Cevap)',
        answersMap: {'Cevap1': [], 'Cevap2': []},
      );
      final qAdequate1 = _createQuestion(
        id: 'q_adeq1',
        text: 'Yeterli Soru 1 (10 Cevap)',
        answersMap: {for (var i = 1; i <= 10; i++) 'Cevap$i': []},
      );
      final qAdequate2 = _createQuestion(
        id: 'q_adeq2',
        text: 'Yeterli Soru 2 (12 Cevap)',
        answersMap: {for (var i = 1; i <= 12; i++) 'Cevap$i': []},
      );

      final config = const MatchConfig(minAnswersPerQuestion: 10);
      final random = math.Random(123);

      for (int i = 0; i < 15; i++) {
        final res = MatchEngine.start(
          config: config,
          playerIds: ['p1', 'p2'],
          questions: [qFew, qAdequate1, qAdequate2],
          random: random,
          nowMs: 1000,
        );
        expect(res.state.currentQuestion!.id, isNot(equals('q_few')));
        expect(res.state.currentQuestion!.answers.length, greaterThanOrEqualTo(10));
      }
    });

    test('10. minAnswersPerQuestion sonrası havuz yetersizse (boşsa) hata fırlatır', () {
      final qFew = _createQuestion(
        id: 'q_few',
        text: 'Az Cevaplı Soru (2 Cevap)',
        answersMap: {'Cevap1': [], 'Cevap2': []},
      );

      final config = const MatchConfig(minAnswersPerQuestion: 10);
      final random = math.Random(1);

      expect(
        () => MatchEngine.start(
          config: config,
          playerIds: ['p1', 'p2'],
          questions: [qFew],
          random: random,
          nowMs: 1000,
        ),
        throwsArgumentError,
      );
    });

    test('11. minAnswersPerQuestion varsayılan 0 eski davranışı korur', () {
      final qFew = _createQuestion(
        id: 'q_few',
        text: 'Az Cevaplı Soru (2 Cevap)',
        answersMap: {'Cevap1': [], 'Cevap2': []},
      );

      final config = const MatchConfig();
      expect(config.minAnswersPerQuestion, equals(0));

      final random = math.Random(1);
      final res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [qFew],
        random: random,
        nowMs: 1000,
      );
      expect(res.state.currentQuestion!.id, equals('q_few'));
    });
  });
}
