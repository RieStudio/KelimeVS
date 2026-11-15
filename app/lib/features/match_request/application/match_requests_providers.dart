import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../../online/data/auth_token_provider.dart';
import '../../online/data/websocket_connector.dart';
import '../../profile/application/profile_notifier.dart';
import '../data/user_inbox_client.dart';
import '../domain/match_request_models.dart';
import 'match_requests_notifier.dart';
import 'presence_controller.dart';

final userInboxConnectorProvider = Provider<WebSocketConnector>((ref) {
  return const IoWebSocketConnector();
});

final userInboxTokenProvider = Provider<AuthTokenProvider>((ref) {
  return const FirebaseAuthTokenProvider();
});

final userInboxClientProvider = Provider<UserInboxClient>((ref) {
  final connector = ref.watch(userInboxConnectorProvider);
  final tokenProvider = ref.watch(userInboxTokenProvider);
  final onDeleted = ref.watch(accountDeletedHandlerProvider);

  final client = UserInboxClient(
    connector: connector,
    tokenProvider: tokenProvider,
    onAccountDeleted: onDeleted,
    getCurrentPresenceState: () {
      return ref.read(presenceControllerProvider).toWireString();
    },
  );

  ref.onDispose(() {
    unawaited(client.dispose());
  });

  return client;
});

/// Uygulama yaşam döngüsü ile /ws/user WebSocket bağlantısını koordine eden sınıf.
class UserInboxLifecycleCoordinator with WidgetsBindingObserver {
  final Ref _ref;
  bool _isForeground = true;
  bool _isObserverRegistered = false;

  UserInboxLifecycleCoordinator(this._ref);

  void start() {
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }

    _ref.listen<bool>(
      authNotifierProvider.select((s) => s.isAuthenticated),
      (previous, current) {
        if (!current) {
          unawaited(onSignOut());
        } else {
          unawaited(evaluateConnection());
        }
      },
    );

    _ref.listen<bool>(
      profileProvider.select((p) => p.hasNickname),
      (previous, current) {
        unawaited(evaluateConnection());
      },
    );

    unawaited(evaluateConnection());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      unawaited(evaluateConnection());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      unawaited(disconnectDueToBackground());
    }
  }

  Future<void> evaluateConnection() async {
    final isAuthenticated = _ref.read(authNotifierProvider).isAuthenticated;
    final hasNickname = _ref.read(profileProvider).hasNickname;

    final shouldConnect = isAuthenticated && hasNickname && _isForeground;

    final client = _ref.read(userInboxClientProvider);
    final notifier = _ref.read(matchRequestsProvider.notifier);
    final presence = _ref.read(presenceControllerProvider.notifier);

    notifier.attachClient(client);
    presence.attachClient(client);

    if (shouldConnect) {
      if (!client.isConnected && !client.isReconnecting) {
        await client.connect();
      }
    } else {
      if (client.isConnected) {
        await client.close(code: 1000, reason: 'lifecycle_not_active');
      }
    }
  }

  Future<void> disconnectDueToBackground() async {
    _ref.read(matchRequestsProvider.notifier).clearLocalRequests();
    final client = _ref.read(userInboxClientProvider);
    if (client.isConnected) {
      await client.close(code: 1000, reason: 'app_backgrounded');
    }
  }

  Future<void> onSignOut() async {
    _ref.read(presenceControllerProvider.notifier).forceReset();
    _ref.read(matchRequestsProvider.notifier).reset();
    final client = _ref.read(userInboxClientProvider);
    if (client.isConnected) {
      await client.close(code: 1000, reason: 'sign_out');
    }
  }

  void dispose() {
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }
  }
}

final userInboxLifecycleCoordinatorProvider =
    Provider<UserInboxLifecycleCoordinator>((ref) {
  final coordinator = UserInboxLifecycleCoordinator(ref);
  ref.onDispose(() {
    coordinator.dispose();
  });
  return coordinator;
});

/// Eşleşme tamamlandı akışı (Global UI navigasyonu için).
final matchedEventsProvider = StreamProvider<MatchedEvent>((ref) {
  return ref.watch(matchRequestsProvider.notifier).matchedEvents;
});

/// Maç isteği geri bildirim (toast) durumu.
class MatchRequestToastState {
  final String message;
  final bool isDanger;
  final int timestamp;

  const MatchRequestToastState({
    required this.message,
    this.isDanger = false,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRequestToastState &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          isDanger == other.isDanger &&
          timestamp == other.timestamp;

  @override
  int get hashCode => message.hashCode ^ isDanger.hashCode ^ timestamp.hashCode;
}

/// Maç isteği geri bildirimlerini (toast) yöneten Notifier.
class MatchRequestToastNotifier extends Notifier<MatchRequestToastState?> {
  @override
  MatchRequestToastState? build() => null;

  void showToast(String message, {bool isDanger = false}) {
    state = MatchRequestToastState(
      message: message,
      isDanger: isDanger,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void clear() {
    state = null;
  }
}

final matchRequestToastProvider =
    NotifierProvider<MatchRequestToastNotifier, MatchRequestToastState?>(
  MatchRequestToastNotifier.new,
);

/// MatchEndView gibi satır içi ekranların, global banner/çip/toast gösterilmesini
/// bastırmak için kaydettiği rakip UID'sini yöneten Notifier.
class InlineHandledRematchNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setUid(String? uid) {
    if (ref.mounted) {
      state = uid;
    }
  }

  void clear() {
    try {
      if (ref.mounted) {
        state = null;
      }
    } catch (_) {}
  }
}

/// MatchEndView gibi satır içi ekranların, global banner/çip/toast gösterilmesini
/// bastırmak için kaydettiği rakip UID'si.
/// Null ise hiçbir rakip satır içi işlenmiyor demektir.
final inlineHandledRematchOpponentUidProvider =
    NotifierProvider<InlineHandledRematchNotifier, String?>(
  InlineHandledRematchNotifier.new,
);

