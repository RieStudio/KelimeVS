import '../../auth/application/auth_notifier.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/profile_notifier.dart';
import '../data/leaderboard_api_client.dart';
import '../domain/models/leaderboard_models.dart';

final leaderboardApiClientProvider = Provider<LeaderboardApiClient>((ref) {
  final authProvider = ref.watch(authTokenProviderForProfile);
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpLeaderboardApiClient(
    authTokenProvider: authProvider,
    onAccountDeleted: onDeleted,
  );
});

class LeaderboardNotifier extends AsyncNotifier<LeaderboardData> {
  @override
  Future<LeaderboardData> build() async {
    final client = ref.watch(leaderboardApiClientProvider);
    return client.fetchLeaderboard();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(leaderboardApiClientProvider);
      return client.fetchLeaderboard();
    });
  }
}

final leaderboardNotifierProvider =
    AsyncNotifierProvider.autoDispose<LeaderboardNotifier, LeaderboardData>(() {
  return LeaderboardNotifier();
});

