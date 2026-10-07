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

      // 1. Tur: p1 kazanır (p2 yanlış cevap verir)
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'audi', nowMs: 2000);
      state = res.state;
      expect(res.events.first, isA<AnswerAccepted>());

      res = MatchEngine.submit(state: state, playerId: 'p2', rawInput: 'yanlis_cevap_123', nowMs: 3000);
      state = res.state;
      expect(res.events.first, isA<RoundWon>());
      expect((res.events.first as RoundWon).winnerId, equals('p1'));
      expect(state.phase, equals(MatchPhase.roundEnded));
      expect(state.scores['p1'], equals(1));
      expect(state.scores['p2'], equals(0));
      expect(state.decisiveRounds, equals(1));

      // 2. Tur başlat: Skor 1 - 0
      res = MatchEngine.startNextRound(state: state, questions: sampleQuestions, random: random, nowMs: 5000);
      state = res.state;
      expect(state.phase, equals(MatchPhase.roundActive));

      // 2. Tur: p1 tekrar kazanır (p2 süre aşımı)
      res = MatchEngine.checkTimeout(state: state, nowMs: 5000 + config.answerSeconds * 1000 + 10);
      state = res.state;
      expect(res.events.first, isA<RoundWon>());
      expect(state.phase, equals(MatchPhase.roundEnded));
      expect(state.scores['p1'], equals(2));
      expect(state.scores['p2'], equals(0));
      expect(state.decisiveRounds, equals(2));

      // 2 - 0 olmasına rağmen maç bitmemelidir (3 sonuçlanan tur kuralı)
      expect(res.events.any((e) => e is MatchFinished), isFalse);

      // 3. Tur başlat: Skor 2 - 0
      res = MatchEngine.startNextRound(state: state, questions: sampleQuestions, random: random, nowMs: 25000);
      state = res.state;
      expect(state.phase, equals(MatchPhase.roundActive));

      // 3. Tur: p2 kazanır (p1 yanlış cevap verir)
      final activeStarter = state.turnPlayerId!;
      final opponent = state.opponentOf(activeStarter);
      res = MatchEngine.submit(state: state, playerId: activeStarter, rawInput: 'kesinlikle_yanlis_xyz', nowMs: 26000);
      state = res.state;
      expect((res.events.first as RoundWon).winnerId, equals(opponent));

      // 3 sonuçlanan tur bitti, maç bitmeli
      expect(state.phase, equals(MatchPhase.matchFinished));
      expect(state.decisiveRounds, equals(3));
      expect(res.events.any((e) => e is MatchFinished), isTrue);
      final finishEvent = res.events.firstWhere((e) => e is MatchFinished) as MatchFinished;
      expect(finishEvent.winnerId, equals('p1')); // 2 - 1 skorla p1 şampiyon
      expect(state.winnerId, equals('p1'));
    });

    test('2. Süre dolumu, tekrar cevap ve yanlış cevapla turun kaybedilmesi ve rakibin puan alması', () {
      final config = const MatchConfig(answerSeconds: 15, graceMs: 0);
      final random = math.Random(42);

      // A: checkTimeout ile süre aşımı
      var res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      expect(state.turnPlayerId, equals('p1'));

      res = MatchEngine.checkTimeout(state: state, nowMs: 1000 + 15000 + 1);
      expect(res.events.length, equals(1));
      expect(res.events.first, isA<RoundWon>());
      final roundWonTimeout = res.events.first as RoundWon;
      expect(roundWonTimeout.winnerId, equals('p2'));
      expect(roundWonTimeout.reason, equals(RoundEndReason.timeout));
      expect(res.state.scores['p2'], equals(1));

      // B: Süresi geçmiş submit ile süre aşımı
      res = MatchEngine.startNextRound(
        state: res.state,
        questions: sampleQuestions,
        random: random,
        nowMs: 20000,
      );
      state = res.state;
      final starter = state.turnPlayerId!;
      final opponent = state.opponentOf(starter);

      res = MatchEngine.submit(
        state: state,
        playerId: starter,
        rawInput: 'audi',
        nowMs: 20000 + 15000 + 100, // Süre dolduktan sonra cevap verildi
      );
      expect(res.events.first, isA<RoundWon>());
      final timeoutSubmit = res.events.first as RoundWon;
      expect(timeoutSubmit.winnerId, equals(opponent));
      expect(timeoutSubmit.reason, equals(RoundEndReason.timeout));

      // C: Tekrar eden cevapla kaybetme
      res = MatchEngine.startNextRound(
        state: res.state,
        questions: [sampleQuestions[0]], // 'Araba markaları'
        random: random,
        nowMs: 40000,
      );
      state = res.state;
      final currentStarter = state.turnPlayerId!;
      final otherPlayer = state.opponentOf(currentStarter);

      // Starter doğru cevap verir
      res = MatchEngine.submit(
        state: state,
        playerId: currentStarter,
        rawInput: 'audi',
        nowMs: 41000,
      );
      state = res.state;
      expect(state.turnPlayerId, equals(otherPlayer));

      // Diğer oyuncu aynı cevabı tekrar söyler
      res = MatchEngine.submit(
        state: state,
        playerId: otherPlayer,
        rawInput: 'audi',
        nowMs: 42000,
      );
      expect(res.events.first, isA<RoundWon>());
      final repeatedWon = res.events.first as RoundWon;
      expect(repeatedWon.winnerId, equals(currentStarter));
      expect(repeatedWon.reason, equals(RoundEndReason.repeated));

      // D: Yanlış cevapla kaybetme (near miss hakkı kalmayınca veya çok alakasız kelimede)
      res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [sampleQuestions[0]],
        random: random,
        nowMs: 1000,
      );
      res = MatchEngine.submit(
        state: res.state,
        playerId: 'p1',
        rawInput: 'tamamen_alakasiz_ve_uzun_yanlis',
        nowMs: 2000,
      );
      expect(res.events.first, isA<RoundWon>());
      final wrongWon = res.events.first as RoundWon;
      expect(wrongWon.winnerId, equals('p2'));
      expect(wrongWon.reason, equals(RoundEndReason.wrong));
    });

    test('3. Sıra dışı cevap ve boş girdinin yoksayılması', () {
      final config = const MatchConfig();
      final random = math.Random(10);

      final res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random,
        nowMs: 1000,
      );
      var state = res.state;
      expect(state.turnPlayerId, equals('p1'));

      // Sırası olmayan p2 cevap vermeye çalışır
      final outOfTurnRes = MatchEngine.submit(
        state: state,
        playerId: 'p2',
        rawInput: 'audi',
        nowMs: 2000,
      );
      expect(outOfTurnRes.events.first, isA<Ignored>());
      expect((outOfTurnRes.events.first as Ignored).reason, equals('not_player_turn'));
      expect(outOfTurnRes.state.turnPlayerId, equals('p1'));
      expect(outOfTurnRes.state.deadlineMs, equals(state.deadlineMs));

      // p1 boş girdi gönderir
      final emptyRes1 = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: '   ',
        nowMs: 3000,
      );
      expect(emptyRes1.events.first, isA<Ignored>());
      expect((emptyRes1.events.first as Ignored).reason, equals('empty_input'));
      expect(emptyRes1.state.deadlineMs, equals(state.deadlineMs));

      final emptyRes2 = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: '...',
        nowMs: 3000,
      );
      expect(emptyRes2.events.first, isA<Ignored>());
      expect((emptyRes2.events.first as Ignored).reason, equals('empty_input'));
    });

    test('4. Çok Yakın (Near Miss) kuralları ve sınırları', () {
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

      // 4.1: "aude" -> "Audi" (4 harf, 1 düzenleme) tetiklenmeli
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

      // 4.2: İkinci kez hata yapıldığında hakkı kalmadığı için kaybeder
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'aude',
        nowMs: 3000,
      );
      expect(res.events.first, isA<RoundWon>());
      expect((res.events.first as RoundWon).winnerId, equals('p2'));
      expect((res.events.first as RoundWon).reason, equals(RoundEndReason.wrong));

      // 4.3: 3 harf ve altı tolerans kapalıdır (BMW hedefi için 'bmv' near miss olamaz)
      res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [testQ],
        random: random,
        nowMs: 10000,
      );
      state = res.state;
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'bmv', // 3 harfli kelimede 1 harf fark
        nowMs: 11000,
      );
      expect(res.events.first, isA<RoundWon>());
      expect((res.events.first as RoundWon).reason, equals(RoundEndReason.wrong));

      // 4.4: Komşu harf yer değiştirmesi (transposition) 1 maliyetindedir
      res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [testQ],
        random: random,
        nowMs: 20000,
      );
      state = res.state;
      res = MatchEngine.submit(
        state: state,
        playerId: 'p1',
        rawInput: 'auid', // 'i' ve 'd' yer değiştirmiş
        nowMs: 21000,
      );
      expect(res.events.first, isA<NearMiss>());

      // 4.5: Zaten söylenmiş bir cevaba yakınlık Near Miss tetiklemez
      res = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: [testQ],
        random: random,
        nowMs: 30000,
      );
      state = res.state;
      // p1 Audi der (kullanılmış olur)
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'audi', nowMs: 31000);
      state = res.state;
      expect(state.usedAnswerIds, contains('audi'));

      // p2 'aude' der (kullanılmış Audi'ye yakın ama geriye kalan Bmw ve Volkswagen'e uzak)
      res = MatchEngine.submit(state: state, playerId: 'p2', rawInput: 'aude', nowMs: 32000);
      expect(res.events.first, isA<RoundWon>());
      expect((res.events.first as RoundWon).winnerId, equals('p1')); // p2 kaybeder
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

    test('6. Tur başlatıcısının sırayla değişmesi, soru tekrar etmemesi ve tohum determinizmi', () {
      final config = const MatchConfig();
      final random1 = math.Random(12345);
      final random2 = math.Random(12345);

      var res1 = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random1,
        nowMs: 1000,
      );
      var res2 = MatchEngine.start(
        config: config,
        playerIds: ['p1', 'p2'],
        questions: sampleQuestions,
        random: random2,
        nowMs: 1000,
      );

      // Aynı seed ile aynı ilk soru seçilir
      expect(res1.state.currentQuestion!.id, equals(res2.state.currentQuestion!.id));

      // Tur 0 başlatıcısı: p1
      expect(res1.state.turnPlayerId, equals('p1'));

      // 1. Turu bitir (berabere veya kazanç farketmeksizin)
      res1 = MatchEngine.submit(
        state: res1.state,
        playerId: 'p1',
        rawInput: 'yanlis_kelime_xyz',
        nowMs: 2000,
      );
      expect(res1.state.totalRoundsPlayed, equals(1));

      // 2. Turu başlat: başlatıcı p2 olmalıdır
      res1 = MatchEngine.startNextRound(
        state: res1.state,
        questions: sampleQuestions,
        random: random1,
        nowMs: 3000,
      );
      expect(res1.state.turnPlayerId, equals('p2'));
      // Farklı bir soru gelmeli
      expect(res1.state.currentQuestion!.id, isNot(equals(res2.state.currentQuestion!.id)));

      // 2. Turu da bitir
      res1 = MatchEngine.submit(
        state: res1.state,
        playerId: 'p2',
        rawInput: 'yanlis_kelime_xyz',
        nowMs: 4000,
      );
      expect(res1.state.totalRoundsPlayed, equals(2));

      // 3. Turu başlat: başlatıcı tekrar p1 olmalıdır
      res1 = MatchEngine.startNextRound(
        state: res1.state,
        questions: sampleQuestions,
        random: random1,
        nowMs: 5000,
      );
      expect(res1.state.turnPlayerId, equals('p1'));
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
      // deadlineMs = 1000 + 10000 = 11000. Tolerans ile limit = 11000 + 500 = 11500.

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

      // 4. Deneme: p1 yanlış (xyz) t=11000 -> Tur biter
      res = MatchEngine.submit(state: state, playerId: 'p1', rawInput: 'xyz', nowMs: 11000);
      state = res.state;

      expect(state.roundHistory.length, equals(1));
      final record = state.roundHistory.first;

      expect(record.questionId, equals('q_history'));
      expect(record.starterPlayerId, equals('p1'));
      expect(record.winnerId, equals('p2'));
      expect(record.reason, equals(RoundEndReason.wrong));

      expect(record.attempts.length, equals(4));

      expect(record.attempts[0].playerId, equals('p1'));
      expect(record.attempts[0].rawInput, equals('ankara'));
      expect(record.attempts[0].resultType, equals(AttemptResultType.correct));
      expect(record.attempts[0].nowMs, equals(2000));

      expect(record.attempts[1].playerId, equals('p2'));
      expect(record.attempts[1].rawInput, equals('parsi'));
      expect(record.attempts[1].resultType, equals(AttemptResultType.nearMiss));
      expect(record.attempts[1].nowMs, equals(5000));

      expect(record.attempts[2].playerId, equals('p2'));
      expect(record.attempts[2].rawInput, equals('paris'));
      expect(record.attempts[2].resultType, equals(AttemptResultType.correct));
      expect(record.attempts[2].nowMs, equals(8000));

      expect(record.attempts[3].playerId, equals('p1'));
      expect(record.attempts[3].rawInput, equals('xyz'));
      expect(record.attempts[3].resultType, equals(AttemptResultType.wrong));
      expect(record.attempts[3].nowMs, equals(11000));
    });
  });
}
