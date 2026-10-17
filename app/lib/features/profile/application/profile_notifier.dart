import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';

class ProfileState {
  final String? nickname;
  final bool isLoaded;

  const ProfileState({
    this.nickname,
    this.isLoaded = false,
  });

  bool get hasNickname => nickname != null && nickname!.trim().isNotEmpty;

  ProfileState copyWith({
    String? nickname,
    bool? isLoaded,
  }) {
    return ProfileState(
      nickname: nickname ?? this.nickname,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const LocalProfileRepository();
});

class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    _loadNickname();
    return const ProfileState(isLoaded: false);
  }

  Future<void> _loadNickname() async {
    final repo = ref.read(profileRepositoryProvider);
    final nick = await repo.getNickname();
    state = ProfileState(nickname: nick, isLoaded: true);
  }

  Future<void> setNickname(String newNickname) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.setNickname(newNickname);
    state = ProfileState(nickname: newNickname.trim(), isLoaded: true);
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(() {
  return ProfileNotifier();
});
