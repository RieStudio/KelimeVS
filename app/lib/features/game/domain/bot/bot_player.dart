// Saf Dart - Flutter veya Firebase bağımlılığı yoktur.

import 'dart:math' as math;

import '../models.dart';
import '../text_normalizer.dart';
import 'bot_config.dart';
import 'bot_decision.dart';

abstract final class BotPlayer {
  /// Soru kategorileriyle ilgisiz genel kelime listesi (yanlış cevap üretimi için)
  static const List<String> _irrelevantWords = [
    'masa',
    'kalem',
    'deniz',
    'kitap',
    'bulut',
    'agac',
    'yol',
    'kapi',
    'pencere',
    'duvar',
    'lamba',
    'canta',
    'ayakkabi',
    'saat',
    'bardak',
    'tabak',
    'telefon',
    'televizyon',
    'dolap',
    'koltuk',
  ];

  /// Botun mevcut duruma göre kararını üretir.
  static BotDecision decide({
    required Question question,
    required Set<String> usedAnswerIds,
    required math.Random random,
    BotConfig config = const BotConfig(),
  }) {
    // 1. Toplam düşünme süresi seçimi [thinkMinMs, thinkMaxMs]
    final minMs = math.min(config.thinkMinMs, config.thinkMaxMs);
    final maxMs = math.max(config.thinkMinMs, config.thinkMaxMs);
    final range = maxMs - minMs;
    final totalDelayMs = range > 0 ? minMs + random.nextInt(range + 1) : minMs;

    // 2. Henüz söylenmemiş cevaplar
    final unusedAnswers = question.answers
        .where((a) => !usedAnswerIds.contains(a.id))
        .toList();

    final allQuestionAliases = <String>{
      for (final a in question.answers) ...[
        a.id,
        for (final al in a.aliases) al,
      ],
      for (final uid in usedAnswerIds) uid,
    };

    List<String> getWrongWords(int count) {
      final validWrongWords = _irrelevantWords.where((w) {
        final norm = TextNormalizer.normalize(w);
        return !allQuestionAliases.contains(norm);
      }).toList();

      final list = <String>[];
      for (int i = 0; i < count; i++) {
        if (validWrongWords.isNotEmpty) {
          final word = validWrongWords[(random.nextInt(validWrongWords.length) + i) % validWrongWords.length];
          list.add(word);
        } else {
          list.add('uydurma_kelime_${i + 1}');
        }
      }
      return list;
    }

    if (unusedAnswers.isEmpty) {
      // Söylenecek cevap kalmadıysa bilmeyen bot gibi davran (sessiz kal veya yanlış dene)
      return _makeUnknowingDecision(
        totalDelayMs: totalDelayMs,
        config: config,
        random: random,
        getWrongWords: getWrongWords,
      );
    }

    final totalAnswers = question.answers.length;
    final remainingAnswers = unusedAnswers.length;
    final ratio = totalAnswers > 0 ? remainingAnswers / totalAnswers : 0.0;

    // 3. Bilme olasılığı: baseKnowChance + extra * (kalan / toplam), 0..1 aralığına kırp
    final knowChance = (config.baseKnowChance + config.extraKnowChance * ratio).clamp(0.0, 1.0);

    final roll = random.nextDouble();
    if (roll < knowChance) {
      // Bilen bot: Söylenmemiş cevaplardan birini seç
      final answer = unusedAnswers[random.nextInt(unusedAnswers.length)];
      final candidates = <String>{
        answer.display,
        ...answer.aliases,
      }.where((s) => s.isNotEmpty).toList();

      final correctText = candidates.isNotEmpty
          ? candidates[random.nextInt(candidates.length)]
          : answer.display;

      // Olasılıkla (wrongBeforeChance = 0.3) önce 1 yanlış deneme, sonra doğru cevap
      if (random.nextDouble() < config.wrongBeforeChance && totalDelayMs >= 1400) {
        final availableSpread = totalDelayMs - 1400;
        final delay2 = 700 + (availableSpread > 0 ? random.nextInt(availableSpread + 1) : 0);
        final delay1 = totalDelayMs - delay2;
        final wrongWord = getWrongWords(1).first;

        return BotDecision(
          actions: [
            BotAction(delay1, wrongWord),
            BotAction(delay2, correctText),
          ],
        );
      } else {
        return BotDecision(
          actions: [
            BotAction(totalDelayMs, correctText),
          ],
        );
      }
    }

    // Bilmeyen bot: 0-2 yanlış deneme, sonra sessiz kal (süre dolsun)
    return _makeUnknowingDecision(
      totalDelayMs: totalDelayMs,
      config: config,
      random: random,
      getWrongWords: getWrongWords,
    );
  }

  static BotDecision _makeUnknowingDecision({
    required int totalDelayMs,
    required BotConfig config,
    required math.Random random,
    required List<String> Function(int count) getWrongWords,
  }) {
    if (random.nextDouble() >= config.wrongAnswerChance) {
      // 0 yanlış deneme: tamamen sessiz kalır (süre aşımına bırakır)
      return const BotDecision(actions: []);
    }

    // 1 veya 2 yanlış deneme
    final wrongCount = 1 + random.nextInt(2); // 1 veya 2
    final wrongWords = getWrongWords(wrongCount);

    if (wrongCount == 1) {
      return BotDecision(
        actions: [
          BotAction(totalDelayMs, wrongWords[0]),
        ],
      );
    } else {
      final effectiveTotal = math.max(1400, totalDelayMs);
      final availableSpread = effectiveTotal - 1400;
      final delay2 = 700 + (availableSpread > 0 ? random.nextInt(availableSpread + 1) : 0);
      final delay1 = effectiveTotal - delay2;

      return BotDecision(
        actions: [
          BotAction(delay1, wrongWords[0]),
          BotAction(delay2, wrongWords[1]),
        ],
      );
    }
  }
}
