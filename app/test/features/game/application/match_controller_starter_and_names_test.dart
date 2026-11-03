import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/profile/domain/nickname_validator.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/bot/bot_opponent_names.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

class FakeClock implements GameClock {
  final Object _asyncObject;
  final int baseMs;

  FakeClock(this._asyncObject, {this.baseMs = 1000});

  @override
  int nowMs() {
    final elapsed = (_asyncObject as dynamic).elapsed as Duration;
    return baseMs + elapsed.inMilliseconds;
  }
}

Question _createQuestion(String id, String text, List<String> answers) {
  return Question(
    id: id,
    categoryId: 'test_category',
    text: text,
    answers: answers.map((a) {
      final norm = TextNormalizer.normalize(a);
      return Answer(
        id: norm,
        display: a,
        aliases: [norm],
      );
    }).toList(),
  );
}

void main() {
  late List<Question> sampleQuestions;

  setUp(() {
    sampleQuestions = [
      _createQuestion('q1', 'Meyveler', ['elma', 'armut', 'muz', 'çilek', 'kavun']),
      _createQuestion('q2', 'Hayvanlar', ['kedi', 'köpek', 'kuş', 'at', 'aslan']),
    ];
  });

  group('MatchController Starter & Bot Names Tests', () {
    test('1. Bot başlarken (initialTurnPlayerId: "bot") sıra botta başlar ve bot cevabından sonra sırayı insana devreder', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(42)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 0.0,
              ),
            ),
            matchConfigProvider.overrideWithValue(
              const MatchConfig(
                answerSeconds: 15,
                totalDecisiveRounds: 3,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'BotKaan',
          initialTurnPlayerId: 'bot',
        );

        var state = container.read(matchControllerProvider);
        expect(state.isLoading, isFalse);
        expect(state.matchState, isNotNull);
        expect(state.matchState!.phase, MatchPhase.roundActive);
        expect(state.isMyTurn, isFalse, reason: 'İlk turda sıra botta olmalı');
        expect(state.matchState!.turnPlayerId, 'bot');
        expect(state.matchState!.playerIds.first, 'bot');

        // Botun 1500ms düşünme süresi ilerletilir
        async.elapse(const Duration(milliseconds: 1500));

        state = container.read(matchControllerProvider);
        // Bot doğru cevabı verdi, şimdi sıra 'me' oyuncusunda olmalı
        expect(state.isMyTurn, isTrue, reason: 'Bot cevabından sonra sıra insana geçmeli');
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.acceptedAnswers, isNotEmpty);
        expect(state.acceptedAnswers.first.playerId, 'bot');

        container.dispose();
      });
    });

    test('2. İnsan başlarken (initialTurnPlayerId: "me") sıra insanda başlar', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(42)),
            botConfigProvider.overrideWithValue(
              const BotConfig(
                thinkMinMs: 1500,
                thinkMaxMs: 1500,
                baseKnowChance: 1.0,
                extraKnowChance: 0.0,
                wrongBeforeChance: 0.0,
              ),
            ),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'BotAyse',
          initialTurnPlayerId: 'me',
        );

        final state = container.read(matchControllerProvider);
        expect(state.isMyTurn, isTrue);
        expect(state.matchState!.turnPlayerId, 'me');
        expect(state.matchState!.playerIds.first, 'me');

        container.dispose();
      });
    });

    test('3. initialTurnPlayerId belirtilmediğinde ilk başlayan %50 rastgeledir', () {
      int humanStartedCount = 0;
      int botStartedCount = 0;
      const matchRuns = 100;

      for (int i = 0; i < matchRuns; i++) {
        final rng = math.Random(1000 + i);
        final container = ProviderContainer(
          overrides: [
            randomProvider.overrideWithValue(rng),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'TestOpponent',
        );

        final state = container.read(matchControllerProvider);
        if (state.matchState!.turnPlayerId == 'me') {
          humanStartedCount++;
        } else {
          botStartedCount++;
        }
        container.dispose();
      }

      // 100 maçta iki taraf da başlamış olmalı (30-70 bandında dengeli)
      expect(humanStartedCount, greaterThan(30));
      expect(botStartedCount, greaterThan(30));
      expect(humanStartedCount + botStartedCount, equals(matchRuns));
    });

    test('4. Bot maçı fiilen başladığında rakip ismi kelimevs_recent_bot_names deposuna azami 3 kayıtla yazılır', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          matchControllerProvider.overrideWith(() => MatchController(prefs: prefs)),
        ],
      );
      final controller = container.read(matchControllerProvider.notifier);

      // 1. Maç başlat: Kaan34
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'Kaan34',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['Kaan34']));

      // 2. Maç başlat: ayse_k
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'ayse_k',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['Kaan34', 'ayse_k']));

      // 3. Maç başlat: Deniz07
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'Deniz07',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['Kaan34', 'ayse_k', 'Deniz07']));

      // 4. Maç başlat: mert_yilmaz -> En eski 'Kaan34' silinmeli (azami 3 kayıt)
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'mert_yilmaz',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['ayse_k', 'Deniz07', 'mert_yilmaz']));

      container.dispose();
    });

    test('5. BotOpponentNames: Havuzdaki tüm 60 isim geçerlidir ve son 3 isim dışlanır', () {
      expect(BotOpponentNames.pool.length, greaterThanOrEqualTo(50));

      for (final name in BotOpponentNames.pool) {
        final valRes = NicknameValidator.validate(name);
        expect(
          valRes.isValid,
          isTrue,
          reason: '$name geçerli olmalı fakat hata: ${valRes.errorMessage}',
        );
        expect(
          NicknameValidator.isGuestPattern(name),
          isFalse,
          reason: '$name misafir M-#### kalıbında olamaz',
        );
      }

      final recent = ['ayse_k', 'Deniz07', 'mert_yilmaz'];
      final rng = math.Random(42);

      for (int i = 0; i < 50; i++) {
        final chosen = BotOpponentNames.pickOpponentName(
          random: rng,
          recentNames: recent,
        );
        expect(recent, isNot(contains(chosen)));
        expect(BotOpponentNames.pool, contains(chosen));
      }
    });
  });
}
