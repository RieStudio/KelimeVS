import '../../auth/application/auth_notifier.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/data/auth_token_provider.dart';
import '../data/profile_api_client.dart';
import '../data/profile_repository.dart';

class ProfileState {
  final String? nickname;
  final int coins;
  final bool isLoaded;
  final bool isSyncing;
  final String? syncError;
  final String equippedFrame;

  const ProfileState({
    this.nickname,
    this.coins = 100,
    this.isLoaded = false,
    this.isSyncing = false,
    this.syncError,
    this.equippedFrame = 'classic',
  });

  bool get hasNickname => nickname != null && nickname!.trim().isNotEmpty;

  ProfileState copyWith({
    String? nickname,
    int? coins,
    bool? isLoaded,
    bool? isSyncing,
    String? syncError,
    String? equippedFrame,
    bool clearSyncError = false,
  }) {
    return ProfileState(
      nickname: nickname ?? this.nickname,
      coins: coins ?? this.coins,
      isLoaded: isLoaded ?? this.isLoaded,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      equippedFrame: equippedFrame ?? this.equippedFrame,
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const LocalProfileRepository();
});

final authTokenProviderForProfile = Provider<AuthTokenProvider>((ref) {
  return const FirebaseAuthTokenProvider();
});

final profileApiClientProvider = Provider<ProfileApiClient>((ref) {
  final authProvider = ref.watch(authTokenProviderForProfile);
  final onDeleted = ref.watch(accountDeletedHandlerProvider);
  return HttpProfileApiClient(
    authTokenProvider: authProvider,
    onAccountDeleted: onDeleted,
  );
});

class ProfileNotifier extends Notifier<ProfileState> {
  bool _isSyncing = false;

  @override
  ProfileState build() {
    _loadProfile();
    return const ProfileState(isLoaded: false);
  }

  Future<void> _loadProfile() async {
    final repo = ref.read(profileRepositoryProvider);
    final nick = await repo.getNickname();
    final coins = await repo.getCoins(defaultCoins: 100);
    final frame = await repo.getEquippedFrame(defaultFrame: 'classic');

    state = state.copyWith(
      nickname: state.nickname ?? nick,
      coins: state.coins == 100 ? coins : state.coins,
      equippedFrame: frame,
      isLoaded: true,
    );

    // Arka planda sunucu senkronizasyonu başlat
    unawaited(syncWithServer());
  }

  /// Sunucuyla profili ve takma adı senkronlar.
  Future<void> syncWithServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    state = state.copyWith(isSyncing: true);

    try {
      final repo = ref.read(profileRepositoryProvider);
      final apiClient = ref.read(profileApiClientProvider);

      final remote = await apiClient.getProfile();
      if (remote != null) {
        // 1. Jeton bakiyesini senkronla
        await repo.setCoins(remote.coins);
        await repo.setEquippedFrame(remote.equippedFrame);
        state = state.copyWith(coins: remote.coins, equippedFrame: remote.equippedFrame);

        // 2. Takma ad senkronizasyonu (Kural 2)
        final localNick = state.nickname ?? await repo.getNickname();
        if (remote.nickname != null && remote.nickname!.trim().isNotEmpty) {
          // Bulutta ad varsa bulut esas alınır, yerel güncellenir
          final cloudNick = remote.nickname!.trim();
          await repo.setNickname(cloudNick);
          await repo.setNicknameSyncPending(false);
          state = state.copyWith(nickname: cloudNick);
        } else if (localNick != null && localNick.trim().isNotEmpty) {
          // Bulutta ad yok ama yerelde geçerli takma ad varsa (Mevcut yerel takma ad göçü)
          final uploadRes = await apiClient.updateNickname(localNick.trim());
          if (uploadRes is ProfileUpdateSuccess) {
            await repo.setNickname(uploadRes.nickname);
            await repo.setNicknameSyncPending(false);
            state = state.copyWith(nickname: uploadRes.nickname);
          } else if (uploadRes is ProfileUpdateNetworkError) {
            await repo.setNicknameSyncPending(true);
          } else if (uploadRes is ProfileUpdateInvalidNickname) {
            await repo.setNicknameSyncPending(false);
            state = state.copyWith(syncError: uploadRes.message);
          }
        }
      } else {
        // Çevrimdışı veya sunucuya ulaşılamadı; bekleyen ad varsa işaretli kalsın
        final pending = await repo.isNicknameSyncPending();
        if (pending && state.hasNickname) {
          // Gelecek bağlantıda tekrar denenecek
        }
      }
    } finally {
      _isSyncing = false;
      state = state.copyWith(isSyncing: false);
    }
  }

  /// Kural 3: Çevrimdışı dayanıklılık.
  /// Ağ hatasında yerel adı kaydeder, 'buluta gönderilmedi' işareti tutar.
  /// 400 geçersiz ad dönerse hata fırlatır ve işareti temizler.
  Future<void> setNickname(String newNickname) async {
    final trimmed = newNickname.trim();
    final repo = ref.read(profileRepositoryProvider);
    final apiClient = ref.read(profileApiClientProvider);

    // Yerelde hemen kaydet (oyun engellenmesin)
    await repo.setNickname(trimmed);
    state = state.copyWith(nickname: trimmed, clearSyncError: true);

    final res = await apiClient.updateNickname(trimmed);
    if (res is ProfileUpdateSuccess) {
      await repo.setNickname(res.nickname);
      await repo.setNicknameSyncPending(false);
      state = state.copyWith(nickname: res.nickname);
    } else if (res is ProfileUpdateNetworkError) {
      // Ağ hatası: yerelde geçerli kaldı, bekleyen işareti koy
      await repo.setNicknameSyncPending(true);
    } else if (res is ProfileUpdateInvalidNickname) {
      // Sunucu "geçersiz ad" (400) derse işareti temizle ve kullanıcıya bildir
      await repo.setNicknameSyncPending(false);
      state = state.copyWith(syncError: res.message);
      throw Exception(res.message);
    }
  }

  /// Uygulama açılışında veya resume durumunda bekleyen ad yüklemesini dener.
  Future<void> retryPendingNicknameSync() async {
    final repo = ref.read(profileRepositoryProvider);
    final isPending = await repo.isNicknameSyncPending();
    if (!isPending || !state.hasNickname) return;

    final apiClient = ref.read(profileApiClientProvider);
    final res = await apiClient.updateNickname(state.nickname!);

    if (res is ProfileUpdateSuccess) {
      await repo.setNickname(res.nickname);
      await repo.setNicknameSyncPending(false);
      state = state.copyWith(nickname: res.nickname);
    } else if (res is ProfileUpdateInvalidNickname) {
      await repo.setNicknameSyncPending(false);
      state = state.copyWith(syncError: res.message);
    }
  }

  /// Kural 5: Mutlak bakiye ile üzerine yazma (toplamayıp mutlak değeri atar).
  Future<void> updateCoins(int newTotal) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.setCoins(newTotal);
    state = state.copyWith(coins: newTotal);
  }

  /// Kuşanılan avatar çerçevesini yerelde ve durumda günceller.
  Future<void> setEquippedFrame(String frame) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.setEquippedFrame(frame);
    state = state.copyWith(equippedFrame: frame);
  }

  Future<void> clearNickname() async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.clear();
    state = const ProfileState(
      nickname: null,
      coins: 100,
      isLoaded: true,
    );
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(() {
  return ProfileNotifier();
});
