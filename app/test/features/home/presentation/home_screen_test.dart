import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/coin_pill.dart';
import 'package:app/core/widgets/kelime_go_logo.dart';
import 'package:app/core/widgets/match_card.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/result_badge.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  final List<MatchHistoryEntry> initialEntries;
  FakeMatchHistoryRepository([this.initialEntries = const []]);

  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return initialEntries;
  }
}

Widget _buildTestApp(MatchHistoryRepository repo, {DateTime? now}) {
  return ProviderScope(
    overrides: [
      matchHistoryRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: HomeScreen(now: now),
    ),
  );
}

void main() {
  final testNow = DateTime(2026, 10, 8, 20, 0);

  final wonEntry = MatchHistoryEntry(
    id: 'm1',
    opponentName: 'Zeynep',
    finishedAtMs: testNow.millisecondsSinceEpoch,
    myScore: 2,
    opponentScore: 1,
    result: MatchResult.win,
    endType: MatchEndType.normal,
    roundRecords: const [],
  );

  final lostEntry = MatchHistoryEntry(
    id: 'm2',
    opponentName: 'Elif',
    finishedAtMs: testNow.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    myScore: 1,
    opponentScore: 2,
    result: MatchResult.lose,
    endType: MatchEndType.normal,
    roundRecords: const [],
  );

  testWidgets('1. Ana ekran üst çubuk, logo, butonlar ve boş durum doğru çizilir', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo, now: testNow));
    await tester.pumpAndSettle();

    // Üst çubuk: "Oyuncu" adı, CoinPill (250)
    expect(find.text(AppStrings.defaultPlayerName), findsOneWidget);
    expect(find.byType(CoinPill), findsOneWidget);
    expect(find.text('250'), findsOneWidget);

    // Logo & Slogan
    expect(find.byType(KelimeGoLogo), findsOneWidget);
    expect(find.text(AppStrings.slogan), findsOneWidget);

    // Ana ve İkincil butonlar
    expect(find.text(AppStrings.quickMatch), findsOneWidget);
    expect(find.text(AppStrings.playWithFriend), findsOneWidget);

    // Boş durum metni
    expect(find.text(AppStrings.noMatchesYet), findsOneWidget);
  });

  testWidgets('2. Maç geçmişi listelenir: kartlar, rozetler ve kayıp maç kenarlığı doğru', (tester) async {
    final repo = FakeMatchHistoryRepository([wonEntry, lostEntry]);

    await tester.pumpWidget(_buildTestApp(repo, now: testNow));
    await tester.pumpAndSettle();

    expect(find.byType(MatchCard), findsNWidgets(2));

    // Zeynep kartı (Kazandın, Bugün, 2 – 1)
    expect(find.text('Zeynep'), findsOneWidget);
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('2 – 1'), findsOneWidget);
    expect(find.widgetWithText(ResultBadge, AppStrings.won), findsOneWidget);

    // Elif kartı (Kaybettin, Dün, 1 – 2)
    expect(find.text('Elif'), findsOneWidget);
    expect(find.text('Dün'), findsOneWidget);
    expect(find.text('1 – 2'), findsOneWidget);
    expect(find.widgetWithText(ResultBadge, AppStrings.lost), findsOneWidget);

    // Elif kartının kenarlık rengi dangerSoft olmalı
    final matchCards = tester.widgetList<MatchCard>(find.byType(MatchCard)).toList();
    final lostCardWidget = matchCards.firstWhere((c) => c.entry.id == 'm2');
    expect(lostCardWidget.entry.result, MatchResult.lose);

    // Kartın Container decoration kenarlık rengini kontrol et
    final lostContainerFinder = find.descendant(
      of: find.ancestor(of: find.text('Elif'), matching: find.byType(MatchCard)),
      matching: find.byWidgetPredicate(
        (w) => w is Container && (w.decoration as BoxDecoration?)?.border != null,
      ),
    );
    final lostContainer = tester.widget<Container>(lostContainerFinder.first);
    final border = (lostContainer.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.dangerSoft);
  });

  testWidgets('3. "Hızlı Maç" butonuna basıldığında MatchmakingScreen açılır', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo, now: testNow));
    await tester.pumpAndSettle();

    expect(find.byType(MatchmakingScreen), findsNothing);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.quickMatch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MatchmakingScreen), findsOneWidget);
  });

  testWidgets('4. "Arkadaşınla Oyna" butonuna basıldığında "Yakında" bilgi penceresi açılır', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo, now: testNow));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.comingSoon), findsNothing);

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.playWithFriend));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.comingSoon), findsOneWidget);
    expect(find.text(AppStrings.playWithFriendComingSoon), findsOneWidget);

    // Tamam butonuna basınca dialog kapanır
    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.ok));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.comingSoon), findsNothing);
  });
}
