import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/objection_provider.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/data/local_objection_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/text_filter.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:app/features/match_detail/presentation/match_detail_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/application/public_profile_provider.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';
import 'package:app/features/profile/presentation/public_profile_screen.dart';

class FakeUser implements User {
  @override
  final String uid;
  FakeUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  final User? user;
  FakeAuthRepository([this.user]);

  @override
  User? get currentUser => user;

  @override
  bool get isAuthenticated => user != null;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);

  @override
  bool get isGoogleLinked => false;

  @override
  String? get linkedEmail => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLeaderboardApiClient implements LeaderboardApiClient {
  LeaderboardData dataToReturn;

  FakeLeaderboardApiClient({required this.dataToReturn});

  @override
  Future<LeaderboardData> fetchLeaderboard() async => dataToReturn;
}

class _TestProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  _TestProfileNotifier(this._state);

  @override
  ProfileState build() => _state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'my_self_uid';
  late SharedPreferences prefs;
  late LocalObjectionRepository objectionRepo;
  late LocalMatchHistoryRepository historyRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    objectionRepo = LocalObjectionRepository(prefs: prefs);
    historyRepo = LocalMatchHistoryRepository(
      prefs: prefs,
      objectionRepository: objectionRepo,
    );
  });

  Widget createTestWidget({
    required Widget child,
    LeaderboardApiClient? leaderboardClient,
    ProfileState? profileState,
  }) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(FakeUser(currentUserId)),
        ),
        if (leaderboardClient != null)
          leaderboardApiClientProvider.overrideWithValue(leaderboardClient),
        if (profileState != null)
          profileProvider.overrideWith(() => _TestProfileNotifier(profileState)),
        objectionRepositoryProvider.overrideWithValue(objectionRepo),
        matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
        textFilterProvider.overrideWithValue(const PassthroughTextFilter()),
        publicProfileProvider.overrideWith((ref, uid) async {
          return PublicProfile(
            uid: uid,
            nickname: 'Rakip $uid',
            equippedFrame: 'classic',
            stats: const PublicProfileStats(
              played: 10,
              won: 7,
              lost: 3,
              winRate: 70,
            ),
            isGuest: false,
            isBlocked: false,
          );
        }),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('LeaderboardScreen Entry Points Tests', () {
    testWidgets(
      '1. Sıralama listesinde geçerli uid içeren rakip satırında chevron görünür ve dokunulunca PublicProfileScreen açılır',
      (tester) async {
        final client = FakeLeaderboardApiClient(
          dataToReturn: const LeaderboardData(
            weekKey: '2026-W42',
            endsAt: 1792357200000,
            top: [
              LeaderboardEntry(
                rank: 1,
                nickname: 'Sampiyon',
                wins: 50,
                isMe: false,
                uid: 'user_champ_123',
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const LeaderboardScreen(),
            leaderboardClient: client,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sampiyon'), findsOneWidget);
        // Chevron ikonu sağda bulunmalı
        expect(find.byType(AppIcon), findsWidgets);

        // Satıra dokun
        await tester.tap(find.text('Sampiyon'));
        await tester.pumpAndSettle();

        // PublicProfileScreen açılmış olmalı
        expect(find.byType(PublicProfileScreen), findsOneWidget);
        final publicProfile = tester.widget<PublicProfileScreen>(
          find.byType(PublicProfileScreen),
        );
        expect(publicProfile.uid, 'user_champ_123');
      },
    );

    testWidgets(
      '2. Sıralama listesinde uid null olan satır pasiftir (chevron yok, dokununca profil açılmaz)',
      (tester) async {
        final client = FakeLeaderboardApiClient(
          dataToReturn: const LeaderboardData(
            weekKey: '2026-W42',
            endsAt: 1792357200000,
            top: [
              LeaderboardEntry(
                rank: 2,
                nickname: 'LegacyOyuncu',
                wins: 30,
                isMe: false,
                uid: null, // Legacy / uid'siz satır
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const LeaderboardScreen(),
            leaderboardClient: client,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('LegacyOyuncu'), findsOneWidget);

        // Satıra dokun
        await tester.tap(find.text('LegacyOyuncu'));
        await tester.pumpAndSettle();

        // PublicProfileScreen AÇILMAMALI
        expect(find.byType(PublicProfileScreen), findsNothing);
      },
    );

    testWidgets(
      '3. Sıralama listesinde kendi satırına dokunulunca PublicProfileScreen açılmaz, kendi profiline yönlendirilir',
      (tester) async {
        final client = FakeLeaderboardApiClient(
          dataToReturn: const LeaderboardData(
            weekKey: '2026-W42',
            endsAt: 1792357200000,
            top: [
              LeaderboardEntry(
                rank: 1,
                nickname: 'BenKendim',
                wins: 100,
                isMe: true,
                uid: currentUserId,
              ),
            ],
          ),
        );

        // Standalone push senaryosu (canPop == true)
        await tester.pumpWidget(
          createTestWidget(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen(),
                      ),
                    );
                  },
                  child: const Text('Liderlik Aç'),
                );
              },
            ),
            leaderboardClient: client,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Liderlik Aç'));
        await tester.pumpAndSettle();

        expect(find.text('BenKendim'), findsOneWidget);

        // Kendi satırıma dokun
        await tester.tap(find.text('BenKendim'));
        await tester.pumpAndSettle();

        // PublicProfileScreen AÇILMAMALI
        expect(find.byType(PublicProfileScreen), findsNothing);
        // Kendi ProfileScreen açılmış olmalı
        expect(find.byType(ProfileScreen), findsOneWidget);
      },
    );

    testWidgets(
      '4. Senin Sıran yapışkan çubuğuna dokunulunca kendi profiline yönlendirilir',
      (tester) async {
        final client = FakeLeaderboardApiClient(
          dataToReturn: const LeaderboardData(
            weekKey: '2026-W42',
            endsAt: 1792357200000,
            top: [
              LeaderboardEntry(
                rank: 1,
                nickname: 'BaskaBiri',
                wins: 100,
                isMe: false,
                uid: 'other_uid',
              ),
            ],
            me: LeaderboardMe(rank: 150, wins: 10),
          ),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen(),
                      ),
                    );
                  },
                  child: const Text('Liderlik Aç'),
                );
              },
            ),
            leaderboardClient: client,
            profileState: const ProfileState(
              nickname: 'BenimTakmaAdim',
              coins: 50,
              isLoaded: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Liderlik Aç'));
        await tester.pumpAndSettle();

        // Yapışkan çubuk ekranda görünür
        expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);

        // Çubuğa dokun
        await tester.tap(find.byKey(const Key('leaderboard_sticky_me')));
        await tester.pumpAndSettle();

        // PublicProfileScreen AÇILMAMALI
        expect(find.byType(PublicProfileScreen), findsNothing);
        // Kendi ProfileScreen açılmış olmalı
        expect(find.byType(ProfileScreen), findsOneWidget);
      },
    );
  });

  group('MatchDetailScreen Entry Points Tests', () {
    testWidgets(
      '5. Maç detayında opponentUid dolu ve gerçek rakip ise chevron görünür ve dokunulunca PublicProfileScreen açılır',
      (tester) async {
        const match = MatchHistoryEntry(
          id: 'test_m1',
          matchId: 'online_101',
          opponentName: 'Zeynep',
          opponentUid: 'user_zeynep_88',
          finishedAtMs: 1729452000000,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
          botlaOynandi: false,
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const MatchDetailScreen(match: match),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Zeynep'), findsOneWidget);

        // Zeynep avatar / adı bölgesine dokun
        await tester.tap(find.text('Zeynep'));
        await tester.pumpAndSettle();

        // PublicProfileScreen açılmalı
        expect(find.byType(PublicProfileScreen), findsOneWidget);
        final screen = tester.widget<PublicProfileScreen>(
          find.byType(PublicProfileScreen),
        );
        expect(screen.uid, 'user_zeynep_88');
      },
    );

    testWidgets(
      '6. Maç detayında opponentUid null ise (eski kayıt veya yerel maç) pasiftir ve PublicProfileScreen açılmaz',
      (tester) async {
        const match = MatchHistoryEntry(
          id: 'test_legacy',
          matchId: 'legacy_001',
          opponentName: 'EskiRakip',
          opponentUid: null, // UID yok
          finishedAtMs: 1700000000000,
          myScore: 2,
          opponentScore: 0,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
          botlaOynandi: false,
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const MatchDetailScreen(match: match),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('EskiRakip'), findsOneWidget);

        // Dokun
        await tester.tap(find.text('EskiRakip'));
        await tester.pumpAndSettle();

        // Profil açılmamalı
        expect(find.byType(PublicProfileScreen), findsNothing);
      },
    );

    testWidgets(
      '7. Maç detayında bot maçı ise (botlaOynandi: true) pasiftir ve PublicProfileScreen açılmaz',
      (tester) async {
        const match = MatchHistoryEntry(
          id: 'test_bot',
          matchId: 'bot_002',
          opponentName: 'M-1234',
          opponentUid: 'bot_fake_uid',
          finishedAtMs: 1729452000000,
          myScore: 2,
          opponentScore: 0,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
          botlaOynandi: true, // Bot bayrağı aktif
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const MatchDetailScreen(match: match),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('M-1234'), findsOneWidget);

        // Dokun
        await tester.tap(find.text('M-1234'));
        await tester.pumpAndSettle();

        // Profil açılmamalı
        expect(find.byType(PublicProfileScreen), findsNothing);
      },
    );

    testWidgets(
      '8. Maç detayında opponentUid kullanıcının kendi uid ise güvenlik gereği pasif kalır',
      (tester) async {
        const match = MatchHistoryEntry(
          id: 'test_self',
          matchId: 'self_003',
          opponentName: 'Kendim',
          opponentUid: currentUserId, // Kendi UID'si
          finishedAtMs: 1729452000000,
          myScore: 2,
          opponentScore: 2,
          result: MatchResult.lose,
          endType: MatchEndType.normal,
          roundRecords: [],
          botlaOynandi: false,
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const MatchDetailScreen(match: match),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Kendim'), findsOneWidget);

        // Dokun
        await tester.tap(find.text('Kendim'));
        await tester.pumpAndSettle();

        // Profil açılmamalı
        expect(find.byType(PublicProfileScreen), findsNothing);
      },
    );
  });
}
