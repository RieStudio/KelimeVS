import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/answer_matcher.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/match/near_miss.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

Directory _resolveSharedVectorsDir() {
  final candidate1 = Directory('../shared/test-vectors');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = Directory('shared/test-vectors');
  if (candidate2.existsSync()) return candidate2;

  final candidate3 = Directory('../../shared/test-vectors');
  if (candidate3.existsSync()) return candidate3;

  throw StateError('shared/test-vectors dizini bulunamadı!');
}

Map<String, dynamic> _readJson(Directory dir, String filename) {
  final file = File('${dir.path}/$filename');
  expect(file.existsSync(), isTrue, reason: '$filename dosyası mevcut olmalıdır.');
  final content = file.readAsStringSync();
  return jsonDecode(content) as Map<String, dynamic>;
}

Question _parseQuestion(Map<String, dynamic> json) {
  final answersJson = (json['answers'] as List).cast<Map<String, dynamic>>();
  return Question(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String? ?? 'cat',
    text: json['title'] as String? ?? json['text'] as String? ?? '',
    answers: answersJson.map((a) {
      return Answer(
        id: a['id'] as String,
        display: a['display'] as String,
        aliases: (a['aliases'] as List).cast<String>(),
      );
    }).toList(),
  );
}

void main() {
  late Directory vectorsDir;

  setUpAll(() {
    vectorsDir = _resolveSharedVectorsDir();
  });

  group('Shared Test Vectors Doğrulama Testleri', () {
    test('1. normalizer.json test vektörleri TextNormalizer ile doğrulanır', () {
      final json = _readJson(vectorsDir, 'normalizer.json');
      expect(json['version'], equals(1));
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThanOrEqualTo(60));

      for (final tc in cases) {
        final input = tc['input'] as String;
        final expected = tc['expected'] as String;
        final actual = TextNormalizer.normalize(input);
        expect(
          actual,
          equals(expected),
          reason: 'Normalizer hatası: input="$input" (id: ${tc['id']})',
        );
      }
    });

    test('2. matcher.json test vektörleri AnswerMatcher ve NearMiss ile doğrulanır', () {
      final json = _readJson(vectorsDir, 'matcher.json');
      expect(json['version'], equals(1));
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThanOrEqualTo(30));

      for (final tc in cases) {
        final q = _parseQuestion(tc['question'] as Map<String, dynamic>);
        final input = tc['input'] as String;
        final usedAnswerIds = (tc['usedAnswerIds'] as List).cast<String>().toSet();
        final expectedResult = tc['expectedResult'] as String;
        final expectedAnswerId = tc['expectedAnswerId'] as String?;
        final expectedIsClose = tc['expectedIsClose'] as bool;

        final matcher = AnswerMatcher(q);
        final matchResult = matcher.check(input, usedAnswerIds);

        final actualResultType = switch (matchResult) {
          MatchResultCorrect() => 'correct',
          MatchResultRepeated() => 'repeated',
          MatchResultWrong() => 'wrong',
          MatchResultEmpty() => 'empty',
        };

        expect(
          actualResultType,
          equals(expectedResult),
          reason: 'Matcher type hatası: input="$input" (id: ${tc['id']})',
        );

        expect(
          matchResult.answer?.id,
          equals(expectedAnswerId),
          reason: 'Matcher answerId hatası: input="$input" (id: ${tc['id']})',
        );

        if (actualResultType == 'wrong') {
          final normalized = TextNormalizer.normalize(input);
          final unusedAliases = q.answers
              .where((a) => !usedAnswerIds.contains(a.id))
              .map((a) => a.aliases);
          final actualIsClose = NearMissCalculator.isNearMiss(
            normalizedInput: normalized,
            unusedAnswerAliases: unusedAliases,
          );

          expect(
            actualIsClose,
            equals(expectedIsClose),
            reason: 'Matcher isClose hatası: input="$input" (id: ${tc['id']})',
          );
        }
      }
    });

    test('3. near_miss.json test vektörleri NearMissCalculator ile doğrulanır', () {
      final json = _readJson(vectorsDir, 'near_miss.json');
      expect(json['version'], equals(1));
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThanOrEqualTo(30));

      for (final tc in cases) {
        final w1 = tc['word1'] as String;
        final w2 = tc['word2'] as String;
        final targetLength = tc['targetLength'] as int;
        final expectedMaxDist = tc['maxAllowedDistance'] as int;
        final expectedDist = tc['distance'] as int;
        final expectedIsClose = tc['isClose'] as bool;

        final actualMaxDist = NearMissCalculator.maxAllowedDistance(targetLength);
        expect(
          actualMaxDist,
          equals(expectedMaxDist),
          reason: 'maxAllowedDistance hatası: targetLen=$targetLength (id: ${tc['id']})',
        );

        final actualDist = NearMissCalculator.distance(w1, w2);
        expect(
          actualDist,
          equals(expectedDist),
          reason: 'distance hatası: "$w1" vs "$w2" (id: ${tc['id']})',
        );

        final actualIsClose = actualDist > 0 && actualDist <= actualMaxDist;
        expect(
          actualIsClose,
          equals(expectedIsClose),
          reason: 'isClose hatası: "$w1" vs "$w2" (id: ${tc['id']})',
        );
      }
    });

    test('4. visibility.json test vektörleri visibleAttempts ile doğrulanır', () {
      final json = _readJson(vectorsDir, 'visibility.json');
      expect(json['version'], equals(1));
      final cases = (json['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThanOrEqualTo(20));

      for (final tc in cases) {
        final attemptsRaw = (tc['attempts'] as List).cast<Map<String, dynamic>>();
        final viewerId = tc['viewerId'] as String;
        final roundActive = tc['roundActive'] as bool;
        final expectedIndices = (tc['expectedVisibleIndices'] as List).cast<int>();

        final attempts = attemptsRaw.map((a) {
          final typeStr = a['resultType'] as String;
          final resultType = AttemptResultType.values.byName(typeStr);
          return TurnAttempt(
            playerId: a['playerId'] as String,
            rawInput: a['rawInput'] as String,
            resultType: resultType,
            answerId: a['answerId'] as String?,
            nowMs: a['nowMs'] as int,
            isClose: a['isClose'] as bool? ?? false,
            hintShown: a['hintShown'] as bool? ?? false,
          );
        }).toList();

        final record = RoundRecord(
          questionId: 'q_test',
          starterPlayerId: 'p1',
          attempts: attempts,
          winnerId: null,
          reason: RoundEndReason.timeout,
        );

        final visible = visibleAttempts(record, viewerId, roundActive);
        final actualIndices = <int>[];
        for (int i = 0; i < attempts.length; i++) {
          if (visible.contains(attempts[i])) {
            actualIndices.add(i);
          }
        }

        expect(
          actualIndices,
          equals(expectedIndices),
          reason: 'Visibility hatası (id: ${tc['id']}, viewer: $viewerId, active: $roundActive)',
        );
      }
    });

    test('5. engine_scenarios.json adım adım maç senaryoları MatchEngine ile doğrulanır', () {
      final json = _readJson(vectorsDir, 'engine_scenarios.json');
      expect(json['version'], equals(1));
      final scenarios = (json['scenarios'] as List).cast<Map<String, dynamic>>();
      expect(scenarios.length, greaterThanOrEqualTo(25));

      // Soru havuzu
      final q1 = Question(
        id: 'q1',
        categoryId: 'c1',
        text: 'Araba Markaları',
        answers: const [
          Answer(id: 'audi', display: 'Audi', aliases: ['audi', 'aude']),
          Answer(id: 'bmw', display: 'BMW', aliases: ['bmw']),
          Answer(id: 'mercedes', display: 'Mercedes', aliases: ['mercedes', 'merco']),
          Answer(id: 'toyota', display: 'Toyota', aliases: ['toyota']),
          Answer(id: 'honda', display: 'Honda', aliases: ['honda']),
          Answer(id: 'ford', display: 'Ford', aliases: ['ford']),
        ],
      );
      final q2 = Question(
        id: 'q2',
        categoryId: 'c2',
        text: 'Meyveler',
        answers: const [
          Answer(id: 'elma', display: 'Elma', aliases: ['elma']),
          Answer(id: 'armut', display: 'Armut', aliases: ['armut']),
          Answer(id: 'muz', display: 'Muz', aliases: ['muz']),
          Answer(id: 'cilek', display: 'Çilek', aliases: ['cilek']),
          Answer(id: 'portakal', display: 'Portakal', aliases: ['portakal']),
          Answer(id: 'karpuz', display: 'Karpuz', aliases: ['karpuz']),
        ],
      );
      final q3 = Question(
        id: 'q3',
        categoryId: 'c3',
        text: 'Başkentler',
        answers: const [
          Answer(id: 'ankara', display: 'Ankara', aliases: ['ankara']),
          Answer(id: 'paris', display: 'Paris', aliases: ['paris']),
          Answer(id: 'berlin', display: 'Berlin', aliases: ['berlin']),
          Answer(id: 'roma', display: 'Roma', aliases: ['roma']),
          Answer(id: 'madrid', display: 'Madrid', aliases: ['madrid']),
          Answer(id: 'tokyo', display: 'Tokyo', aliases: ['tokyo']),
        ],
      );
      final qSmall = Question(
        id: 'q_small',
        categoryId: 'c_small',
        text: 'İki Seçenek',
        answers: const [
          Answer(id: 'evet', display: 'Evet', aliases: ['evet']),
          Answer(id: 'hayir', display: 'Hayır', aliases: ['hayir']),
        ],
      );
      final pool = [q1, q2, q3, qSmall];

      for (final scen in scenarios) {
        final scenId = scen['id'] as String;
        final cfgJson = scen['config'] as Map<String, dynamic>;
        final config = MatchConfig(
          roundsToWin: cfgJson['roundsToWin'] as int,
          answerSeconds: cfgJson['answerSeconds'] as int,
          graceMs: cfgJson['graceMs'] as int,
          nearMissPerRound: cfgJson['nearMissPerRound'] as int,
          minAnswersPerQuestion: cfgJson['minAnswersPerQuestion'] as int,
          minSubmitIntervalMs: cfgJson['minSubmitIntervalMs'] as int,
          maxAttemptsPerTurn: cfgJson['maxAttemptsPerTurn'] as int,
        );
        final playerIds = (scen['playerIds'] as List).cast<String>();
        final questionOrder = (scen['questionOrder'] as List).cast<String>();
        final initialNowMs = scen['initialNowMs'] as int;

        final rng = math.Random(42);
        var res = MatchEngine.start(
          config: config,
          playerIds: playerIds,
          questions: pool,
          random: rng,
          nowMs: initialNowMs,
          questionOrder: questionOrder,
        );
        var state = res.state;

        final steps = (scen['steps'] as List).cast<Map<String, dynamic>>();
        for (final step in steps) {
          final stepIdx = step['stepIndex'] as int;
          final action = step['action'] as String;
          final payload = step['payload'] as Map<String, dynamic>;
          final expectedEventsJson = (step['expectedEvents'] as List).cast<Map<String, dynamic>>();
          final expectedSnap = step['expectedStateSnapshot'] as Map<String, dynamic>;

          switch (action) {
            case 'submit':
              res = MatchEngine.submit(
                state: state,
                playerId: payload['playerId'] as String,
                rawInput: payload['rawInput'] as String,
                nowMs: payload['nowMs'] as int,
                questionsPool: pool,
                random: rng,
              );
            case 'tick':
              res = MatchEngine.checkTimeout(
                state: state,
                nowMs: payload['nowMs'] as int,
              );
            case 'forfeit':
              res = MatchEngine.forfeit(
                state: state,
                playerId: payload['playerId'] as String,
                nowMs: payload['nowMs'] as int,
              );
            case 'startNextRound':
              res = MatchEngine.startNextRound(
                state: state,
                questions: pool,
                random: rng,
                nowMs: payload['nowMs'] as int,
                questionOrder: questionOrder,
              );
            default:
              fail('Bilinmeyen aksiyon: $action ($scenId)');
          }

          state = res.state;

          // Event tipleri ve sayıları doğrulanır
          expect(
            res.events.length,
            equals(expectedEventsJson.length),
            reason: '$scenId step $stepIdx: Event sayısı eşleşmiyor',
          );
          for (int eIdx = 0; eIdx < res.events.length; eIdx++) {
            final actualEv = res.events[eIdx];
            final expEv = expectedEventsJson[eIdx];
            final expType = expEv['type'] as String;

            final actualType = switch (actualEv) {
              AnswerAccepted() => 'AnswerAccepted',
              NearMiss() => 'NearMiss',
              WrongAnswer() => 'WrongAnswer',
              AlreadySaid() => 'AlreadySaid',
              RoundWon() => 'RoundWon',
              RoundDrawn() => 'RoundDrawn',
              MatchFinished() => 'MatchFinished',
              Ignored() => 'Ignored',
            };
            expect(
              actualType,
              equals(expType),
              reason: '$scenId step $stepIdx: Event type eşleşmiyor',
            );
          }

          // State snapshot doğrulanır
          expect(state.phase.name, equals(expectedSnap['phase']),
              reason: '$scenId step $stepIdx: phase eşleşmiyor');
          expect(state.turnPlayerId, equals(expectedSnap['turnPlayerId']),
              reason: '$scenId step $stepIdx: turnPlayerId eşleşmiyor');
          expect(state.scores, equals(expectedSnap['scores']),
              reason: '$scenId step $stepIdx: scores eşleşmiyor');
          expect(state.decisiveRounds, equals(expectedSnap['decisiveRounds']),
              reason: '$scenId step $stepIdx: decisiveRounds eşleşmiyor');
          expect(state.totalRoundsPlayed, equals(expectedSnap['totalRoundsPlayed']),
              reason: '$scenId step $stepIdx: totalRoundsPlayed eşleşmiyor');
          expect(state.winnerId, equals(expectedSnap['winnerId']),
              reason: '$scenId step $stepIdx: winnerId eşleşmiyor');
          expect(state.endedBy, equals(expectedSnap['endedBy']),
              reason: '$scenId step $stepIdx: endedBy eşleşmiyor');
          expect(state.currentRoundAttempts.length, equals(expectedSnap['attemptsCount']),
              reason: '$scenId step $stepIdx: attemptsCount eşleşmiyor');
        }
      }
    });
  });
}
