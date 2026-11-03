// ignore_for_file: avoid_print, unused_local_variable

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/bot/bot_player.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

void main(List<String> args) {
  int masterSeed = 12345;
  if (args.isNotEmpty) {
    masterSeed = int.tryParse(args[0]) ?? 12345;
  }
  File? questionsFile;
  const candidates = [
    'assets/dev/questions.json',
    'app/assets/dev/questions.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      questionsFile = file;
      break;
    }
  }

  if (questionsFile == null) {
    stderr.writeln('Hata: questions.json dosyası bulunamadı!');
    exit(1);
  }

  final jsonStr = questionsFile.readAsStringSync();
  final Map<String, dynamic> decoded = json.decode(jsonStr);
  final questions = Question.parseQuestionsPool(decoded);

  print('=== Soru Havuzu: ${questions.length} soru yüklendi ===\n');

  final masterRandom = math.Random(masterSeed);

  // 1. Raw Bot Decision Statistics (10,000 decisions with 3 personas & fatigue & rubber-banding)
  print('--- 1. Yeni Bot Karar ve Yanıt Dağılımı (10.000 Karar Analizi - Seed: $masterSeed) ---');
  int totalDecisions = 10000;
  int knewCount = 0;
  int wrongFirstCount = 0;
  int wrongOnlyCount = 0;
  int timeoutCount = 0;
  List<int> delays = [];

  final personaCounts = <BotPersona, int>{
    BotPersona.dengeli: 0,
    BotPersona.aceleci: 0,
    BotPersona.dusunur: 0,
  };

  for (int i = 0; i < totalDecisions; i++) {
    final q = questions[masterRandom.nextInt(questions.length)];
    final usedCount = masterRandom.nextInt((q.answers.length * 0.7).ceil() + 1);
    final shuffled = List<Answer>.from(q.answers)..shuffle(masterRandom);
    final used = shuffled.take(usedCount).map((a) => a.id).toSet();

    final persona = BotPersona.values[masterRandom.nextInt(BotPersona.values.length)];
    personaCounts[persona] = (personaCounts[persona] ?? 0) + 1;
    final botConfig = BotConfig.forPersona(persona);

    final roundBotSuccess = masterRandom.nextInt(5);
    final humanScore = masterRandom.nextInt(3);
    final botScore = masterRandom.nextInt(3);

    final decision = BotPlayer.decide(
      question: q,
      usedAnswerIds: used,
      random: masterRandom,
      config: botConfig,
      roundBotSuccessCount: roundBotSuccess,
      humanScore: humanScore,
      botScore: botScore,
    );

    if (decision.willTimeout) {
      timeoutCount++;
      delays.add(15000);
    } else {
      final totalDelay = decision.actions.fold<int>(0, (sum, a) => sum + a.delayMs);
      delays.add(totalDelay);

      final lastInput = decision.actions.last.input;
      final norm = TextNormalizer.normalize(lastInput);
      final isCorrect = q.answers.any((a) => a.id == norm || a.aliases.contains(norm));

      if (isCorrect) {
        knewCount++;
        if (decision.actions.length > 1) {
          wrongFirstCount++;
        }
      } else {
        wrongOnlyCount++;
      }
    }
  }

  delays.sort();
  final avgDelay = delays.reduce((a, b) => a + b) / delays.length;
  final answeredDelays = delays.where((d) => d < 15000).toList();
  final avgAnswerDelay = answeredDelays.reduce((a, b) => a + b) / answeredDelays.length;

  print('Toplam Karar: $totalDecisions');
  print('Persona Dağılımı: Dengeli: ${personaCounts[BotPersona.dengeli]}, Aceleci: ${personaCounts[BotPersona.aceleci]}, Düşünür: ${personaCounts[BotPersona.dusunur]}');
  print('Doğru Cevap Verme Oranı: %${(knewCount / totalDecisions * 100).toStringAsFixed(1)}');
  print('  - Önce Yanlış Sonra Doğru: %${(wrongFirstCount / totalDecisions * 100).toStringAsFixed(1)}');
  print('  - Direkt Doğru: %${((knewCount - wrongFirstCount) / totalDecisions * 100).toStringAsFixed(1)}');
  print('Yanlış Deneyip Süre Aşımına Bırakma: %${(wrongOnlyCount / totalDecisions * 100).toStringAsFixed(1)}');
  print('Sessiz Kalma (0 Yanlış ile Süre Aşımı): %${(timeoutCount / totalDecisions * 100).toStringAsFixed(1)}');
  print('Yalnızca Cevap Verilen Turlarda Ort. Düşünme Süresi: ${(avgAnswerDelay / 1000).toStringAsFixed(2)} sn\n');

  // 2. Full Match Simulation: Bot vs Different Player Profiles (1000 matches each)
  print('--- 2. İyileştirilmiş Bot vs Oyuncu Seviyeleri (3 Seviye x 1.000 Maç - Seed: $masterSeed) ---');

  void simulateMatchesVsHuman({
    required String profileName,
    required double humanBaseKnowRate,
    required int humanMinThinkMs,
    required int humanMaxThinkMs,
    int matchCount = 1000,
  }) {
    int humanWins = 0;
    int botWins = 0;
    int draws = 0;
    int totalRounds = 0;
    int humanStartedCount = 0;

    const matchConfig = MatchConfig();
    final simRandom = math.Random(masterSeed);

    for (int m = 0; m < matchCount; m++) {
      int nowMs = 1000;
      final humanStarts = simRandom.nextBool();
      if (humanStarts) humanStartedCount++;

      final playerIds = humanStarts ? ['human', 'bot'] : ['bot', 'human'];

      // Maç başında rastgele persona seçilir
      final persona = BotPersona.values[simRandom.nextInt(BotPersona.values.length)];
      final botConfig = BotConfig.forPersona(persona);

      var engineRes = MatchEngine.start(
        config: matchConfig,
        playerIds: playerIds,
        questions: questions,
        random: simRandom,
        nowMs: nowMs,
      );
      var state = engineRes.state;

      int roundBotSuccessCount = 0;

      while (state.phase != MatchPhase.matchFinished) {
        if (state.phase == MatchPhase.roundEnded) {
          nowMs += 2500;
          roundBotSuccessCount = 0;
          engineRes = MatchEngine.startNextRound(
            state: state,
            questions: questions,
            random: simRandom,
            nowMs: nowMs,
          );
          state = engineRes.state;
        }

        while (state.phase == MatchPhase.roundActive) {
          final activePlayer = state.turnPlayerId!;
          final unused = state.currentQuestion!.answers
              .where((a) => !state.usedAnswerIds.contains(a.id))
              .toList();

          if (unused.isEmpty) {
            break;
          }

          if (activePlayer == 'bot') {
            final decision = BotPlayer.decide(
              question: state.currentQuestion!,
              usedAnswerIds: state.usedAnswerIds,
              random: simRandom,
              config: botConfig,
              roundBotSuccessCount: roundBotSuccessCount,
              humanScore: state.scores['human'] ?? 0,
              botScore: state.scores['bot'] ?? 0,
            );

            if (decision.willTimeout) {
              nowMs = state.deadlineMs + 100;
              engineRes = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
              state = engineRes.state;
              break;
            } else {
              bool roundEndedEarly = false;
              for (final action in decision.actions) {
                nowMs += action.delayMs;
                if (nowMs > state.deadlineMs) {
                  engineRes = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
                  state = engineRes.state;
                  roundEndedEarly = true;
                  break;
                }
                engineRes = MatchEngine.submit(
                  state: state,
                  playerId: 'bot',
                  rawInput: action.input,
                  nowMs: nowMs,
                );
                state = engineRes.state;

                for (final ev in engineRes.events) {
                  if (ev is AnswerAccepted && ev.playerId == 'bot') {
                    roundBotSuccessCount++;
                  }
                }

                if (state.phase != MatchPhase.roundActive) {
                  roundEndedEarly = true;
                  break;
                }
              }
              if (roundEndedEarly) break;
            }
          } else {
            // Human player turn
            final totalAns = state.currentQuestion!.answers.length;
            final remainingRatio = unused.length / totalAns;
            final humanKnowChance = (humanBaseKnowRate * remainingRatio).clamp(0.15, 0.95);
            final humanKnows = simRandom.nextDouble() < humanKnowChance;

            final thinkMs = humanMinThinkMs + simRandom.nextInt(humanMaxThinkMs - humanMinThinkMs + 1);
            nowMs += thinkMs;

            if (nowMs > state.deadlineMs || !humanKnows) {
              if (nowMs <= state.deadlineMs) {
                nowMs = state.deadlineMs + 100;
              }
              engineRes = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
              state = engineRes.state;
              break;
            } else {
              final chosen = unused[simRandom.nextInt(unused.length)];
              engineRes = MatchEngine.submit(
                state: state,
                playerId: 'human',
                rawInput: chosen.display,
                nowMs: nowMs,
              );
              state = engineRes.state;
            }
          }
        }
      }

      totalRounds += state.totalRoundsPlayed;
      if (state.winnerId == 'human') {
        humanWins++;
      } else if (state.winnerId == 'bot') {
        botWins++;
      } else {
        draws++;
      }
    }

    final winRate = (humanWins / matchCount * 100).toStringAsFixed(1);
    final botWinRate = (botWins / matchCount * 100).toStringAsFixed(1);
    final drawRate = (draws / matchCount * 100).toStringAsFixed(1);
    final starterRatio = (humanStartedCount / matchCount * 100).toStringAsFixed(1);

    print('Profil: $profileName');
    print('  - İnsan Kazanma Oranı: %$winRate ($humanWins / $matchCount)');
    print('  - Bot Kazanma Oranı:   %$botWinRate ($botWins / $matchCount)');
    print('  - Beraberlik Oranı:    %$drawRate ($draws / $matchCount)');
    print('  - İnsan Başlama Oranı: %$starterRatio');
    print('  - Ortalama Tur Sayısı: ${(totalRounds / matchCount).toStringAsFixed(2)} tur\n');
  }

  simulateMatchesVsHuman(
    profileName: '1. Acemi / Başlangıç Seviyesi (Doğruluk: ~%50, Süre: 4-8 sn)',
    humanBaseKnowRate: 0.60,
    humanMinThinkMs: 4000,
    humanMaxThinkMs: 8000,
  );

  simulateMatchesVsHuman(
    profileName: '2. Orta Seviye (Doğruluk: ~%75, Süre: 3-6 sn)',
    humanBaseKnowRate: 0.85,
    humanMinThinkMs: 3000,
    humanMaxThinkMs: 6000,
  );

  simulateMatchesVsHuman(
    profileName: '3. İleri Seviye / Usta (Doğruluk: ~%90, Süre: 2-4 sn)',
    humanBaseKnowRate: 0.98,
    humanMinThinkMs: 2000,
    humanMaxThinkMs: 4000,
  );
}
