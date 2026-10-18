import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}
  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => const [];
  @override
  Future<void> clear() async {}
}

class FakeLeaderboardApiClient implements LeaderboardApiClient {
  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    return const LeaderboardData(
      weekKey: '2026-W42',
      endsAt: 1792357200000,
      top: [],
    );
  }
}

Widget _buildHomeScreen({
  String? nickname,
  int coins = 100,
}) {
  return ProviderScope(
    overrides: [
      matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
      leaderboardApiClientProvider.overrideWithValue(FakeLeaderboardApiClient()),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, child) {
          if (nickname != null) {
            Future.microtask(() {
              ref.read(profileProvider.notifier).state = ProfileState(
                nickname: nickname,
                coins: coins,
                isLoaded: true,
              );
            });
          }
          return const HomeScreen();
        },
      ),
    ),
  );
}

void main() {
  group('HomeScreen Leaderboard Button & Responsiveness', () {
    testWidgets('1. Ana ekranda kupa butonu bulunur ve tıklandığında LeaderboardScreen açılır',
        (tester) async {
      await tester.pumpWidget(_buildHomeScreen());
      await tester.pumpAndSettle();

      final trophyButton = find.byKey(const Key('leaderboard_button'));
      expect(trophyButton, findsOneWidget);

      await tester.tap(trophyButton);
      await tester.pumpAndSettle();

      expect(find.byType(LeaderboardScreen), findsOneWidget);
      expect(find.text(AppStrings.leaderboardTitle), findsOneWidget);
    });

    testWidgets('2. 360 dp dar ekranda uzun takma ad (16 karakter) ile taşma olmadan çizilir',
        (tester) async {
      // 360x640 dp ekran boyutu ayarla
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 16 karakterlik sınır takma ad ve 4 haneli jeton
      await tester.pumpWidget(_buildHomeScreen(
        nickname: 'MuhammedMustafa_',
        coins: 1500,
      ));
      await tester.pumpAndSettle();

      // RenderFlex overflow hatası yakalanmamalı (0 exceptions)
      expect(tester.takeException(), isNull);

      // Kupa butonu ve profil bileşenleri görünür olmalı
      expect(find.byKey(const Key('leaderboard_button')), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_button')), findsOneWidget);
    });
  });
}
