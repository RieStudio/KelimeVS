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

    test('1. Gecikmeler thinkMinMs ve thinkMaxMs aralığındadır', () {
      const config = BotConfig(thinkMinMs: 3000, thinkMaxMs: 7000);
      final random = math.Random(42);

      for (int i = 0; i < 50; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: random,
          config: config,
        );
        expect(decision.delayMs, greaterThanOrEqualTo(3000));
        expect(decision.delayMs, lessThanOrEqualTo(7000));
      }
    });

    test('2. Kullanılmış cevaplar asla seçilmez', () {
      final used = {'ankara', 'istanbul', 'izmir', 'bursa', 'antalya', 'adana', 'konya', 'trabzon', 'samsun'};
      // Sadece 'eskisehir' kaldı
      const config = BotConfig(baseKnowChance: 1.0, extraKnowChance: 0.0);
      final random = math.Random(1);

      for (int i = 0; i < 20; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: used,
          random: random,
          config: config,
        );

        expect(decision.input, isNotNull);
        final norm = TextNormalizer.normalize(decision.input!);
        expect(used, isNot(contains(norm)));
        expect(norm, equals('eskisehir'));
      }
    });

    test('3. Kalan cevap az olunca bilme şansı istatistiksel olarak düşer', () {
      const config = BotConfig(
        baseKnowChance: 0.20,
        extraKnowChance: 0.80,
        wrongAnswerChance: 0.5,
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
        if (decision.input != null && allAnswerIds.contains(TextNormalizer.normalize(decision.input!))) {
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
        if (decision.input != null && allAnswerIds.contains(TextNormalizer.normalize(decision.input!))) {
          knownCountB++;
        }
      }

      // Durum A'da neredeyse %100 bilmeli
      expect(knownCountA, greaterThanOrEqualTo(190));

      // Durum B'de bilme oranı anlamlı ölçüde daha düşük olmalı (~%28 civarı, örn. 30 - 90 arası)
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

        expect(dec1.input, equals(dec2.input));
        expect(dec1.delayMs, equals(dec2.delayMs));
      }
    });

    test('5. Bilmediğinde yanlış metin ya da süre aşımı (null) üretir', () {
      const config = BotConfig(
        baseKnowChance: 0.0,
        extraKnowChance: 0.0,
        wrongAnswerChance: 0.5,
      );
      final random = math.Random(42);

      int timeoutCount = 0;
      int wrongWordCount = 0;

      for (int i = 0; i < 100; i++) {
        final decision = BotPlayer.decide(
          question: question,
          usedAnswerIds: {},
          random: random,
          config: config,
        );

        if (decision.input == null) {
          timeoutCount++;
        } else {
          wrongWordCount++;
          // Yanlış kelime soru cevapları arasında olmamalıdır
          final norm = TextNormalizer.normalize(decision.input!);
          expect(question.answers.map((a) => a.id), isNot(contains(norm)));
        }
      }

      expect(timeoutCount, greaterThan(20));
      expect(wrongWordCount, greaterThan(20));
    });
  });
}

