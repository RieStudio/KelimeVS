import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/profile_notifier.dart';
import '../data/leaderboard_api_client.dart';
import '../domain/models/leaderboard_models.dart';

final leaderboardApiClientProvider = Provider<LeaderboardApiClient>((ref) {
  final authProvider = ref.watch(authTokenProviderForProfile);
  return HttpLeaderboardApiClient(authTokenProvider: authProvider);
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
    AsyncNotifierProvider<LeaderboardNotifier, LeaderboardData>(() {
  return LeaderboardNotifier();
});

