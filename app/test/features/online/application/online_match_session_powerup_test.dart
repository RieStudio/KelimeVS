import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';
import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class FakeGameClock implements GameClock {
  int currentMs = 10000;
  @override
  int nowMs() => currentMs;
}

class FakeOnlineMatchClient extends OnlineMatchClient {
  final _eventController = StreamController<OnlineMatchEvent>.broadcast(sync: true);
  bool usePowerupCalled = false;
  int usePowerupCallCount = 0;
  String? lastPowerupType;

  @override
  Stream<OnlineMatchEvent> get events => _eventController.stream;

  void emit(OnlineMatchEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  @override
  Future<void> connect(String matchId) async {
    _eventController.add(const OnlineMatchConnected());
  }

  @override
  bool usePowerup(String type) {
    usePowerupCalled = true;
    usePowerupCallCount++;
    lastPowerupType = type;
    return true;
  }

  @override
  bool submit(String text) => true;

  @override
  Future<void> leave() async {}

  @override
  Future<void> close() async {
    await _eventController.close();
  }

  @override
  void handleAppPaused() {}

  @override
  Future<void> handleAppResumed() async {}

  @override
  Future<void> dispose() async {
    await close();
  }
}

class TestProfileNotifier extends ProfileNotifier {
  final int startCoins;
  TestProfileNotifier({this.startCoins = 100});

  @override
  ProfileState build() {
    return ProfileState(nickname: 'Tester', coins: startCoins);
  }

  @override
  Future<void> updateCoins(int newTotal) async {
    state = state.copyWith(coins: newTotal);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeOnlineMatchClient fakeClient;
  late FakeGameClock fakeClock;
  bool accountDeletedCalled = false;

  setUp(() {
    fakeClient = FakeOnlineMatchClient();
    fakeClock = FakeGameClock();
    accountDeletedCalled = false;

    container = ProviderContainer(
      overrides: [
        gameClockProvider.overrideWithValue(fakeClock),
        profileProvider.overrideWith(() => TestProfileNotifier(startCoins: 100)),
        accountDeletedHandlerProvider.overrideWithValue(() {
          accountDeletedCalled = true;
        }),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('1. OnlineMatchStateUpdate ile gelen güçlendirici konfigürasyonu uiState içine aktarılır', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const onlineState = OnlineMatchState(
      serverNowMs: 10000,
      receivedLocalMs: 10000,
      phase: OnlineMatchPhase.roundActive,
      roundNumber: 1,
      myScore: 0,
      opponentScore: 0,
      turnIsMine: true,
      deadlineMs: 25000,
      myHintsLeft: 1,
      answerSeconds: 15,
      attempts: [],
      opponentConnected: true,
      opponentName: 'Rakip',
      extraTimePowerup: OnlinePowerupConfig(
        cost: 30,
        seconds: 5,
        remainingUses: 1,
      ),
    );

    fakeClient.emit(const OnlineMatchStateUpdate(onlineState));
    await Future<void>.delayed(Duration.zero);

    final ui = container.read(onlineMatchSessionProvider);
    expect(ui.extraTimeCost, equals(30));
    expect(ui.extraTimeSeconds, equals(5));
    expect(ui.extraTimeRemainingUses, equals(1));
    expect(ui.maxAllowedSeconds, equals(15)); // Ek süre henüz kullanılmadığı için turun temel süresi geçerlidir
    expect(ui.isMyTurn, isTrue);
  });

  test('2. useExtraTime çağrıldığında client.usePowerup("extra_time") çağrılır ve isUsingPowerup bayrağı set edilir', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const onlineState = OnlineMatchState(
      serverNowMs: 10000,
      receivedLocalMs: 10000,
      phase: OnlineMatchPhase.roundActive,
      roundNumber: 1,
      myScore: 0,
      opponentScore: 0,
      turnIsMine: true,
      deadlineMs: 25000,
      myHintsLeft: 1,
      answerSeconds: 15,
      attempts: [],
      opponentConnected: true,
      opponentName: 'Rakip',
      extraTimePowerup: OnlinePowerupConfig(
        cost: 30,
        seconds: 5,
        remainingUses: 1,
      ),
    );

    fakeClient.emit(const OnlineMatchStateUpdate(onlineState));
    await Future<void>.delayed(Duration.zero);

    session.useExtraTime();

    expect(fakeClient.usePowerupCalled, isTrue);
    expect(fakeClient.lastPowerupType, equals('extra_time'));
    expect(container.read(onlineMatchSessionProvider).isUsingPowerup, isTrue);
  });

  test('3. Başarılı powerup_ack gelince profil jetonu güncellenir, remainingUses 0 olur ve isUsingPowerup sıfırlanır', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const onlineState = OnlineMatchState(
      serverNowMs: 10000,
      receivedLocalMs: 10000,
      phase: OnlineMatchPhase.roundActive,
      roundNumber: 1,
      myScore: 0,
      opponentScore: 0,
      turnIsMine: true,
      deadlineMs: 25000,
      myHintsLeft: 1,
      answerSeconds: 15,
      attempts: [],
      opponentConnected: true,
      opponentName: 'Rakip',
      extraTimePowerup: OnlinePowerupConfig(
        cost: 30,
        seconds: 5,
        remainingUses: 1,
      ),
    );
    fakeClient.emit(const OnlineMatchStateUpdate(onlineState));
    await Future<void>.delayed(Duration.zero);

    session.useExtraTime();

    const ack = PowerupAckServerMessage(
      powerupType: 'extra_time',
      success: true,
      deadlineMs: 30000,
      coins: 70, // 100 - 30
      remainingUses: 0,
    );
    fakeClient.emit(const OnlineMatchPowerupAck(ack));
    await Future<void>.delayed(Duration.zero);

    final ui = container.read(onlineMatchSessionProvider);
    expect(ui.isUsingPowerup, isFalse);
    expect(ui.extraTimeRemainingUses, equals(0));
    expect(container.read(profileProvider).coins, equals(70));
  });

  test('4. powerup_ack account_deleted hatası döndürdüğünde onAccountDeleted tetiklenir', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const ack = PowerupAckServerMessage(
      powerupType: 'extra_time',
      success: false,
      code: 'account_deleted',
      message: 'Hesap silinmiş',
    );
    fakeClient.emit(const OnlineMatchPowerupAck(ack));
    await Future<void>.delayed(Duration.zero);

    expect(accountDeletedCalled, isTrue);
    expect(container.read(onlineMatchSessionProvider).isUsingPowerup, isFalse);
  });

  test('5. opponent_powerup geldiğinde opponentExtraTimeBanner set edilir ve 2 sn sonra temizlenir', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const opponentMsg = OpponentPowerupServerMessage(
      powerupType: 'extra_time',
      seconds: 5,
    );
    fakeClient.emit(const OnlineMatchOpponentPowerup(opponentMsg));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(onlineMatchSessionProvider).opponentExtraTimeBanner,
      equals(AppStrings.opponentUsedExtraTime),
    );

    // 2 saniye sonrasında şerit otomatik kalkmalı
    await Future<void>.delayed(const Duration(milliseconds: 2100));

    expect(
      container.read(onlineMatchSessionProvider).opponentExtraTimeBanner,
      isNull,
    );
  });

  test('6. powerup_ack temporary_error döndürdüğünde isUsingPowerup sıfırlanır ve hata bildirimi set edilir', () async {
    final session = container.read(onlineMatchSessionProvider.notifier);
    await session.startOnlineMatch(
      matchId: 'match_123',
      opponentName: 'Rakip',
      client: fakeClient,
    );

    const onlineState = OnlineMatchState(
      serverNowMs: 10000,
      receivedLocalMs: 10000,
      phase: OnlineMatchPhase.roundActive,
      roundNumber: 1,
      myScore: 0,
      opponentScore: 0,
      turnIsMine: true,
      deadlineMs: 25000,
      myHintsLeft: 1,
      answerSeconds: 15,
      attempts: [],
      opponentConnected: true,
      opponentName: 'Rakip',
      extraTimePowerup: OnlinePowerupConfig(
        cost: 30,
        seconds: 5,
        remainingUses: 1,
      ),
    );
    fakeClient.emit(const OnlineMatchStateUpdate(onlineState));
    await Future<void>.delayed(Duration.zero);

    session.useExtraTime();
    expect(container.read(onlineMatchSessionProvider).isUsingPowerup, isTrue);

    const ack = PowerupAckServerMessage(
      powerupType: 'extra_time',
      success: false,
      code: 'temporary_error',
      message: 'İşlem sırasında bir hata oluştu.',
    );
    fakeClient.emit(const OnlineMatchPowerupAck(ack));
    await Future<void>.delayed(Duration.zero);

    final ui = container.read(onlineMatchSessionProvider);
    expect(ui.isUsingPowerup, isFalse);
    expect(ui.powerupErrorNotice, equals(AppStrings.powerupTemporaryError));
    expect(ui.powerupErrorCounter, equals(1));
  });

  group('Cevap Ver (give_answer) Session Tests', () {
    const baseGiveAnswerOnlineState = OnlineMatchState(
      serverNowMs: 10000,
      receivedLocalMs: 10000,
      phase: OnlineMatchPhase.roundActive,
      roundNumber: 1,
      myScore: 0,
      opponentScore: 0,
      turnIsMine: true,
      deadlineMs: 25000,
      myHintsLeft: 1,
      answerSeconds: 15,
      attempts: [],
      opponentConnected: true,
      opponentName: 'Rakip',
      giveAnswerPowerup: OnlineGiveAnswerPowerupConfig(
        cost: 50,
        remainingUses: 1,
      ),
    );

    test('7. OnlineMatchStateUpdate ile giveAnswer konfigürasyonu aktarılır', () async {
      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_give_answer',
        opponentName: 'Rakip',
        client: fakeClient,
      );

      fakeClient.emit(const OnlineMatchStateUpdate(baseGiveAnswerOnlineState));
      await Future<void>.delayed(Duration.zero);

      final ui = container.read(onlineMatchSessionProvider);
      expect(ui.giveAnswerCost, equals(50));
      expect(ui.giveAnswerRemainingUses, equals(1));
    });

    test('8. useGiveAnswer çağrıldığında client.usePowerup("give_answer") çağrılır ve isUsingPowerup set edilir', () async {
      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_give_answer',
        opponentName: 'Rakip',
        client: fakeClient,
      );

      fakeClient.emit(const OnlineMatchStateUpdate(baseGiveAnswerOnlineState));
      await Future<void>.delayed(Duration.zero);

      session.useGiveAnswer();

      expect(fakeClient.usePowerupCalled, isTrue);
      expect(fakeClient.lastPowerupType, equals('give_answer'));
      expect(container.read(onlineMatchSessionProvider).isUsingPowerup, isTrue);
    });

    test('9. Çift tıklama: isUsingPowerup açıkken ikinci useGiveAnswer() çağrısı mükerrer mesaj göndermez', () async {
      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_give_answer',
        opponentName: 'Rakip',
        client: fakeClient,
      );

      fakeClient.emit(const OnlineMatchStateUpdate(baseGiveAnswerOnlineState));
      await Future<void>.delayed(Duration.zero);

      session.useGiveAnswer();
      expect(fakeClient.usePowerupCallCount, equals(1));

      // İkinci kez çağrılıyor
      session.useGiveAnswer();
      expect(fakeClient.usePowerupCallCount, equals(1)); // Artmaz
    });

    test('10. Başarılı give_answer ack: profil jetonu güncellenir, remainingUses 0 olur, isUsingPowerup sıfırlanır', () async {
      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_give_answer',
        opponentName: 'Rakip',
        client: fakeClient,
      );

      fakeClient.emit(const OnlineMatchStateUpdate(baseGiveAnswerOnlineState));
      await Future<void>.delayed(Duration.zero);

      session.useGiveAnswer();

      const ack = PowerupAckServerMessage(
        powerupType: 'give_answer',
        success: true,
        coins: 50, // 100 - 50
        remainingUses: 0,
      );
      fakeClient.emit(const OnlineMatchPowerupAck(ack));
      await Future<void>.delayed(Duration.zero);

      final ui = container.read(onlineMatchSessionProvider);
      expect(ui.isUsingPowerup, isFalse);
      expect(ui.giveAnswerRemainingUses, equals(0));
      expect(container.read(profileProvider).coins, equals(50));
    });

    test('11. give_answer hata kodları için doğru Türkçe hata mesajları üretilir', () async {
      final session = container.read(onlineMatchSessionProvider.notifier);
      await session.startOnlineMatch(
        matchId: 'm_give_answer',
        opponentName: 'Rakip',
        client: fakeClient,
      );

      fakeClient.emit(const OnlineMatchStateUpdate(baseGiveAnswerOnlineState));
      await Future<void>.delayed(Duration.zero);

      final scenarios = <String, String>{
        'no_answers_left': AppStrings.noAnswersLeft,
        'not_enough_coins': AppStrings.notEnoughCoinsForGiveAnswer(50),
        'already_used': AppStrings.giveAnswerAlreadyUsed,
        'not_your_turn': AppStrings.notYourTurnGiveAnswer,
        'round_not_active': AppStrings.giveAnswerGenericError,
        'not_allowed_in_match_type': AppStrings.giveAnswerGenericError,
        'temporary_error': AppStrings.powerupTemporaryError,
        'unknown_code': AppStrings.giveAnswerGenericError,
      };

      var counter = 0;
      for (final entry in scenarios.entries) {
        session.useGiveAnswer();
        expect(container.read(onlineMatchSessionProvider).isUsingPowerup, isTrue);

        fakeClient.emit(OnlineMatchPowerupAck(PowerupAckServerMessage(
          powerupType: 'give_answer',
          success: false,
          code: entry.key,
          message: 'Server text that should be ignored',
        )));
        await Future<void>.delayed(Duration.zero);

        counter++;
        final ui = container.read(onlineMatchSessionProvider);
        expect(ui.isUsingPowerup, isFalse);
        expect(ui.powerupErrorNotice, equals(entry.value));
        expect(ui.powerupErrorCounter, equals(counter));
      }
    });
  });
}
