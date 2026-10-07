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
  ];

  /// Botun mevcut duruma göre kararını üretir.
  static BotDecision decide({
    required Question question,
    required Set<String> usedAnswerIds,
    required math.Random random,
    BotConfig config = const BotConfig(),
  }) {
    // 1. Gecikme süresi hesaplama [thinkMinMs, thinkMaxMs]
    final minMs = math.min(config.thinkMinMs, config.thinkMaxMs);
    final maxMs = math.max(config.thinkMinMs, config.thinkMaxMs);
    final range = maxMs - minMs;
    final delayMs = range > 0 ? minMs + random.nextInt(range + 1) : minMs;

    // 2. Henüz söylenmemiş cevaplar
    final unusedAnswers = question.answers
        .where((a) => !usedAnswerIds.contains(a.id))
        .toList();

    if (unusedAnswers.isEmpty) {
      // Söylenecek cevap kalmadıysa süre aşımına uğrasın
      return BotDecision(input: null, delayMs: delayMs);
    }

    final totalAnswers = question.answers.length;
    final remainingAnswers = unusedAnswers.length;
    final ratio = totalAnswers > 0 ? remainingAnswers / totalAnswers : 0.0;

    // 3. Bilme olasılığı: baseKnowChance + extra * (kalan / toplam), 0..1 aralığına kırp
    final knowChance = (config.baseKnowChance + config.extraKnowChance * ratio).clamp(0.0, 1.0);

    final roll = random.nextDouble();
    if (roll < knowChance) {
      // Bilir: söylenmemiş cevaplardan rastgele birini seç
      final answer = unusedAnswers[random.nextInt(unusedAnswers.length)];

      // O cevabın alias'larından rastgele birini seç (display veya aliases)
      final candidates = <String>{
        answer.display,
        ...answer.aliases,
      }.where((s) => s.isNotEmpty).toList();

      final chosenText = candidates.isNotEmpty
          ? candidates[random.nextInt(candidates.length)]
          : answer.display;

      return BotDecision(
        input: chosenText,
        delayMs: delayMs,
      );
    }

    // Bilmezse:
    final wrongRoll = random.nextDouble();
    if (wrongRoll < config.wrongAnswerChance) {
      // Yanlış metin: kategoriyle ilgisiz listeden, soru cevaplarında olmayanı seç
      final allNormalizedAliases = <String>{
        for (final a in question.answers) ...[
          a.id,
          for (final al in a.aliases) al,
        ]
      };

      final validWrongWords = _irrelevantWords.where((w) {
        final norm = TextNormalizer.normalize(w);
        return !allNormalizedAliases.contains(norm);
      }).toList();

      final chosenWrong = validWrongWords.isNotEmpty
          ? validWrongWords[random.nextInt(validWrongWords.length)]
          : 'uydurma_cevap_xyz';

      return BotDecision(
        input: chosenWrong,
        delayMs: delayMs,
      );
    }

    // Diğer yarısında hiçbir şey yapmadan süreyi geçirir (input = null)
    return BotDecision(
      input: null,
      delayMs: delayMs,
    );
  }
}

