import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/profile/domain/nickname_validator.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
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

class _TestProfileNotifier extends ProfileNotifier {
  final ProfileState _initial;
  _TestProfileNotifier(this._initial);

  @override
  ProfileState build() => _initial;
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
  TestWidgetsFlutterBinding.ensureInitialized();
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
                answerSeconds: 20,
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
      expect(BotOpponentNames.storageKey, equals('kelimevs_recent_bot_names'));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          matchControllerProvider.overrideWith(() => MatchController(prefs: prefs)),
        ],
      );
      final controller = container.read(matchControllerProvider.notifier);

      // 1. Maç başlat: M-1234
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'M-1234',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['M-1234']));

      // 2. Maç başlat: M-2345
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'M-2345',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['M-1234', 'M-2345']));

      // 3. Maç başlat: M-3456
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'M-3456',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['M-1234', 'M-2345', 'M-3456']));

      // 4. Maç başlat: M-4567 -> En eski 'M-1234' silinmeli (azami 3 kayıt)
      await controller.startMatch(
        questions: sampleQuestions,
        opponentName: 'M-4567',
      );
      expect(BotOpponentNames.loadRecentNames(prefs), equals(['M-2345', 'M-3456', 'M-4567']));

      container.dispose();
    });

    test('5. BotOpponentNames: Misafir formatında (M-####, 1000-9999) ad üretilir, oyuncu adını ve son 3 rakibi dışlar', () {
      final guestRegex = RegExp(r'^M-([1-9]\d{3})$');
      final recent = ['M-1001', 'M-1002', 'M-1003'];
      const myNickname = 'M-4821';

      for (int i = 0; i < 100; i++) {
        final rng = math.Random(100 + i);
        final chosen = BotOpponentNames.pickOpponentName(
          random: rng,
          recentNames: recent,
          excludeName: myNickname,
        );

        // Format kontrolü: M-#### ve 1000..9999
        final match = guestRegex.firstMatch(chosen);
        expect(match, isNotNull, reason: '$chosen misafir formatına (M-####) uymalı');
        final num = int.parse(match!.group(1)!);
        expect(num, inInclusiveRange(1000, 9999));

        // Misafir kalıbı kontrolü
        expect(NicknameValidator.isGuestPattern(chosen), isTrue);

        // Son 3 rakip dışlanmalı
        expect(recent, isNot(contains(chosen)), reason: '$chosen son rakipler arasında olamaz');

        // Oyuncunun kendi adı (büyük/küçük harf farketmeksizin) dışlanmalı
        expect(chosen.toUpperCase(), isNot(equals(myNickname.toUpperCase())));
      }

      // Oyuncunun adı küçük harfle gelse dahi çakışma engellenmeli
      final chosenCaseInsensitive = BotOpponentNames.pickOpponentName(
        random: math.Random(42),
        excludeName: 'm-4821',
      );
      expect(chosenCaseInsensitive.toUpperCase(), isNot(equals('M-4821')));
    });

    test('6. MatchController: opponentName verilmediğinde profileProvider\'daki oyuncu adını çakışmayacak şekilde M-#### üretir', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => _TestProfileNotifier(const ProfileState(nickname: 'M-5555'))),
          matchControllerProvider.overrideWith(() => MatchController(prefs: prefs)),
        ],
      );
      final controller = container.read(matchControllerProvider.notifier);

      await controller.startMatch(
        questions: sampleQuestions,
      );

      final state = container.read(matchControllerProvider);
      final oppName = state.opponentName;
      expect(oppName, isNotEmpty);
      expect(RegExp(r'^M-[1-9]\d{3}$').hasMatch(oppName), isTrue);
      expect(oppName, isNot(equals('M-5555')), reason: 'Oyuncunun kendi adı bot adı olarak seçilemez');

      // prefs'e kaydedildiğini doğrula
      expect(BotOpponentNames.loadRecentNames(prefs), contains(oppName));

      container.dispose();
    });
  });
}
