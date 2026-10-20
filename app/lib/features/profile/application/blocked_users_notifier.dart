import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/blocked_users_api_client.dart';
import '../domain/blocked_user_model.dart';

class BlockedUsersNotifier extends AsyncNotifier<List<BlockedUser>> {
  @override
  Future<List<BlockedUser>> build() async {
    final client = ref.watch(blockedUsersApiClientProvider);
    return client.getBlockedUsers();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(blockedUsersApiClientProvider);
      return client.getBlockedUsers();
    });
  }

  Future<bool> unblock(String id) async {
    final client = ref.read(blockedUsersApiClientProvider);
    final success = await client.unblockUser(id);
    if (success) {
      final current = state.value ?? [];
      state = AsyncData(current.where((u) => u.id != id).toList());
      return true;
    }
    return false;
  }
}

final blockedUsersProvider =
    AsyncNotifierProvider.autoDispose<BlockedUsersNotifier, List<BlockedUser>>(() {
  return BlockedUsersNotifier();
});
