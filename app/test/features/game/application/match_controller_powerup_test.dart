import 'dart:async';
import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/data/powerup_api_client.dart';
import 'package:app/features/game/data/question_repository.dart';
import 'package:app/features/game/domain/bot/bot_config.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';

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

class FakeQuestionRepository implements QuestionRepository {
  final List<Question> questions;
  const FakeQuestionRepository(this.questions);

  @override
  Future<List<Question>> loadAll() async => questions;
}

class FakePowerupApiClient implements PowerupApiClient {
  int spendCalls = 0;
  final List<({String matchId, String powerup})> calls = [];
  Future<SpendPowerupResult> Function(String matchId, String powerup)? onSpend;

  FakePowerupApiClient({this.onSpend});

  @override
  Future<SpendPowerupResult> spend({
    required String matchId,
    required String powerup,
  }) async {
    spendCalls++;
    calls.add((matchId: matchId, powerup: powerup));
    if (onSpend != null) {
      return onSpend!(matchId, powerup);
    }
    return const SpendPowerupSuccess(coins: 70, alreadySpent: false);
  }
}

final testQuestion = Question(
  id: 'q_cars',
  categoryId: 'c_test',
  text: 'Araba markaları',
  answers: const [
    Answer(id: 'audi', display: 'Audi', aliases: ['audi']),
    Answer(id: 'bmw', display: 'BMW', aliases: ['bmw']),
    Answer(id: 'mercedes', display: 'Mercedes', aliases: ['mercedes']),
  ],
);

ProviderContainer createContainer({
  required FakeClock clock,
  required math.Random random,
  required FakePowerupApiClient apiClient,
  required int Function() coinsProvider,
  required void Function(int) onCoinsUpdated,
  MatchConfig matchConfig = const MatchConfig(answerSeconds: 15),
  BotConfig botConfig = const BotConfig(thinkMinMs: 1500, thinkMaxMs: 1500),
  List<Question>? questions,
}) {
  return ProviderContainer(
    overrides: [
      gameClockProvider.overrideWithValue(clock),
      randomProvider.overrideWithValue(random),
      questionRepositoryProvider.overrideWithValue(
        FakeQuestionRepository(questions ?? [testQuestion]),
      ),
      matchConfigProvider.overrideWithValue(matchConfig),
      botConfigProvider.overrideWithValue(botConfig),
      matchControllerProvider.overrideWith(
        () => MatchController(
          clock: clock,
          random: random,
          repository: FakeQuestionRepository(questions ?? [testQuestion]),
          matchConfig: matchConfig,
          botConfig: botConfig,
          powerupApiClient: apiClient,
          coinsProvider: coinsProvider,
          onCoinsUpdated: onCoinsUpdated,
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MatchController Bot Maçı Güçlendirici Testleri', () {
    test('1. Başlangıç state ve botMatchId üretimi', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        final fakeApiClient = FakePowerupApiClient();
        int userCoins = 100;

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        expect(container.read(matchControllerProvider).extraTimeCost, isNull);

        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 10));

        final state = container.read(matchControllerProvider);
        expect(state.extraTimeCost, equals(30));
        expect(state.extraTimeSeconds, equals(5));
        expect(state.extraTimeRemainingUses, equals(1));
        expect(state.giveAnswerCost, equals(50));
        expect(state.giveAnswerRemainingUses, equals(1));
        expect(state.isUsingPowerup, isFalse);
        expect(controller.botMatchIdForTesting, startsWith('bot:'));
        expect(
          RegExp(r'^bot:[A-Za-z0-9_-]{8,64}$').hasMatch(controller.botMatchIdForTesting),
          isTrue,
        );

        container.dispose();
      });
    });

    test('2. Ek Süre (extra_time) başarı akışı: bakiye düşer, hak 0 olur, deadline +5 sn uzar', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) async {
            expect(powerup, equals('extra_time'));
            return const SpendPowerupSuccess(coins: 70, alreadySpent: false);
          },
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 100));

        final initialDeadline = container.read(matchControllerProvider).matchState!.deadlineMs;
        final initialRemaining = container.read(matchControllerProvider).remainingMs;

        // Ek süre kullan
        controller.useExtraTime();
        expect(container.read(matchControllerProvider).isUsingPowerup, isTrue);

        async.elapse(const Duration(milliseconds: 50));

        final state = container.read(matchControllerProvider);
        expect(fakeApiClient.spendCalls, equals(1));
        expect(userCoins, equals(70));
        expect(state.extraTimeRemainingUses, equals(0));
        expect(state.isUsingPowerup, isFalse);

        // Deadline 5 sn (5000 ms) + istek süresi kadar uzatılmış olmalı
        expect(
          state.matchState!.deadlineMs,
          greaterThanOrEqualTo(initialDeadline + 5000),
        );
        expect(
          state.remainingMs,
          greaterThan(initialRemaining + 4000),
        );

        container.dispose();
      });
    });

    test('3. Cevap Ver (give_answer) başarı akışı: bakiye düşer, hak 0, rastgele cevap viaPowerup: true ile girer, sıra bota geçer', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) async {
            expect(powerup, equals('give_answer'));
            return const SpendPowerupSuccess(coins: 50, alreadySpent: false);
          },
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
          botConfig: const BotConfig(
            thinkMinMs: 1000,
            thinkMaxMs: 1000,
            baseKnowChance: 1.0,
            extraKnowChance: 0.0,
            wrongBeforeChance: 0.0,
          ),
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(container.read(matchControllerProvider).isMyTurn, isTrue);

        // Cevap Ver kullan
        controller.useGiveAnswer();
        expect(container.read(matchControllerProvider).isUsingPowerup, isTrue);

        async.elapse(const Duration(milliseconds: 50));

        final state = container.read(matchControllerProvider);
        expect(fakeApiClient.spendCalls, equals(1));
        expect(userCoins, equals(50));
        expect(state.giveAnswerRemainingUses, equals(0));
        expect(state.isUsingPowerup, isFalse);

        // Cevap girildi mi kontrol et
        expect(state.roundAttempts.length, equals(1));
        final attempt = state.roundAttempts.first;
        expect(attempt.isCorrect, isTrue);
        expect(attempt.viaPowerup, isTrue); // Ampul rozeti bayrağı!

        // Sıra bota geçti mi?
        expect(state.matchState!.turnPlayerId, equals('bot'));

        // 1 saniye bot süresi geçince botun cevabı gelmeli
        async.elapse(const Duration(milliseconds: 1000));
        expect(container.read(matchControllerProvider).roundAttempts.length, greaterThanOrEqualTo(2));

        container.dispose();
      });
    });

    test('4. İstek sırasında sayaç donar: kalan süre 1.5 sn iken basılsa bile tur düşmez, gecikmeli başarıda süre uzar', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;

        final completer = Completer<SpendPowerupResult>();
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) => completer.future,
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
          matchConfig: const MatchConfig(answerSeconds: 15, graceMs: 200),
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        // 13.5 saniye ilerlet (kalan süre 1.5 sn = 1500 ms)
        async.elapse(const Duration(milliseconds: 13500));

        final remainingBefore = container.read(matchControllerProvider).remainingMs;
        expect(remainingBefore, inInclusiveRange(1300, 1600));

        // Ek süre tuşuna bas (sayaç donar)
        controller.useExtraTime();
        expect(container.read(matchControllerProvider).isUsingPowerup, isTrue);

        // İstek sırasında 3 saniye geçsin (eğer donmasaydı 1.5 sn sonra timeout olurdu!)
        async.elapse(const Duration(milliseconds: 3000));

        // Tur bitmemiş olmalı, phase hâlâ roundActive ve turn 'me'
        var state = container.read(matchControllerProvider);
        expect(state.matchState!.phase, equals(MatchPhase.roundActive));
        expect(state.matchState!.turnPlayerId, equals('me'));
        // Kalan süre de donmuş olmalı (azalmamış olmalı)
        expect(state.remainingMs, equals(remainingBefore));

        // Ağ isteği 200 dönsün
        completer.complete(const SpendPowerupSuccess(coins: 70, alreadySpent: false));
        async.elapse(const Duration(milliseconds: 10));

        state = container.read(matchControllerProvider);
        // Şimdi başarı uygulandı, +5 sn eklendi
        expect(state.isUsingPowerup, isFalse);
        expect(state.remainingMs, greaterThan(5000));
        expect(state.matchState!.phase, equals(MatchPhase.roundActive));

        container.dispose();
      });
    });

    test('5. Hata / zaman aşımında saat kaldığı yerden devam eder, tur kaybedilmez', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;

        final completer = Completer<SpendPowerupResult>();
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) => completer.future,
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
          matchConfig: const MatchConfig(answerSeconds: 15, graceMs: 200),
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        // 12 saniye ilerlet (kalan süre ~3 sn)
        async.elapse(const Duration(milliseconds: 12000));
        final remainingBefore = container.read(matchControllerProvider).remainingMs;

        controller.useExtraTime();
        expect(container.read(matchControllerProvider).isUsingPowerup, isTrue);

        // 2 saniye ağda beklesin
        async.elapse(const Duration(milliseconds: 2000));

        // Ağ hatası dönsün
        completer.complete(const SpendPowerupNetworkError(AppStrings.powerupTemporaryError));
        async.elapse(const Duration(milliseconds: 50));

        final state = container.read(matchControllerProvider);
        expect(state.isUsingPowerup, isFalse);
        expect(state.powerupErrorNotice, equals(AppStrings.powerupTemporaryError));
        expect(state.extraTimeRemainingUses, equals(1)); // Hak yanmadı!

        // Saat kaldığı yerden (~3 sn) devam etmeli, tur kaybedilmemiş olmalı
        expect(state.matchState!.phase, equals(MatchPhase.roundActive));
        expect(state.matchState!.turnPlayerId, equals('me'));
        expect(state.remainingMs, inInclusiveRange(remainingBefore - 100, remainingBefore + 100));

        container.dispose();
      });
    });

    test('6. NetworkError sonrası aynı matchId ile tekrar deneme: alreadySpent: true başarıyla uygulanır', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;
        int callCount = 0;

        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) async {
            callCount++;
            if (callCount == 1) {
              return const SpendPowerupNetworkError();
            }
            // 2. istekte sunucu alreadySpent: true döner
            return const SpendPowerupSuccess(coins: 70, alreadySpent: true);
          },
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        // 1. deneme -> hata
        controller.useExtraTime();
        async.elapse(const Duration(milliseconds: 50));
        expect(container.read(matchControllerProvider).extraTimeRemainingUses, equals(1));
        expect(fakeApiClient.calls.length, equals(1));
        final firstMatchId = fakeApiClient.calls.first.matchId;

        // 2. deneme -> alreadySpent: true
        controller.useExtraTime();
        async.elapse(const Duration(milliseconds: 50));

        expect(fakeApiClient.calls.length, equals(2));
        expect(fakeApiClient.calls[1].matchId, equals(firstMatchId)); // Aynı matchId!
        expect(container.read(matchControllerProvider).extraTimeRemainingUses, equals(0)); // Hak başarıyla yandı
        expect(userCoins, equals(70));

        container.dispose();
      });
    });

    test('7. Çift dokunuş (double-tap): ilk istek bitmeden ikinci istek atılmaz (tek ağ çağrısı)', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;

        final completer = Completer<SpendPowerupResult>();
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) => completer.future,
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        // Peş peşe iki kez bas
        controller.useExtraTime();
        controller.useExtraTime();

        expect(fakeApiClient.spendCalls, equals(1)); // Yalnızca 1 kez çağrıldı

        completer.complete(const SpendPowerupSuccess(coins: 70));
        async.elapse(const Duration(milliseconds: 50));

        expect(fakeApiClient.spendCalls, equals(1));

        container.dispose();
      });
    });

    test('8. Yetersiz yerel bakiye: ağ çağrısı SIFIR, uyarı gösterilir', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 15; // 30'dan ve 50'den az
        final fakeApiClient = FakePowerupApiClient();

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        controller.useExtraTime();
        async.elapse(const Duration(milliseconds: 50));

        var state = container.read(matchControllerProvider);
        expect(fakeApiClient.spendCalls, equals(0)); // Sıfır ağ çağrısı!
        expect(state.powerupErrorNotice, equals(AppStrings.notEnoughCoinsForExtraTime(30)));
        expect(state.extraTimeRemainingUses, equals(1));

        controller.useGiveAnswer();
        async.elapse(const Duration(milliseconds: 50));

        state = container.read(matchControllerProvider);
        expect(fakeApiClient.spendCalls, equals(0)); // Sıfır ağ çağrısı!
        expect(state.powerupErrorNotice, equals(AppStrings.notEnoughCoinsForGiveAnswer(50)));
        expect(state.giveAnswerRemainingUses, equals(1));

        container.dispose();
      });
    });

    test('9. Cevap Ver için kullanılmamış cevap kalmadı: ağ çağrısı SIFIR, uyarı gösterilir', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;
        final fakeApiClient = FakePowerupApiClient();

        final singleAnswerQ = Question(
          id: 'q_one',
          categoryId: 'c1',
          text: 'Tek cevaplı soru',
          answers: const [
            Answer(id: 'a1', display: 'TekCevap', aliases: ['tekcevap']),
          ],
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
          questions: [singleAnswerQ],
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [singleAnswerQ],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        // Kullanıcı tek cevabı söyler
        controller.submit('TekCevap');
        async.elapse(const Duration(milliseconds: 50));

        // Artık cevap kalmadı, sıra bota geçmiş durumda ve cevap kalmadı
        controller.useGiveAnswer();
        async.elapse(const Duration(milliseconds: 50));

        expect(fakeApiClient.spendCalls, equals(0));
        expect(container.read(matchControllerProvider).giveAnswerRemainingUses, equals(1));

        container.dispose();
      });
    });

    test('10. 402 NotEnoughCoins ve 400 BadRequest yanıtları doğru işlenir', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;

        SpendPowerupResult resultToReturn = const SpendPowerupNotEnoughCoins(coins: 5);
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) async => resultToReturn,
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        // 402 senaryosu
        controller.useExtraTime();
        async.elapse(const Duration(milliseconds: 50));

        var state = container.read(matchControllerProvider);
        expect(userCoins, equals(5)); // Sunucudaki gerçek bakiye ile senkronlandı
        expect(state.extraTimeRemainingUses, equals(1));
        expect(state.powerupErrorNotice, equals(AppStrings.notEnoughCoinsForExtraTime(30)));

        // 400 BadRequest senaryosu
        userCoins = 100;
        resultToReturn = const SpendPowerupBadRequest('Geçersiz parametre');
        controller.useGiveAnswer();
        async.elapse(const Duration(milliseconds: 50));

        state = container.read(matchControllerProvider);
        expect(state.giveAnswerRemainingUses, equals(1));
        expect(state.powerupErrorNotice, equals('Geçersiz parametre'));

        container.dispose();
      });
    });

    test('11. İstek devam ederken controller dispose olursa state değişmez', () {
      fakeAsync((async) {
        final clock = FakeClock(async);
        final random = math.Random(42);
        int userCoins = 100;

        final completer = Completer<SpendPowerupResult>();
        final fakeApiClient = FakePowerupApiClient(
          onSpend: (matchId, powerup) => completer.future,
        );

        final container = createContainer(
          clock: clock,
          random: random,
          apiClient: fakeApiClient,
          coinsProvider: () => userCoins,
          onCoinsUpdated: (c) => userCoins = c,
        );

        final controller = container.read(matchControllerProvider.notifier);
        controller.startMatch(
          questions: [testQuestion],
          initialTurnPlayerId: 'me',
        );
        async.elapse(const Duration(milliseconds: 50));

        controller.useExtraTime();
        expect(container.read(matchControllerProvider).isUsingPowerup, isTrue);

        // Kullanıcı maçı terk etti / container kapandı
        container.dispose();

        // Şimdi istek dönsün
        completer.complete(const SpendPowerupSuccess(coins: 70));
        async.elapse(const Duration(milliseconds: 50));

        // Dispose sonrası bakiye veya state manipülasyonu yapılmamalı
        expect(userCoins, equals(100)); // updateCoins çağrılmadı
      });
    });
  });
}
