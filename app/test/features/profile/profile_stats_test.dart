import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';

class _MockProfileNotifier extends ProfileNotifier {
  final ProfileState _mockState;

  _MockProfileNotifier(this._mockState);

  @override
  ProfileState build() => _mockState;

  @override
  Future<void> syncWithServer() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserStats Unit Tests', () {
    test('Default values are all zero and winRateDisplay is dash', () {
      const stats = UserStats();
      expect(stats.played, 0);
      expect(stats.won, 0);
      expect(stats.lost, 0);
      expect(stats.correctAnswers, 0);
      expect(stats.winRateRatio, isNull);
      expect(stats.winRateDisplay, '—');
    });

    test('winRateDisplay formats correctly and rounds properly', () {
      // 2/3 -> 66.666...% -> %67
      const stats2of3 = UserStats(played: 3, won: 2, lost: 1);
      expect(stats2of3.winRateRatio, closeTo(2 / 3, 0.0001));
      expect(stats2of3.winRateDisplay, '%67');

      // 1/3 -> 33.333...% -> %33
      const stats1of3 = UserStats(played: 3, won: 1, lost: 2);
      expect(stats1of3.winRateRatio, closeTo(1 / 3, 0.0001));
      expect(stats1of3.winRateDisplay, '%33');

      // 0/5 -> 0% -> %0
      const stats0of5 = UserStats(played: 5, won: 0, lost: 5);
      expect(stats0of5.winRateRatio, 0.0);
      expect(stats0of5.winRateDisplay, '%0');

      // 5/5 -> 100% -> %100
      const stats5of5 = UserStats(played: 5, won: 5, lost: 0);
      expect(stats5of5.winRateRatio, 1.0);
      expect(stats5of5.winRateDisplay, '%100');

      // 1/2 -> 50% -> %50
      const stats1of2 = UserStats(played: 2, won: 1, lost: 1);
      expect(stats1of2.winRateRatio, 0.5);
      expect(stats1of2.winRateDisplay, '%50');

      // played <= 0 -> "—"
      const stats0 = UserStats(played: 0, won: 0, lost: 0);
      expect(stats0.winRateDisplay, '—');
    });

    test('Serialization roundtrip works', () {
      const stats = UserStats(
        played: 42,
        won: 28,
        lost: 14,
        correctAnswers: 156,
      );
      final json = stats.toJson();
      expect(json['played'], 42);
      expect(json['won'], 28);
      expect(json['lost'], 14);
      expect(json['correctAnswers'], 156);

      final reconstructed = UserStats.fromJson(json);
      expect(reconstructed.played, 42);
      expect(reconstructed.won, 28);
      expect(reconstructed.lost, 14);
      expect(reconstructed.correctAnswers, 156);
      expect(reconstructed.winRateDisplay, '%67');
    });

    test('UserProfileModel exposes stats and delegates properties', () {
      const profile = UserProfileModel(
        uid: 'user_123',
        nickname: 'Alice',
        coins: 200,
        equippedFrame: 'gold',
        stats: UserStats(
          played: 10,
          won: 7,
          lost: 3,
          correctAnswers: 30,
        ),
      );

      expect(profile.stats.played, 10);
      expect(profile.stats.correctAnswers, 30);
      expect(profile.played, 10);
      expect(profile.won, 7);
      expect(profile.lost, 3);
      expect(profile.correctAnswers, 30);
      expect(profile.winRateRatio, 0.7);
      expect(profile.winRateDisplay, '%70');

      final fromJson = UserProfileModel.fromJson({
        'uid': 'user_123',
        'nickname': 'Alice',
        'coins': 200,
        'stats': {
          'played': 10,
          'won': 7,
          'lost': 3,
          'correctAnswers': 30,
        },
      });
      expect(fromJson.stats.played, 10);
      expect(fromJson.stats.correctAnswers, 30);
      expect(fromJson.winRateDisplay, '%70');
    });
  });

  group('LocalProfileRepository UID Isolation & Cache Tests', () {
    test('Stats are isolated by UID and never leak between accounts', () async {
      SharedPreferences.setMockInitialValues({});
      const repo = LocalProfileRepository();

      // User A saves stats
      await repo.setStats(
        'user_a',
        const UserStats(played: 15, won: 10, lost: 5, correctAnswers: 45),
      );

      // Verify User A can retrieve stats
      final userAStats = await repo.getStats(uid: 'user_a');
      expect(userAStats.played, 15);
      expect(userAStats.won, 10);
      expect(userAStats.lost, 5);
      expect(userAStats.correctAnswers, 45);

      // User B should get empty/zero stats
      final userBStats = await repo.getStats(uid: 'user_b');
      expect(userBStats.played, 0);
      expect(userBStats.won, 0);
      expect(userBStats.lost, 0);
      expect(userBStats.correctAnswers, 0);
      expect(userBStats.winRateDisplay, '—');

      // User B saves their own stats
      await repo.setStats(
        'user_b',
        const UserStats(played: 2, won: 1, lost: 1, correctAnswers: 8),
      );

      // Verify User A stats are unchanged and User B stats are separate
      final recheckedA = await repo.getStats(uid: 'user_a');
      final recheckedB = await repo.getStats(uid: 'user_b');
      expect(recheckedA.played, 15);
      expect(recheckedA.correctAnswers, 45);
      expect(recheckedB.played, 2);
      expect(recheckedB.correctAnswers, 8);

      // Clear for User A only
      await repo.clear(uid: 'user_a');
      final clearedA = await repo.getStats(uid: 'user_a');
      expect(clearedA.played, 0);
      expect(clearedA.correctAnswers, 0);

      // User B's stats should still be intact
      final untouchedB = await repo.getStats(uid: 'user_b');
      expect(untouchedB.played, 2);
      expect(untouchedB.correctAnswers, 8);
    });

    test('Calling clear() without UID clears current cached UID stats and resets UID marker', () async {
      SharedPreferences.setMockInitialValues({});
      const repo = LocalProfileRepository();

      await repo.setStats(
        'user_x',
        const UserStats(played: 8, won: 4, lost: 4, correctAnswers: 20),
      );

      await repo.clear();

      final statsAfter = await repo.getStats(uid: 'user_x');
      expect(statsAfter.played, 0);
      expect(statsAfter.correctAnswers, 0);

      final statsDefault = await repo.getStats();
      expect(statsDefault.played, 0);
    });
  });

  group('ProfileScreen Widget Tests - Player Statistics', () {
    testWidgets('Renders 3 stat cards: Oynanan Maç, Doğru Cevap, Kazanma with dash for 0 matches', (tester) async {
      SharedPreferences.setMockInitialValues({
        LocalProfileRepository.keyNickname: 'TestPlayer',
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.statsPlayed), findsOneWidget);
      expect(find.text(AppStrings.statsCorrectAnswers), findsOneWidget);
      expect(find.text(AppStrings.statsWinRate), findsOneWidget);

      // Default state has played: 0, correctAnswers: 0, winRate: "—"
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2)); // Oynanan Maç: 0, Doğru Cevap: 0
    });

    testWidgets('Renders non-zero stats correctly when loaded in ProfileState', (tester) async {
      final mockState = const ProfileState(
        isLoaded: true,
        nickname: 'ProGamer',
        stats: UserStats(
          played: 30,
          won: 20,
          lost: 10,
          correctAnswers: 85,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _MockProfileNotifier(mockState)),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('30'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('%67'), findsOneWidget); // 20/30 = 66.6% -> %67
      expect(find.text(AppStrings.statsPlayed), findsOneWidget);
      expect(find.text(AppStrings.statsCorrectAnswers), findsOneWidget);
      expect(find.text(AppStrings.statsWinRate), findsOneWidget);
    });

    testWidgets('Does not overflow at 320 dp width and 1.5 textScaler (Accessibility) with equal card heights', (tester) async {
      final mockState = const ProfileState(
        isLoaded: true,
        nickname: 'LongPlayerNameHere',
        stats: UserStats(
          played: 9999,
          won: 6666,
          lost: 3333,
          correctAnswers: 12345,
        ),
      );

      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _MockProfileNotifier(mockState)),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.5),
              ),
              child: ProfileScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex or text overflow exceptions thrown!
      expect(tester.takeException(), isNull);

      // Verify that values are present and rendered
      expect(find.text('9999'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
      expect(find.text('%67'), findsOneWidget);

      final playedCardFinder = find.ancestor(
        of: find.text(AppStrings.statsPlayed),
        matching: find.byType(Container),
      ).first;
      final winRateCardFinder = find.ancestor(
        of: find.text(AppStrings.statsWinRate),
        matching: find.byType(Container),
      ).first;

      final playedHeight = tester.getSize(playedCardFinder).height;
      final winRateHeight = tester.getSize(winRateCardFinder).height;
      expect(playedHeight, equals(winRateHeight));
    });

    testWidgets('Verify card dimensions and equal heights at 360 dp', (tester) async {
      final mockState = const ProfileState(
        isLoaded: true,
        nickname: 'Player',
        stats: UserStats(
          played: 10,
          won: 5,
          lost: 5,
          correctAnswers: 25,
        ),
      );

      tester.view.physicalSize = const Size(360 * 2.0, 800 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => _MockProfileNotifier(mockState)),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.0),
              ),
              child: ProfileScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.statsPlayed), findsOneWidget);
      expect(find.text(AppStrings.statsCorrectAnswers), findsOneWidget);
      expect(find.text(AppStrings.statsWinRate), findsOneWidget);

      final playedCardFinder = find.ancestor(
        of: find.text(AppStrings.statsPlayed),
        matching: find.byType(Container),
      ).first;
      final correctCardFinder = find.ancestor(
        of: find.text(AppStrings.statsCorrectAnswers),
        matching: find.byType(Container),
      ).first;
      final winRateCardFinder = find.ancestor(
        of: find.text(AppStrings.statsWinRate),
        matching: find.byType(Container),
      ).first;

      final playedHeight = tester.getSize(playedCardFinder).height;
      final correctHeight = tester.getSize(correctCardFinder).height;
      final winRateHeight = tester.getSize(winRateCardFinder).height;

      expect(playedHeight, equals(correctHeight));
      expect(correctHeight, equals(winRateHeight));
    });
  });
}

