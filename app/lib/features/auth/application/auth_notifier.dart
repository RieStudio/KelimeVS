import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../game/application/match_history_provider.dart';
import '../../game/application/objection_provider.dart';
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
  bool _isHandlingDeletedElsewhere = false;

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

      // Yerel maç geçmişi, itirazlar ve takma adı sıfırla
      await ref.read(matchHistoryRepositoryProvider).clear();
      ref.invalidate(matchHistoryProvider);
      await ref.read(objectionRepositoryProvider).clear();
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

      // Yerel maç geçmişi, itirazlar ve takma adı sıfırla
      await ref.read(matchHistoryRepositoryProvider).clear();
      ref.invalidate(matchHistoryProvider);
      await ref.read(objectionRepositoryProvider).clear();
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

  /// Kullanıcının hesabını ve tüm verilerini siler.
  /// 1. Google bağlıysa önce Google ile yeniden doğrular (re-auth).
  ///    Kullanıcı re-auth promptunu iptal ederse hiçbir veri silinmeden işlem durdurulur.
  /// 2. Sunucuya DELETE /me isteği atılır. Ağ hatası alınırsa işlem durdurulur.
  /// 3. Firebase kullanıcısı silinir (anonim hesapta requires-recent-login hatası yoksayılır).
  /// 4. Yerel depolar (maç geçmişi, itirazlar, profil) temizlenir.
  /// 5. Google ve Firebase oturumu kapatılır, yeni anonim hesaba geçilir.
  Future<bool> deleteAccount() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final repo = ref.read(authRepositoryProvider);

    // 1. Google bağlıysa Re-auth yap
    if (repo.isGoogleLinked) {
      final reauthResult = await repo.reauthenticateGoogle();
      if (reauthResult is AuthLinkCanceled) {
        state = state.copyWith(isLoading: false);
        return false;
      }
      if (reauthResult is AuthLinkError) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: reauthResult.message,
        );
        return false;
      }
    }

    // 2. Sunucudaki profil ve liderlik verilerini sil (DELETE /me)
    final apiClient = ref.read(profileApiClientProvider);
    try {
      await apiClient.deleteProfile();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AppStrings.deleteAccountNetworkError,
      );
      return false;
    }

    // 3. Firebase kullanıcısını silmeyi dene
    try {
      await repo.deleteFirebaseUser();
    } catch (_) {
      // Hata olsa bile sunucu verisi silindiği için temizlik adımlarına devam et
    }

    // 4. Yerel depoları tamamen temizle
    await ref.read(matchHistoryRepositoryProvider).clear();
    ref.invalidate(matchHistoryProvider);
    await ref.read(objectionRepositoryProvider).clear();
    await ref.read(profileProvider.notifier).clearNickname();

    // 5. Oturumları sıfırla ve yeni anonim hesaba geç
    await repo.completeAccountDeletionAndReset();

    _refresh();
    state = state.copyWith(isLoading: false);
    return true;
  }

  /// Sunucudan 410 (account_deleted) veya WebSocket 4001 geldiğinde sessizce çağrılır.
  Future<void> handleAccountDeletedElsewhere() async {
    if (_isHandlingDeletedElsewhere) return;
    _isHandlingDeletedElsewhere = true;

    try {
      final repo = ref.read(authRepositoryProvider);

      // Yerel depoları temizle
      await ref.read(matchHistoryRepositoryProvider).clear();
      ref.invalidate(matchHistoryProvider);
      await ref.read(objectionRepositoryProvider).clear();
      await ref.read(profileProvider.notifier).clearNickname();

      // Firebase kullanıcısını silmeyi dene, oturumu kapat, yeni anonim hesap aç
      await repo.completeAccountDeletionAndReset();

      _refresh();
    } finally {
      _isHandlingDeletedElsewhere = false;
    }
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthUiState>(() {
  return AuthNotifier();
});

final accountDeletedHandlerProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(authNotifierProvider.notifier).handleAccountDeletedElsewhere();
  };
});
