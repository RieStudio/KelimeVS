import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/bot/bot_player.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

Question _makeTestQuestion({
  required String id,
  required String text,
  required List<String> answerWords,
}) {
  return Question(
    id: id,
    categoryId: 'test_category',
    text: text,
    answers: answerWords.map((w) {
      final norm = TextNormalizer.normalize(w);
      return Answer(id: norm, display: w, aliases: [norm]);
    }).toList(),
  );
}

void main() {
  group('BotPlayer Testleri', () {
    late Question question;

    setUp(() {
      question = _makeTestQuestion(
        id: 'q_bot_test',
        text: 'Test Sorusu',
        answerWords: [
          'Ankara',
          'İstanbul',
          'İzmir',
          'Bursa',
          'Antalya',
          'Adana',
          'Konya',
          'Trabzon',
          'Samsun',
          'Eskişehir',
        ],
      );
    });

    test('1. Gecikmeler thinkMinMs ve thinkMaxMs aralığındadır ve denemeler arası en az 700ms dir', () {
      const config = BotConfig(thinkMinMs: 3000, thinkMaxMs: 7000, wrongBeforeChance: 0.5);
      final random = math.Random(42);

      for (int i = 0; i < 50; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: random,
          config: config,
        );

        if (decision.actions.isNotEmpty) {
          final totalDelay = decision.actions.fold(0, (sum, a) => sum + a.delayMs);
          expect(totalDelay, greaterThanOrEqualTo(3000));
          expect(totalDelay, lessThanOrEqualTo(7000));

          if (decision.actions.length > 1) {
            for (int k = 1; k < decision.actions.length; k++) {
              expect(decision.actions[k].delayMs, greaterThanOrEqualTo(700));
            }
          }
        }
      }
    });

    test('2. Kullanılmış cevaplar asla seçilmez', () {
      final used = {'ankara', 'istanbul', 'izmir', 'bursa', 'antalya', 'adana', 'konya', 'trabzon', 'samsun'};
      // Sadece 'eskisehir' kaldı
      const config = BotConfig(baseKnowChance: 1.0, extraKnowChance: 0.0, wrongBeforeChance: 0.0);
      final random = math.Random(1);

      for (int i = 0; i < 20; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: used,
          random: random,
          config: config,
        );

        expect(decision.actions, isNotEmpty);
        final finalInput = decision.actions.last.input;
        final norm = TextNormalizer.normalize(finalInput);
        expect(used, isNot(contains(norm)));
        expect(norm, equals('eskisehir'));
      }
    });

    test('3. Kalan cevap az olunca bilme şansı istatistiksel olarak düşer', () {
      const config = BotConfig(
        baseKnowChance: 0.20,
        extraKnowChance: 0.80,
        wrongAnswerChance: 0.5,
        wrongBeforeChance: 0.0,
      );

      // Durum A: 10 cevabın 10'u da duruyor (oran = 1.0, knowChance = 1.0)
      final randomA = math.Random(100);
      int knownCountA = 0;
      const samples = 200;

      final allAnswerIds = question.answers.map((a) => a.id).toSet();

      for (int i = 0; i < samples; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: randomA,
          config: config,
        );
        if (decision.actions.isNotEmpty && allAnswerIds.contains(TextNormalizer.normalize(decision.actions.last.input))) {
          knownCountA++;
        }
      }

      // Durum B: 10 cevabın 9'u kullanılmış, sadece 1'i duruyor (oran = 0.1, knowChance = 0.28)
      final randomB = math.Random(100);
      int knownCountB = 0;
      final used9 = question.answers.take(9).map((a) => a.id).toSet();

      for (int i = 0; i < samples; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: used9,
          random: randomB,
          config: config,
        );
        if (decision.actions.isNotEmpty && allAnswerIds.contains(TextNormalizer.normalize(decision.actions.last.input))) {
          knownCountB++;
        }
      }

      expect(knownCountA, greaterThanOrEqualTo(190));
      expect(knownCountB, lessThan(knownCountA));
      expect(knownCountB, lessThan(100));
      expect(knownCountB, greaterThan(25));
    });

    test('4. Tohumlu Random ile tam deterministik davranır', () {
      final random1 = math.Random(12345);
      final random2 = math.Random(12345);

      for (int i = 0; i < 20; i++) {
        final dec1 = BotPlayer.decide(
          question: question,
          usedAnswerIds: {'ankara'},
          random: random1,
        );
        final dec2 = BotPlayer.decide(
          question: question,
          usedAnswerIds: {'ankara'},
          random: random2,
        );

        expect(dec1.actions.length, equals(dec2.actions.length));
        for (int k = 0; k < dec1.actions.length; k++) {
          expect(dec1.actions[k].input, equals(dec2.actions[k].input));
          expect(dec1.actions[k].delayMs, equals(dec2.actions[k].delayMs));
        }
      }
    });

    test('5. Bilmeyen bot: 0-2 yanlış deneme yapar, sonra sessiz kalır', () {
      const config = BotConfig(
        baseKnowChance: 0.0,
        extraKnowChance: 0.0,
        wrongAnswerChance: 0.5,
      );
      final random = math.Random(42);

      int silentCount = 0;
      int oneWrongCount = 0;
      int twoWrongCount = 0;

      for (int i = 0; i < 150; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: random,
          config: config,
        );

        final allAnswerIds = question.answers.map((a) => a.id).toSet();

        if (decision.actions.isEmpty) {
          silentCount++;
        } else if (decision.actions.length == 1) {
          oneWrongCount++;
          expect(allAnswerIds, isNot(contains(TextNormalizer.normalize(decision.actions[0].input))));
        } else if (decision.actions.length == 2) {
          twoWrongCount++;
          expect(allAnswerIds, isNot(contains(TextNormalizer.normalize(decision.actions[0].input))));
          expect(allAnswerIds, isNot(contains(TextNormalizer.normalize(decision.actions[1].input))));
          expect(decision.actions[1].delayMs, greaterThanOrEqualTo(700));
        }
      }

      expect(silentCount, greaterThan(20));
      expect(oneWrongCount, greaterThan(20));
      expect(twoWrongCount, greaterThan(20));
    });

    test('6. Bilen bot wrongBeforeChance ile önce 1 yanlış deneme, sonra doğru cevap verir', () {
      const config = BotConfig(
        baseKnowChance: 1.0,
        extraKnowChance: 0.0,
        wrongBeforeChance: 1.0, // Her zaman önce yanlış deneme yap
        thinkMinMs: 3000,
        thinkMaxMs: 4000,
      );
      final random = math.Random(7);

      final allAnswerIds = question.answers.map((a) => a.id).toSet();

      for (int i = 0; i < 20; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: random,
          config: config,
        );

        expect(decision.actions.length, equals(2));
        // 1. Eylem: yanlış kelime
        final firstNorm = TextNormalizer.normalize(decision.actions[0].input);
        expect(allAnswerIds, isNot(contains(firstNorm)));

        // 2. Eylem: doğru kelime
        final secondNorm = TextNormalizer.normalize(decision.actions[1].input);
        expect(allAnswerIds, contains(secondNorm));

        // Denemeler arası en az 700 ms
        expect(decision.actions[1].delayMs, greaterThanOrEqualTo(700));

        // Toplam süre thinkMin..thinkMax
        final totalDelay = decision.actions[0].delayMs + decision.actions[1].delayMs;
        expect(totalDelay, greaterThanOrEqualTo(3000));
        expect(totalDelay, lessThanOrEqualTo(4000));
      }
    });
  });
}
