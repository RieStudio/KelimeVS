import 'package:app/core/network/network_service.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => [];
}

class FakeProfileNotifier extends ProfileNotifier {
  @override
  ProfileState build() {
    return const ProfileState(
      nickname: 'TestUser',
      coins: 100,
      isLoaded: true,
    );
  }
}

class FakeOfflineNetworkService implements NetworkService {
  @override
  Future<bool> checkPhysicalConnection() async => false;

  @override
  Stream<bool> get onPhysicalConnectionChanged => const Stream.empty();

  @override
  Future<bool> probeServerHealth() async => false;
}

class FakeOnlineNetworkService implements NetworkService {
  @override
  Future<bool> checkPhysicalConnection() async => true;

  @override
  Stream<bool> get onPhysicalConnectionChanged => const Stream.empty();

  @override
  Future<bool> probeServerHealth() async => true;
}

void main() {
  group('HomeScreen Ağ Koruması (Network Guard) Testleri', () {
    testWidgets('1. İnternet yokken Hızlı Maç tıklandığında maç başlamaz ve SnackBar uyarısı verilir', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(FakeOfflineNetworkService()),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(FakeProfileNotifier.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hızlı Maç butonuna dokun
      await tester.tap(find.text(AppStrings.quickMatch));
      await tester.pumpAndSettle();

      // Matchmaking ekranı açılmamalı
      expect(find.byType(MatchmakingScreen), findsNothing);

      // SnackBar uyarısı çıkmalı
      expect(find.text(AppStrings.noInternetActionError), findsOneWidget);
    });

    testWidgets('2. İnternet yokken Arkadaşınla Oyna tıklandığında modal açılmaz ve SnackBar uyarısı verilir', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(FakeOfflineNetworkService()),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(FakeProfileNotifier.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Arkadaşınla Oyna butonuna dokun
      await tester.tap(find.text(AppStrings.playWithFriend));
      await tester.pumpAndSettle();

      // Modal açılmamalı
      expect(find.text(AppStrings.createRoom), findsNothing);

      // SnackBar uyarısı çıkmalı
      expect(find.text(AppStrings.noInternetActionError), findsOneWidget);
    });

    testWidgets('3. İnternet varken Hızlı Maç tıklandığında MatchmakingScreen normal açılır', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(FakeOnlineNetworkService()),
            matchHistoryRepositoryProvider.overrideWithValue(FakeMatchHistoryRepository()),
            profileProvider.overrideWith(FakeProfileNotifier.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.quickMatch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Matchmaking ekranı açılmış olmalı
      expect(find.byType(MatchmakingScreen), findsOneWidget);
    });
  });
}
