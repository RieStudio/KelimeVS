import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../../auth/data/auth_repository.dart';
import '../data/public_profile_api_client.dart';
import '../domain/public_profile_model.dart';
import 'blocked_users_notifier.dart';

final publicProfileApiClientProvider =
    Provider<PublicProfileApiClient>((ref) {
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpPublicProfileApiClient(onAccountDeleted: onDeleted);
});

final publicProfileProvider =
    FutureProvider.family<PublicProfile, String>((ref, uid) async {
  final timer = Timer(const Duration(seconds: 60), () {
    ref.invalidateSelf();
  });
  ref.onDispose(() => timer.cancel());

  final client = ref.watch(publicProfileApiClientProvider);
  return client.getPublicProfile(uid);
});

class PublicProfileService {
  final Ref _ref;
  const PublicProfileService(this._ref);

  Future<String> blockUser(String uid) async {
    final client = _ref.read(publicProfileApiClientProvider);
    final blockId = await client.blockUser(uid);
    _ref.invalidate(publicProfileProvider(uid));
    _ref.invalidate(blockedUsersProvider);
    return blockId;
  }

  Future<void> unblockUser(String uid) async {
    final client = _ref.read(publicProfileApiClientProvider);
    await client.unblockUser(uid);
    _ref.invalidate(publicProfileProvider(uid));
    _ref.invalidate(blockedUsersProvider);
  }

  Future<String> reportUser(String uid, String reason) async {
    final client = _ref.read(publicProfileApiClientProvider);
    return client.reportUser(uid, reason);
  }
}

final publicProfileServiceProvider = Provider<PublicProfileService>((ref) {
  return PublicProfileService(ref);
});

final currentUserIdProvider = Provider<String?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.currentUser?.uid;
});

final isCurrentUserProvider = Provider.family<bool, String?>((ref, uid) {
  if (uid == null || uid.isEmpty) return false;
  final currentUid = ref.watch(currentUserIdProvider);
  return currentUid != null && currentUid == uid;
});
