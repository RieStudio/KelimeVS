import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_session.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';

class FakeMatchSession implements MatchSession {
  @override
  MatchUiState get state => const MatchUiState();

  @override
  void submit(String text) {}

  @override
  void leaveMatch() {}

  @override
  void dispose() {}
}

class FakeModeNotifier extends ActiveMatchSessionModeNotifier {
  final MatchSessionMode initialMode;
  FakeModeNotifier(this.initialMode);

  @override
  MatchSessionMode build() => initialMode;
}

class TestUiStateNotifier extends Notifier<MatchUiState> {
  final MatchUiState initial;
  TestUiStateNotifier(this.initial);

  @override
  MatchUiState build() => initial;

  void updateState(MatchUiState next) {
    state = next;
  }
}

void main() {
  const testQuestion = Question(
    id: 'q1',
    categoryId: 'c1',
    text: 'Türkiye\'nin başkenti?',
    answers: [],
  );

  final testMatchState = MatchState(
    config: const MatchConfig(),
    playerIds: const ['me', 'bot'],
    scores: const {'me': 0, 'bot': 0},
    decisiveRounds: 0,
    totalRoundsPlayed: 0,
    phase: MatchPhase.roundActive,
    currentQuestion: testQuestion,
    usedAnswerIds: const {},
    turnPlayerId: 'me',
    deadlineMs: 15000,
    remainingNearMisses: const {'me': 1, 'bot': 0},
    usedQuestionIds: const {},
    currentRoundAttempts: const [],
    roundHistory: const [],
  );

  group('MatchScreen - Bağlantı Deneyimi (ADIM 4.5d)', () {
    testWidgets(
      'Online maçta rakip bağlantısı kopunca (rakipBağlı: false) rakip kartında "Bağlantı koptu" notu görünür, kendi kartında çıkmaz',
      (tester) async {
        final testNotifier = TestUiStateNotifier(
          MatchUiState(
            matchState: testMatchState,
            opponentName: 'Mehmet',
            opponentConnected: false, // Rakip koptu
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        final testUiStateProvider =
            NotifierProvider<TestUiStateNotifier, MatchUiState>(
          () => testNotifier,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeMatchSessionModeProvider
                  .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
              activeMatchUiStateProvider
                  .overrideWith((ref) => ref.watch(testUiStateProvider)),
              activeMatchSessionProvider.overrideWithValue(FakeMatchSession()),
            ],
            child: const MaterialApp(
              home: MatchScreen(),
            ),
          ),
        );

        await tester.pump();

        // Rakip kartında "Bağlantı koptu" notu görünür
        expect(find.text(AppStrings.opponentDisconnectedNote), findsOneWidget);

        // Kendi kartında bu not HİÇ çıkmaz (kart adı "Sen" dir)
        expect(find.text(AppStrings.you), findsOneWidget);

        // Rakip geri gelince (opponentConnected: true) not kaybolur
        testNotifier.updateState(
          testNotifier.state.copyWith(opponentConnected: true),
        );
        await tester.pump();

        expect(find.text(AppStrings.opponentDisconnectedNote), findsNothing);
      },
    );

    testWidgets(
      'Online maçta kendi bağlantın kopunca (>700 ms) şerit görünür, düzelince 1.5 sn "Bağlandı" hapı görünür',
      (tester) async {
        final testNotifier = TestUiStateNotifier(
          MatchUiState(
            matchState: testMatchState,
            opponentName: 'Mehmet',
            opponentConnected: true,
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        final testUiStateProvider =
            NotifierProvider<TestUiStateNotifier, MatchUiState>(
          () => testNotifier,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeMatchSessionModeProvider
                  .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
              activeMatchUiStateProvider
                  .overrideWith((ref) => ref.watch(testUiStateProvider)),
              activeMatchSessionProvider.overrideWithValue(FakeMatchSession()),
            ],
            child: const MaterialApp(
              home: MatchScreen(),
            ),
          ),
        );

        await tester.pump();
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);

        // 1. Kendi bağlantımız koptu
        testNotifier.updateState(
          testNotifier.state.copyWith(
            connectionStatus: ConnectionStatus.reconnecting,
          ),
        );
        await tester.pump();

        // 400 ms sonra şerit henüz yok (debounce)
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);

        // 700 ms dolunca şerit görünür
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);

        // 2. Bağlantı geri geldi
        testNotifier.updateState(
          testNotifier.state.copyWith(
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        await tester.pump();

        // 200 ms içinde şerit kaybolup "Bağlandı" hapı görünür
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(AppStrings.connectionRestored), findsOneWidget);

        // 1.5 sn sonra hap da kaybolur (1500 ms pill süresi + 200 ms solma süresi)
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );

    testWidgets(
      'Kalıcı kopmada (permanent) connectionLostNotice ile ana ekrana dönülür',
      (tester) async {
        final testNotifier = TestUiStateNotifier(
          MatchUiState(
            matchState: testMatchState,
            opponentName: 'Ahmet',
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        final testUiStateProvider =
            NotifierProvider<TestUiStateNotifier, MatchUiState>(
          () => testNotifier,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeMatchSessionModeProvider
                  .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
              activeMatchUiStateProvider
                  .overrideWith((ref) => ref.watch(testUiStateProvider)),
              activeMatchSessionProvider.overrideWithValue(FakeMatchSession()),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MatchScreen(),
                          ),
                        );
                      },
                      child: const Text('Maça Git'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Maç ekranına geç
        await tester.tap(find.text('Maça Git'));
        await tester.pumpAndSettle();
        expect(find.byType(MatchScreen), findsOneWidget);

        // Kalıcı kopma tetiklenir
        testNotifier.updateState(
          testNotifier.state.copyWith(
            connectionStatus: ConnectionStatus.permanentDisconnected,
            isDisconnectedPermanent: true,
            isDisconnectedReplaced: false,
          ),
        );
        await tester.pumpAndSettle();

        // Maç ekranı kapanıp ilk ekrana dönülmüş olmalı
        expect(find.byType(MatchScreen), findsNothing);
        expect(find.text(AppStrings.connectionLostNotice), findsOneWidget);
      },
    );

    testWidgets(
      'Başka cihazdan ezilerek kopmada (replaced) matchReplacedNotice ile ana ekrana dönülür',
      (tester) async {
        final testNotifier = TestUiStateNotifier(
          MatchUiState(
            matchState: testMatchState,
            opponentName: 'Ahmet',
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        final testUiStateProvider =
            NotifierProvider<TestUiStateNotifier, MatchUiState>(
          () => testNotifier,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeMatchSessionModeProvider
                  .overrideWith(() => FakeModeNotifier(MatchSessionMode.online)),
              activeMatchUiStateProvider
                  .overrideWith((ref) => ref.watch(testUiStateProvider)),
              activeMatchSessionProvider.overrideWithValue(FakeMatchSession()),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MatchScreen(),
                          ),
                        );
                      },
                      child: const Text('Maça Git'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Maç ekranına geç
        await tester.tap(find.text('Maça Git'));
        await tester.pumpAndSettle();
        expect(find.byType(MatchScreen), findsOneWidget);

        // Replaced kopma tetiklenir
        testNotifier.updateState(
          testNotifier.state.copyWith(
            connectionStatus: ConnectionStatus.permanentDisconnected,
            isDisconnectedPermanent: true,
            isDisconnectedReplaced: true,
          ),
        );
        await tester.pumpAndSettle();

        // Maç ekranı kapanıp ilk ekrana dönülmüş ve "Maçı başka bir cihazda açtın" görünmüş olmalı
        expect(find.byType(MatchScreen), findsNothing);
        expect(find.text(AppStrings.matchReplacedNotice), findsOneWidget);
      },
    );

    testWidgets(
      'Yerel bot oturumunda (MatchSessionMode.bot) şerit ve not HİÇ görünmez',
      (tester) async {
        final testNotifier = TestUiStateNotifier(
          MatchUiState(
            matchState: testMatchState,
            opponentName: 'Bot Ahmet',
            opponentConnected: true,
            connectionStatus: ConnectionStatus.connected,
          ),
        );
        final testUiStateProvider =
            NotifierProvider<TestUiStateNotifier, MatchUiState>(
          () => testNotifier,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeMatchSessionModeProvider
                  .overrideWith(() => FakeModeNotifier(MatchSessionMode.bot)),
              activeMatchUiStateProvider
                  .overrideWith((ref) => ref.watch(testUiStateProvider)),
              activeMatchSessionProvider.overrideWithValue(FakeMatchSession()),
            ],
            child: const MaterialApp(
              home: MatchScreen(),
            ),
          ),
        );

        await tester.pump();

        // Bot oturumunda şerit ve rakip notu asla çıkmaz
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
        expect(find.text(AppStrings.opponentDisconnectedNote), findsNothing);
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );
  });
}
