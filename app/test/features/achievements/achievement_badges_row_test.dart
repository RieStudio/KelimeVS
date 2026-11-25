import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/achievements/domain/user_achievement.dart';
import 'package:app/features/achievements/presentation/widgets/achievement_badges_row.dart';
import 'package:app/features/achievements/presentation/widgets/achievement_detail_sheet.dart';
import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRepo implements AuthRepository {
  @override
  bool get isAuthenticated => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileApiClient implements ProfileApiClient {
  UserProfileModel? nextProfile;

  @override
  Future<UserProfileModel?> getProfile() async => nextProfile;
  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);
  @override
  Future<bool> deleteProfile() async => true;
  @override
  Future<bool> updateAllowMatchRequests(bool allow) async => allow;
}

void main() {
  group('UserAchievement & PublicProfile JSON Parse', () {
    test('UserAchievement count yoksa varsayılan 1 alır, <1 ise 1 olur', () {
      final a1 = UserAchievement.fromJson({'id': 'first_match', 'unlockedAt': 1000});
      expect(a1.id, 'first_match');
      expect(a1.unlockedAt, 1000);
      expect(a1.count, 1);

      final a2 = UserAchievement.fromJson({'id': 'streak_3', 'unlockedAt': 2000, 'count': 8});
      expect(a2.count, 8);

      final a3 = UserAchievement.fromJson({'id': 'streak_5', 'unlockedAt': 3000, 'count': 0});
      expect(a3.count, 1);
    });

    test('PublicProfile achievements parse edilir ve alan yoksa [] döner', () {
      final withoutAch = PublicProfile.fromJson({
        'uid': 'u1',
        'nickname': 'Ali',
      });
      expect(withoutAch.achievements, isEmpty);

      final withAch = PublicProfile.fromJson({
        'uid': 'u2',
        'nickname': 'Veli',
        'achievements': [
          {'id': 'first_match', 'unlockedAt': 1000},
          {'id': 'streak_3', 'unlockedAt': 2000, 'count': 4},
        ],
      });
      expect(withAch.achievements.length, 2);
      expect(withAch.achievements[0], const UserAchievement(id: 'first_match', unlockedAt: 1000, count: 1));
      expect(withAch.achievements[1], const UserAchievement(id: 'streak_3', unlockedAt: 2000, count: 4));
    });
  });

  group('ProfileState & ProfileNotifier Achievements Sync / Account Switch', () {
    test('syncWithServer achievements, currentStreak ve maxStreak taşır; hesap geçişinde temizlenir', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeApi = _FakeProfileApiClient()
        ..nextProfile = const UserProfileModel(
          uid: 'acc_1',
          nickname: 'Hesap1',
          coins: 100,
          currentStreak: 3,
          maxStreak: 5,
          achievements: [
            UserAchievement(id: 'streak_3', unlockedAt: 5000, count: 2),
          ],
        );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
          profileRepositoryProvider.overrideWithValue(const LocalProfileRepository()),
          profileApiClientProvider.overrideWithValue(fakeApi),
        ],
      );
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).syncWithServer(force: true);
      var state = container.read(profileProvider);
      expect(state.achievements.length, 1);
      expect(state.achievements.first.count, 2);
      expect(state.currentStreak, 3);
      expect(state.maxStreak, 5);

      // Yeni hesaba geçiş -> önceki hesabın rozetleri asla kalmamalı
      fakeApi.nextProfile = const UserProfileModel(
        uid: 'acc_2',
        nickname: 'Hesap2',
        coins: 100,
        currentStreak: 0,
        maxStreak: 0,
        achievements: [],
      );
      await container.read(profileProvider.notifier).loadProfileForSwitchedAccount();
      state = container.read(profileProvider);
      expect(state.nickname, 'Hesap2');
      expect(state.achievements, isEmpty);
      expect(state.currentStreak, 0);
      expect(state.maxStreak, 0);
    });
  });

  group('AchievementBadgesRow & AchievementDetailSheet Widget Tests', () {
    testWidgets('Boş veya yalnızca bilinmeyen ID listesinde widget gizlenir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AchievementBadgesRow(
              achievements: [
                UserAchievement(id: 'unknown_id', unlockedAt: 1000),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('<=4 rozette 360dp ve 320dp ekranlarda 4 rozet tam sığar ve sağ solma (ShaderMask) yoktur, count=1 sayaç göstermez', (tester) async {
      for (final width in [360.0, 320.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.reset());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AchievementBadgesRow(
                achievements: [
                  UserAchievement(id: 'first_match', unlockedAt: 1000, count: 1),
                  UserAchievement(id: 'first_win', unlockedAt: 2000, count: 1),
                  UserAchievement(id: 'matches_10', unlockedAt: 3000, count: 1),
                  UserAchievement(id: 'wins_10', unlockedAt: 4000, count: 1),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(AchievementBadgesRow)).width, width);
        // İlk rozet soldan 20 px içeride başlar
        final firstBadge = find.bySemanticsLabel(
          AppStrings.achievementBadgeSemantic('Yükselen Yıldız', 1),
        );
        expect(tester.getTopLeft(firstBadge).dx, 20.0);

        final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
        expect(scrollable.position.maxScrollExtent, 0.0);
        expect(find.text('x1'), findsNothing);
      }
    });

    testWidgets('5+ rozette sağ uca kaydırınca ofset sıfırlanmaz, parent rebuildde korunur ve solma sona gelince kalkar', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      Widget buildRow(List<UserAchievement> list) => MaterialApp(
            home: Scaffold(
              body: AchievementBadgesRow(achievements: list),
            ),
          );

      final initialList = [
        const UserAchievement(id: 'first_match', unlockedAt: 1000),
        const UserAchievement(id: 'first_win', unlockedAt: 2000),
        const UserAchievement(id: 'matches_10', unlockedAt: 3000),
        const UserAchievement(id: 'streak_3', unlockedAt: 4000, count: 8),
        const UserAchievement(id: 'wins_10', unlockedAt: 5000),
        const UserAchievement(id: 'matches_50', unlockedAt: 6000),
      ];

      await tester.pumpWidget(buildRow(initialList));
      await tester.pumpAndSettle();

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.text('x8'), findsOneWidget);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final maxExtent = scrollable.position.maxScrollExtent;
      expect(maxExtent, greaterThan(0.0));

      // En sağa kaydır
      await tester.drag(find.byType(ListView), Offset(-maxExtent - 50, 0));
      await tester.pumpAndSettle();

      // Sona gelince ofset sıfırlanmamalı (en sonda kalmalı)
      expect(scrollable.position.pixels, closeTo(maxExtent, 1.0));

      // Parent aynı içerikte yeni liste nesnesiyle rebuild olduğunda da ofset korunmalı
      await tester.pumpWidget(buildRow(List<UserAchievement>.from(initialList)));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(maxExtent, 1.0));
    });

    testWidgets('Rozete dokununca AchievementDetailSheet başlık, açıklama, tarih ve tekrar sayısı ile açılır', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      final unlockedMs = DateTime(2026, 11, 25, 14, 30).millisecondsSinceEpoch;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementBadgesRow(
              achievements: [
                UserAchievement(id: 'streak_3', unlockedAt: unlockedMs, count: 8),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel(AppStrings.achievementBadgeSemantic('Üçlü Seri', 8)));
      await tester.pumpAndSettle();

      expect(find.byType(AchievementDetailSheet), findsOneWidget);
      expect(find.text('Üçlü Seri'), findsOneWidget);
      expect(find.text('Üst üste 3 maç kazan'), findsOneWidget);
      expect(find.text('İlk açılış: 25 Kasım 2026'), findsOneWidget);
      expect(find.text('x8 kez kazanıldı'), findsOneWidget);
    });
  });
}
