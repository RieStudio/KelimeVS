// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'dart:math' as math;

import '../answer_matcher.dart';
import '../models.dart';
import 'bot_config.dart';
import 'bot_decision.dart';

abstract final class BotPlayer {
  /// Kelimeden OSA mesafesi 1 olan gerçekçi bir yazım hatası (typo) türetir.
  static String makeTypo(String word, math.Random random) {
    if (word.length >= 4) {
      final chars = word.split('');
      final type = random.nextInt(3);
      if (type == 0 && chars.length >= 4) {
        // Komşu iki harfin yer değiştirmesi
        final idx = random.nextInt(chars.length - 1);
        if (chars[idx] != chars[idx + 1]) {
          final tmp = chars[idx];
          chars[idx] = chars[idx + 1];
          chars[idx + 1] = tmp;
          return chars.join();
        }
      } else if (type == 1) {
        // Harf değiştirme (özellikle sesli harf veya son karakter)
        final idx = chars.length > 2 ? chars.length - 2 : chars.length - 1;
        chars[idx] = chars[idx] == 'a' ? 'e' : (chars[idx] == 'e' ? 'i' : 'a');
        return chars.join();
      } else {
        // Harf tekrarı (yazım titremesi/çift basma)
        final idx = random.nextInt(chars.length);
        chars.insert(idx, chars[idx]);
        return chars.join();
      }
    }
    return '${word}x';
  }

  /// AnswerMatcher ile doğrulanarak hiçbir soru cevabıyla eşleşmeyen
  /// (asla doğru sayılmayacak) kategoriye yakın hatalı cevap üretir.
  static String generateWrongAnswer({
    required Question question,
    required AnswerMatcher matcher,
    required math.Random random,
    String? baseWord,
  }) {
    final candidateSource = baseWord ??
        (question.answers.isNotEmpty
            ? question.answers[random.nextInt(question.answers.length)].display
            : 'cevap');

    var typo = makeTypo(candidateSource, random);
    int attempts = 0;
    while (!matcher.check(typo, const {}).isWrong && attempts < 10) {
      typo = '${typo}x';
      attempts++;
    }
    return typo;
  }

  /// Botun mevcut duruma göre kararını üretir.
  static BotDecision decide({
    required Question question,
    required Set<String> usedAnswerIds,
    required math.Random random,
    BotConfig config = const BotConfig(),
    int roundBotSuccessCount = 0,
    int humanScore = 0,
    int botScore = 0,
  }) {
    final matcher = AnswerMatcher(question);

    // 1. Henüz söylenmemiş cevaplar
    final unusedAnswers = question.answers
        .where((a) => !usedAnswerIds.contains(a.id))
        .toList();

    // 2. Dinamik bilme olasılığı hesabı
    final totalAnswers = question.answers.length;
    final remainingAnswers = unusedAnswers.length;
    final ratio = totalAnswers > 0 ? remainingAnswers / totalAnswers : 0.0;

    double calculatedKnowChance = config.baseKnowChance + config.extraKnowChance * ratio;

    // Tur içi doygunluk ve telafi normal oyun olasılıklarında (< 1.0 ve > 0.0) etkindir.
    // Testlerdeki deterministik zorlama (1.0 veya 0.0) durumlarını bozmaz.
    if (calculatedKnowChance > 0.0 && calculatedKnowChance < 1.0) {
      // Tur içi doygunluk (fatigue): 3. doğrudan sonra bilme şansı düşer
      if (roundBotSuccessCount >= BotConfig.fatigueAnswerThreshold) {
        calculatedKnowChance *= BotConfig.fatigueMultiplier;
      }

      // Telafi mekanizması (rubber-banding - en fazla %15)
      if (botScore > humanScore) {
        // Bot öndeyse bilme şansı hafif azalır
        calculatedKnowChance *= BotConfig.rubberBandBehindKnowMultiplier;
      } else if (humanScore > botScore) {
        // Bot gerideyse toparlanma şansı hafif artar
        calculatedKnowChance *= BotConfig.rubberBandAheadKnowMultiplier;
      }
    }

    final knowChance = calculatedKnowChance.clamp(0.0, 1.0);
    final willKnow = unusedAnswers.isNotEmpty && (random.nextDouble() < knowChance);

    // 3. Hedef kelime ve uzunluk ölçeklemesi
    String? correctText;
    int targetWordLength = BotConfig.wordLengthBaseChars;

    if (willKnow) {
      final answer = unusedAnswers[random.nextInt(unusedAnswers.length)];
      final candidates = <String>{
        answer.display,
        ...answer.aliases,
      }.where((s) => s.isNotEmpty).toList();

      correctText = candidates.isNotEmpty
          ? candidates[random.nextInt(candidates.length)]
          : answer.display;
      targetWordLength = correctText.length;
    } else if (unusedAnswers.isNotEmpty) {
      targetWordLength = unusedAnswers[random.nextInt(unusedAnswers.length)].display.length;
    }

    // 4. Gauss-benzeri düşünme süresi seçimi (Merkezi Limit Teoremi, n=3)
    final minMs = math.min(config.thinkMinMs, config.thinkMaxMs);
    final maxMs = math.max(config.thinkMinMs, config.thinkMaxMs);
    final range = maxMs - minMs;

    final int totalDelayMs;
    if (minMs == maxMs) {
      totalDelayMs = minMs;
    } else {
      final u = (random.nextDouble() + random.nextDouble() + random.nextDouble()) / 3.0;
      final baseDelayMs = minMs + range * u;

      // Kelime uzunluğu süre ölçeklemesi
      final lengthDeltaMs = (targetWordLength - BotConfig.wordLengthBaseChars) *
          BotConfig.wordLengthPerCharMs;

      // Telafi mekanizması süre çarpanı
      double thinkMultiplier = 1.0;
      if (botScore > humanScore) {
        thinkMultiplier = BotConfig.rubberBandBehindThinkMultiplier;
      } else if (humanScore > botScore) {
        thinkMultiplier = BotConfig.rubberBandAheadThinkMultiplier;
      }

      totalDelayMs = ((baseDelayMs + lengthDeltaMs) * thinkMultiplier)
          .round()
          .clamp(minMs, maxMs);
    }

    List<String> getWrongWords(int count, {String? base}) {
      final list = <String>[];
      for (int i = 0; i < count; i++) {
        list.add(
          generateWrongAnswer(
            question: question,
            matcher: matcher,
            random: random,
            baseWord: base,
          ),
        );
      }
      return list;
    }

    if (!willKnow) {
      // Bilmeyen bot: 0-1 yanlış deneme, sonra sessiz kal (süre dolsun)
      return _makeUnknowingDecision(
        totalDelayMs: totalDelayMs,
        config: config,
        random: random,
        getWrongWords: getWrongWords,
      );
    }

    // Bilen bot: Olasılıkla (wrongBeforeChance) önce 1 yanlış deneme, sonra doğru cevap
    // İki bot mesajı arası en az minCorrectionIntervalMs (1.5 sn) olmalıdır;
    // toplam süre yetersizse (totalDelayMs < minFirstAttemptMs + minCorrectionIntervalMs) ilk yanlış hiç atılmaz.
    const minRequiredMs = BotConfig.minFirstAttemptMs + BotConfig.minCorrectionIntervalMs;
    if (random.nextDouble() < config.wrongBeforeChance && totalDelayMs >= minRequiredMs) {
      final availableSpread = totalDelayMs - minRequiredMs;
      final extra2 = availableSpread > 0 ? random.nextInt(availableSpread + 1) : 0;
      final delay2 = BotConfig.minCorrectionIntervalMs + extra2;
      final delay1 = totalDelayMs - delay2;
      final wrongWord = getWrongWords(1, base: correctText).first;

      return BotDecision(
        actions: [
          BotAction(delay1, wrongWord),
          BotAction(delay2, correctText!),
        ],
      );
    } else {
      return BotDecision(
        actions: [
          BotAction(totalDelayMs, correctText!),
        ],
      );
    }
  }

  static BotDecision _makeUnknowingDecision({
    required int totalDelayMs,
    required BotConfig config,
    required math.Random random,
    required List<String> Function(int count, {String? base}) getWrongWords,
  }) {
    if (random.nextDouble() >= config.wrongAnswerChance) {
      // 0 yanlış deneme: tamamen sessiz kalır (süre aşımına bırakır)
      return const BotDecision(actions: []);
    }

    // Bilmeyen bot en fazla 1 yanlış deneme yapar (0 veya 1), asla peş peşe 2 hatalı mesaj atmaz.
    // Tek hatalı denemeden sonra süre dolana kadar sessiz kalır.
    final wrongWords = getWrongWords(1);
    return BotDecision(
      actions: [
        BotAction(totalDelayMs, wrongWords[0]),
      ],
    );
  }
}
