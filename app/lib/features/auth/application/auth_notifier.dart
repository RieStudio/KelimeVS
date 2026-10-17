import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/application/match_history_provider.dart';
import '../../profile/application/profile_notifier.dart';
import '../data/auth_repository.dart';
import '../domain/auth_link_result.dart';

class AuthUiState {
  final bool isGoogleLinked;
  final String? linkedEmail;
  final bool isLoading;
  final String? errorMessage;

  const AuthUiState({
    required this.isGoogleLinked,
    this.linkedEmail,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthUiState copyWith({
    bool? isGoogleLinked,
    String? linkedEmail,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthUiState(
      isGoogleLinked: isGoogleLinked ?? this.isGoogleLinked,
      linkedEmail: linkedEmail ?? this.linkedEmail,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthUiState> {
  StreamSubscription<User?>? _sub;

  @override
  AuthUiState build() {
    final repo = ref.watch(authRepositoryProvider);
    _sub?.cancel();
    _sub = repo.authStateChanges().listen((_) {
      _refresh();
    });

    ref.onDispose(() {
      _sub?.cancel();
    });

    return AuthUiState(
      isGoogleLinked: repo.isGoogleLinked,
      linkedEmail: repo.linkedEmail,
    );
  }

  void _refresh() {
    final repo = ref.read(authRepositoryProvider);
    state = state.copyWith(
      isGoogleLinked: repo.isGoogleLinked,
      linkedEmail: repo.linkedEmail,
    );
  }

  Future<AuthLinkResult> linkGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.linkWithGoogle();

    if (result is AuthLinkSuccess) {
      state = state.copyWith(
        isLoading: false,
        isGoogleLinked: true,
        linkedEmail: result.email ?? repo.linkedEmail,
      );
    } else if (result is AuthLinkError) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.message,
      );
    } else {
      state = state.copyWith(isLoading: false);
    }

    return result;
  }

  Future<void> resolveConflict(AuthCredential credential) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.signInWithConflictCredential(credential);

      // Yerel maç geçmişi ve takma adı sıfırla
      await ref.read(matchHistoryRepositoryProvider).clear();
      ref.invalidate(matchHistoryProvider);
      await ref.read(profileProvider.notifier).clearNickname();

      _refresh();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.signOutAndResetToAnonymous();

      // Yerel maç geçmişi ve takma adı sıfırla
      await ref.read(matchHistoryRepositoryProvider).clear();
      ref.invalidate(matchHistoryProvider);
      await ref.read(profileProvider.notifier).clearNickname();

      _refresh();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthUiState>(() {
  return AuthNotifier();
});

