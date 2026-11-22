import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

Question _makeQuestion(String id, String text, List<String> answers) {
  return Question(
    id: id,
    categoryId: 'test_cat',
    text: text,
    answers: answers.map((w) {
      final norm = TextNormalizer.normalize(w);
      return Answer(id: norm, display: w, aliases: [norm]);
    }).toList(),
  );
}

void main() {
  test('En agresif ayarlarla en hızlı meşru solo galibiyet süresi hesabı', () {
    const matchConfig = MatchConfig(
      roundsToWin: 2,
      answerSeconds: 20,
      minSubmitIntervalMs: 600,
    );

    // En agresif bot kişiliği: aceleci
    final botConfig = BotConfig.forPersona(BotPersona.aceleci);
    final random = math.Random(12345);

    final questions = [
      _makeQuestion('q1', 'Soru 1', ['Ankara', 'İstanbul', 'İzmir']),
      _makeQuestion('q2', 'Soru 2', ['Elma', 'Armut', 'Muz']),
      _makeQuestion('q3', 'Soru 3', ['Kedi', 'Köpek', 'Kuş']),
    ];

    int nowMs = 1000;
    final startMs = nowMs;

    // 1. Maçı başlat
    var engineRes = MatchEngine.start(
      config: matchConfig,
      playerIds: ['me', 'bot'],
      questions: questions,
      random: random,
      nowMs: nowMs,
      questionOrder: ['q1', 'q2', 'q3'],
    );
    var state = engineRes.state;

    // Sıra insanda değilse bile insana geçirelim (en hızlı senaryoda insan başlar)
    state = state.copyWith(turnPlayerId: 'me');

    // Tur 1: İnsan en hızlı şekilde (minSubmitIntervalMs = 600ms) doğru cevap girer
    nowMs += matchConfig.minSubmitIntervalMs;
    engineRes = MatchEngine.submit(
      state: state,
      playerId: 'me',
      rawInput: 'Ankara',
      nowMs: nowMs,
    );
    state = engineRes.state;
    expect(state.turnPlayerId, 'bot');

    // Bot sırası: Bot düşünür veya bilemez, süre dolar
    // Botun süresi dolana kadar (answerSeconds = 20s) ilerle
    nowMs = state.deadlineMs;
    engineRes = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
    state = engineRes.state;
    expect(state.phase, MatchPhase.roundEnded);
    expect(state.scores['me'], 1);

    // Tur geçiş süresi (2 saniye)
    nowMs += 2000;

    // Tur 2: Yeni tur başlar
    final q2 = questions[1];
    state = state.copyWith(
      phase: MatchPhase.roundActive,
      currentQuestion: q2,
      turnPlayerId: 'me',
      deadlineMs: nowMs + matchConfig.answerSeconds * 1000,
      usedAnswerIds: {},
      currentTurnAttempts: 0,
      currentRoundAttempts: [],
    );

    // İnsan yine 600ms içinde doğru cevabı yazar
    nowMs += matchConfig.minSubmitIntervalMs;
    engineRes = MatchEngine.submit(
      state: state,
      playerId: 'me',
      rawInput: 'Elma',
      nowMs: nowMs,
    );
    state = engineRes.state;
    expect(state.turnPlayerId, 'bot');

    // Botun süresi tekrar dolar
    nowMs = state.deadlineMs;
    engineRes = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
    state = engineRes.state;

    expect(state.phase, MatchPhase.matchFinished);
    expect(state.winnerId, 'me');
    expect(state.scores['me'], 2);

    final totalElapsedMs = nowMs - startMs;
    final totalElapsedSeconds = totalElapsedMs / 1000.0;
    final minSoloWinSeconds = math.max(10, (totalElapsedSeconds / 2).floor());

    // ignore: avoid_print
    print('====================================================');
    // ignore: avoid_print
    print('EN HIZLI MEŞRU GALİBİYET SÜRESİ: $totalElapsedSeconds sn ($totalElapsedMs ms)');
    // ignore: avoid_print
    print('MIN_SOLO_WIN_SECONDS (yarısı, min 10): $minSoloWinSeconds sn');
    // ignore: avoid_print
    print('====================================================');

    expect(totalElapsedSeconds, greaterThanOrEqualTo(40.0));
    expect(minSoloWinSeconds, greaterThanOrEqualTo(20));
  });
}
