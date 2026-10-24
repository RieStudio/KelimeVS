import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/main.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}
  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => const [];
  @override
  Future<void> clear() async {}
}

class FakeLeaderboardApiClient implements LeaderboardApiClient {
  int fetchCallCount = 0;

  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    fetchCallCount++;
    return const LeaderboardData(
      weekKey: '2026-W42',
      endsAt: 1792357200000,
      top: [
        LeaderboardEntry(rank: 1, nickname: 'Lider1', wins: 10, isMe: false),
      ],
    );
  }
}

class FakeProfileNotifier extends ProfileNotifier {
  final String nickname;
  final int coins;

  FakeProfileNotifier({this.nickname = 'Muhammed', this.coins = 100});

  @override
  ProfileState build() {
    return ProfileState(
      nickname: nickname,
      coins: coins,
      isLoaded: true,
    );
  }
}

Widget _buildMainShellApp({
  required FakeLeaderboardApiClient leaderboardClient,
  String nickname = 'Muhammed',
  int coins = 100,
}) {
  return ProviderScope(
    overrides: [
      matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
      leaderboardApiClientProvider.overrideWithValue(leaderboardClient),
      profileProvider.overrideWith(() => FakeProfileNotifier(nickname: nickname, coins: coins)),
    ],
    child: const MaterialApp(
      home: MainShell(),
    ),
  );
}

void main() {
  group('HomeScreen Leaderboard Navigation & Lazy Loading Tests', () {
    testWidgets('1. İlk ziyaretten önce LeaderboardScreen eager kurulmaz ve veri çekilmez',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient();

      await tester.pumpWidget(_buildMainShellApp(leaderboardClient: fakeClient));
      await tester.pumpAndSettle();

      // Ana sayfada açılmalı
      final currentIndexFinder = find.byType(MainShell);
      expect(currentIndexFinder, findsOneWidget);

      // Henüz ziyaret edilmediği için LeaderboardScreen kurulmamış olmalı (offstage dahil)
      expect(find.byType(LeaderboardScreen, skipOffstage: false), findsNothing);
      expect(
        find.byKey(
          const Key('leaderboard_unvisited_placeholder'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(fakeClient.fetchCallCount, 0);
    });

    testWidgets('2. Kupa butonuna tıklandığında Sıralama sekmesine (index 1) geçer ve LeaderboardScreen kurulur',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient();

      await tester.pumpWidget(_buildMainShellApp(leaderboardClient: fakeClient));
      await tester.pumpAndSettle();

      final trophyButton = find.byKey(const Key('leaderboard_button'));
      expect(trophyButton, findsOneWidget);

      // Kupa butonuna tıkla
      await tester.tap(trophyButton);
      await tester.pumpAndSettle();

      // Sekme 1'e geçmiş olmalı ve LeaderboardScreen kurulmalı
      expect(find.byType(LeaderboardScreen), findsOneWidget);
      expect(find.text(AppStrings.leaderboardTitle), findsOneWidget);
      expect(find.text('Lider1'), findsOneWidget);
      expect(fakeClient.fetchCallCount, 1);

      // Sekmede açıldığı için (canPop false) geri butonu OLMAMALI
      expect(find.byKey(const Key('leaderboard_back_button')), findsNothing);
    });

    testWidgets('3. Alt çubuktaki Sıralama sekmesine basıldığında da LeaderboardScreen açılır ve geri butonu görünmez',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient();

      await tester.pumpWidget(_buildMainShellApp(leaderboardClient: fakeClient));
      await tester.pumpAndSettle();

      // Alt çubuktaki "Sıralama" sekmesine dokun
      final leaderboardTab = find.text(AppStrings.navLeaderboard);
      expect(leaderboardTab, findsOneWidget);

      await tester.tap(leaderboardTab);
      await tester.pumpAndSettle();

      expect(find.byType(LeaderboardScreen), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_back_button')), findsNothing);
      expect(fakeClient.fetchCallCount, 1);
    });

    testWidgets('4. 360 dp dar ekranda uzun takma ad (16 karakter) ile taşma olmadan çizilir',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeClient = FakeLeaderboardApiClient();

      await tester.pumpWidget(_buildMainShellApp(
        leaderboardClient: fakeClient,
        nickname: 'MuhammedMustafa_',
        coins: 1500,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('leaderboard_button')), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_button')), findsOneWidget);
    });
  });
}
