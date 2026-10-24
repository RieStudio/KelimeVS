import 'dart:async';

import 'package:app/core/network/network_service.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/global_offline_banner.dart';
import 'package:app/core/widgets/offline_splash_screen.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControllableNetworkService implements NetworkService {
  bool hasPhysical;
  bool isReachable;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  ControllableNetworkService({
    this.hasPhysical = false,
    this.isReachable = false,
  });

  @override
  Future<bool> checkPhysicalConnection() async => hasPhysical;

  @override
  Stream<bool> get onPhysicalConnectionChanged => _controller.stream;

  void emitPhysicalConnection(bool value) {
    hasPhysical = value;
    _controller.add(value);
  }

  @override
  Future<bool> probeServerHealth() async => isReachable;

  void dispose() {
    _controller.close();
  }
}

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => [];
}

class FakeProfileNotifier extends ProfileNotifier {
  int syncCallCount = 0;

  @override
  ProfileState build() {
    return const ProfileState(
      nickname: 'TestPlayer',
      coins: 100,
      isLoaded: true,
    );
  }

  @override
  Future<void> syncWithServer() async {
    syncCallCount++;
  }
}

class FakeLeaderboardClient implements LeaderboardApiClient {
  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    return const LeaderboardData(
      weekKey: '2026-W42',
      endsAt: 1792357200000,
      top: [],
    );
  }
}

void main() {
  group('App Startup & Lifecycle Network Tests', () {
    late ControllableNetworkService netService;
    late FakeProfileNotifier fakeProfile;

    setUp(() {
      netService = ControllableNetworkService(hasPhysical: false, isReachable: false);
      fakeProfile = FakeProfileNotifier();
    });

    tearDown(() {
      netService.dispose();
    });

    testWidgets('1. Açılışta internet yoksa OfflineSplashScreen gösterilir; bağlantı gelince otomatik devam eder', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(netService),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(() => fakeProfile),
            leaderboardApiClientProvider.overrideWithValue(FakeLeaderboardClient()),
          ],
          child: const KelimeVSApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Açılışta tam ekran OfflineSplashScreen olmalı
      expect(find.byType(OfflineSplashScreen), findsOneWidget);
      expect(find.text(AppStrings.noInternetTitle), findsOneWidget);
      expect(find.text(AppStrings.quickMatch), findsNothing);

      // Bağlantı geldi
      netService.hasPhysical = true;
      netService.isReachable = true;
      netService.emitPhysicalConnection(true);

      await tester.pumpAndSettle();

      // OfflineSplashScreen kapanmalı ve ana ekran gelmeli
      expect(find.byType(OfflineSplashScreen), findsNothing);
      expect(find.text(AppStrings.quickMatch), findsOneWidget);
      // Profil senkronu tetiklenmiş olmalı
      expect(fakeProfile.syncCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('2. Menülerdeyken bağlantı kopunca (2 sn sonra) GlobalOfflineBanner içeriği aşağı iter', (tester) async {
      netService.hasPhysical = true;
      netService.isReachable = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(netService),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(() => fakeProfile),
            leaderboardApiClientProvider.overrideWithValue(FakeLeaderboardClient()),
          ],
          child: const KelimeVSApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.quickMatch), findsOneWidget);
      expect(find.byType(GlobalOfflineBanner), findsNothing);

      // Bağlantı koptu
      netService.hasPhysical = false;
      netService.isReachable = false;
      netService.emitPhysicalConnection(false);

      // 2 saniyelik debounce süresini ilerlet
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GlobalOfflineBanner), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Global şerit görünmeli
      expect(find.byType(GlobalOfflineBanner), findsOneWidget);
      expect(find.text(AppStrings.noInternetBanner), findsOneWidget);

      // Bağlantı geri geldiğinde kendiliğinden kaybolmalı
      netService.hasPhysical = true;
      netService.isReachable = true;
      netService.emitPhysicalConnection(true);

      await tester.pumpAndSettle();
      expect(find.byType(GlobalOfflineBanner), findsNothing);
    });

    testWidgets('3. Maç ekranında (MatchScreen) global şerit bastırılır', (tester) async {
      netService.hasPhysical = true;
      netService.isReachable = true;

      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(netService),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(() => fakeProfile),
            leaderboardApiClientProvider.overrideWithValue(FakeLeaderboardClient()),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                savedRef = ref;
                return const Scaffold(body: MatchScreen());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Maç ekranı açılınca suppression true olmalı
      expect(savedRef.read(isOfflineBannerSuppressedProvider), true);
    });
  });
}
