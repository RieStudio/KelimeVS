import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';

class FakeMatchController extends MatchController {
  String? startedWithOpponentName;
  bool startMatchCalled = false;

  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startMatch({
    List<Question>? questions,
    String? opponentName,
  }) async {
    startMatchCalled = true;
    startedWithOpponentName = opponentName;
    state = state.copyWith(
      opponentName: opponentName ?? '',
      isLoading: true,
    );
  }
}

Widget _buildTestApp(
  FakeMatchController controller, {
  Duration? searchDuration,
  String? initialOpponentName,
}) {
  return ProviderScope(
    overrides: [
      matchControllerProvider.overrideWith(() => controller),
    ],
    child: MaterialApp(
      home: MatchmakingScreen(
        searchDuration: searchDuration,
        initialOpponentName: initialOpponentName,
      ),
    ),
  );
}

void main() {
  testWidgets('1. Eşleşme ekranı başlangıç durumu: avatarlar, başlık, ipucu ve vazgeç butonu', (tester) async {
    final controller = FakeMatchController();

    await tester.pumpWidget(
      _buildTestApp(
        controller,
        searchDuration: const Duration(seconds: 10),
        initialOpponentName: 'Deniz',
      ),
    );
    await tester.pump();

    // Kendi avatarı ve bilinmeyen rakip avatarı
    expect(find.text('S'), findsOneWidget);
    expect(find.text(AppStrings.vs), findsOneWidget);
    expect(find.text(AppStrings.questionMark), findsOneWidget);

    // Başlık ve alt yazı
    expect(find.text(AppStrings.searchingOpponent), findsOneWidget);
    expect(find.text(AppStrings.startingSoon), findsOneWidget);

    // İpucu kartı
    expect(find.text(AppStrings.searchTipTitle), findsOneWidget);
    expect(find.text(AppStrings.searchTipContent), findsOneWidget);

    // Vazgeç butonu
    expect(find.widgetWithText(SecondaryButton, AppStrings.cancel), findsOneWidget);
  });

  testWidgets('2. Vazgeç butonuna basıldığında ekran kapanır ve zamanlayıcılar iptal edilir', (tester) async {
    final controller = FakeMatchController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => const MatchmakingScreen(
                      searchDuration: Duration(seconds: 5),
                      initialOpponentName: 'Deniz',
                    ),
                  ),
                );
              },
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );

    // Ekranı aç
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MatchmakingScreen), findsOneWidget);

    // Vazgeç butonuna bas
    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // MatchmakingScreen kapanmış olmalı
    expect(find.byType(MatchmakingScreen), findsNothing);
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets('3. Süre dolunca rakip avatarı/adı görünür, sonra maça geçer ve ad aktarılır', (tester) async {
    final controller = FakeMatchController();

    await tester.pumpWidget(
      _buildTestApp(
        controller,
        searchDuration: const Duration(milliseconds: 1000),
        initialOpponentName: 'Deniz',
      ),
    );
    await tester.pump();

    // Başlangıçta soru işareti var, Deniz adı henüz ekranda görünmüyor
    expect(find.text(AppStrings.questionMark), findsOneWidget);
    expect(find.text('Deniz'), findsNothing);

    // 1000 ms arama süresini ilerlet -> Rakip bulundu!
    await tester.pump(const Duration(milliseconds: 1050));

    // Rakip bulundu: Deniz adı ve avatarı ekranda
    expect(find.text('Deniz'), findsOneWidget);
    expect(find.text(AppStrings.questionMark), findsNothing);

    // 800 ms geçiş süresini ilerlet -> MatchScreen açılır ve maça aktarılır
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MatchScreen), findsOneWidget);
    expect(controller.startMatchCalled, isTrue);
    expect(controller.startedWithOpponentName, 'Deniz');
  });
}
