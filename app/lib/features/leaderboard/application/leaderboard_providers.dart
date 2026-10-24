import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
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

class LeaderboardSyncErrorNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;

  void setError(Object? error) => state = error;
  void clear() => state = null;
}

final leaderboardSyncErrorProvider =
    NotifierProvider.autoDispose<LeaderboardSyncErrorNotifier, Object?>(
  LeaderboardSyncErrorNotifier.new,
);

class LeaderboardNotifier extends AsyncNotifier<LeaderboardData> {
  Object? _syncError;
  Object? get syncError => _syncError;

  @override
  Future<LeaderboardData> build() async {
    _syncError = null;
    final client = ref.watch(leaderboardApiClientProvider);
    final data = await client.fetchLeaderboard();
    ref.read(leaderboardSyncErrorProvider.notifier).clear();
    return data;
  }

  Future<void> refresh() async {
    if (state.isLoading && !state.hasValue) return;

    final client = ref.read(leaderboardApiClientProvider);
    if (!state.hasValue) {
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => client.fetchLeaderboard());
      return;
    }

    try {
      final data = await client.fetchLeaderboard();
      _syncError = null;
      ref.read(leaderboardSyncErrorProvider.notifier).clear();
      state = AsyncData(data);
    } catch (err) {
      _syncError = err;
      ref.read(leaderboardSyncErrorProvider.notifier).setError(err);
      if (state.hasValue) {
        state = AsyncData(state.value!);
      } else {
        state = AsyncError(err, StackTrace.current);
      }
    }
  }
}

final leaderboardNotifierProvider =
    AsyncNotifierProvider.autoDispose<LeaderboardNotifier, LeaderboardData>(() {
  return LeaderboardNotifier();
});
