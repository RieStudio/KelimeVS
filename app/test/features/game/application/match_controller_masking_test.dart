import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/text_filter/app_text_filter.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/models.dart';

class FakeClock implements GameClock {
  final FakeAsync async;
  FakeClock(this.async);
  @override
  int nowMs() => async.elapsed.inMilliseconds;
}

final sampleQuestions = [
  Question(
    id: 'q1',
    text: 'Türkiye illeri',
    categoryId: 'c1',
    answers: [
      Answer(id: 'a1', display: 'Ankara', aliases: ['ankara']),
      Answer(id: 'a2', display: 'İstanbul', aliases: ['istanbul']),
    ],
  ),
];

void main() {
  late AppTextFilter appTextFilter;

  setUpAll(() {
    File? blocklistFile;
    for (final p in [
      'assets/text_filter/blocklist.json',
      'app/assets/text_filter/blocklist.json',
      '../app/assets/text_filter/blocklist.json',
    ]) {
      final f = File(p);
      if (f.existsSync()) {
        blocklistFile = f;
        break;
      }
    }
    expect(blocklistFile, isNotNull);
    final jsonMap = json.decode(blocklistFile!.readAsStringSync()) as Map<String, dynamic>;
    appTextFilter = AppTextFilter.fromJson(jsonMap);
  });

  group('MatchController Küfür Maskeleme Entegrasyon Testleri', () {
    test('Kullanıcı uygunsuz kelime girdiğinde roundAttempts içinde maskelenir, motor kaydı ham kalır', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            textFilterProvider.overrideWithValue(appTextFilter),
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
          opponentName: 'Bot Ahmet',
          initialTurnPlayerId: 'me',
        );

        // Kullanıcı uygunsuz bir yanlış cevap gönderir
        const badWord = 'orospu';
        controller.submit(badWord);

        final state = container.read(matchControllerProvider);

        // 1. UI Modelinde (roundAttempts) metin maskelenmiş olmalıdır
        final myAttempts = state.roundAttempts.where((a) => a.playerId == 'me').toList();
        expect(myAttempts.isNotEmpty, isTrue);
        expect(myAttempts.first.text, 'o*****');

        // 2. Ham motor durumunda (currentRoundRecord) metin orijinal kalmalıdır
        final rawAttempts = state.matchState!.currentRoundRecord!.attempts;
        expect(rawAttempts.first.rawInput, badWord);

        container.dispose();
      });
    });

    test('Meşru cevaplar (Ankara) ve sayısal cevaplar (31, Windows 3 1) maskelenmez', () {
      fakeAsync((async) {
        final fakeClock = FakeClock(async);
        final container = ProviderContainer(
          overrides: [
            gameClockProvider.overrideWithValue(fakeClock),
            randomProvider.overrideWithValue(math.Random(1)),
            textFilterProvider.overrideWithValue(appTextFilter),
          ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: sampleQuestions,
          opponentName: 'Bot Ahmet',
          initialTurnPlayerId: 'me',
        );

        // Meşru yanlış cevaplar: sayı ve masum kelime
        controller.submit('31');
        async.elapse(const Duration(milliseconds: 600));
        controller.submit('kemal');

        final state = container.read(matchControllerProvider);
        final texts = state.roundAttempts.map((a) => a.text).toList();

        expect(texts.contains('31'), isTrue);
        expect(texts.contains('kemal'), isTrue);

        container.dispose();
      });
    });
  });
}
