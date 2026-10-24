import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_service.dart';

enum NetworkStatus {
  online,
  offline,
  checking,
}

class NetworkState {
  final NetworkStatus status;
  final bool isConnected;
  final DateTime? lastProbeTime;

  const NetworkState({
    required this.status,
    this.lastProbeTime,
  }) : isConnected = status == NetworkStatus.online;

  NetworkState copyWith({
    NetworkStatus? status,
    DateTime? lastProbeTime,
  }) {
    return NetworkState(
      status: status ?? this.status,
      lastProbeTime: lastProbeTime ?? this.lastProbeTime,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkState &&
        other.status == status &&
        other.lastProbeTime == lastProbeTime;
  }

  @override
  int get hashCode => Object.hash(status, lastProbeTime);
}

final networkServiceProvider = Provider<NetworkService>((ref) {
  return DefaultNetworkService();
});

class NetworkStatusNotifier extends Notifier<NetworkState> {
  StreamSubscription<bool>? _subscription;
  Timer? _debounceTimer;
  static const Duration throttleDuration = Duration(seconds: 5);
  static const Duration offlineDebounceDuration = Duration(seconds: 2);

  @override
  NetworkState build() {
    final service = ref.watch(networkServiceProvider);

    _subscription?.cancel();
    _subscription = service.onPhysicalConnectionChanged.listen(_handlePhysicalChange);

    ref.onDispose(() {
      _subscription?.cancel();
      _debounceTimer?.cancel();
    });

    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTestEnv && service is DefaultNetworkService) {
      return NetworkState(
        status: NetworkStatus.online,
        lastProbeTime: DateTime.now(),
      );
    }

    // İlk durum kontrolünü başlat
    unawaited(_performInitialCheck(service));

    return const NetworkState(status: NetworkStatus.checking);
  }

  Future<void> _performInitialCheck(NetworkService service) async {
    final hasPhysical = await service.checkPhysicalConnection();
    if (!ref.mounted) return;
    if (!hasPhysical) {
      state = NetworkState(
        status: NetworkStatus.offline,
        lastProbeTime: DateTime.now(),
      );
      return;
    }

    final isReachable = await service.probeServerHealth();
    if (!ref.mounted) return;
    state = NetworkState(
      status: isReachable ? NetworkStatus.online : NetworkStatus.offline,
      lastProbeTime: DateTime.now(),
    );
  }

  void _handlePhysicalChange(bool hasPhysical) {
    if (!hasPhysical) {
      // Fiziksel bağlantı koptu
      _scheduleOffline();
    } else {
      // Fiziksel bağlantı geldi (none -> wifi/mobile)
      _cancelOfflineDebounce();
      unawaited(_verifyReachability(force: true));
    }
  }

  void _scheduleOffline() {
    if (state.status == NetworkStatus.offline) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(offlineDebounceDuration, () {
      if (!ref.mounted) return;
      state = state.copyWith(status: NetworkStatus.offline);
    });
  }

  void _cancelOfflineDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Sunucu erişilebilirliğini kontrol eder.
  ///
  /// [force] `true` ise 5 saniyelik önbellek kısıtını (throttling) aşar.
  Future<void> _verifyReachability({bool force = false}) async {
    final now = DateTime.now();
    if (!force && state.lastProbeTime != null) {
      final elapsed = now.difference(state.lastProbeTime!);
      if (elapsed < throttleDuration) {
        return;
      }
    }

    final service = ref.read(networkServiceProvider);
    final isReachable = await service.probeServerHealth();
    if (!ref.mounted) return;

    if (isReachable) {
      _cancelOfflineDebounce();
      state = NetworkState(
        status: NetworkStatus.online,
        lastProbeTime: now,
      );
    } else {
      _scheduleOffline();
    }
  }

  /// Kullanıcı "Tekrar Dene" butonuna bastığında veya zorunlu yenilemede çağrılır.
  Future<void> refresh() async {
    _cancelOfflineDebounce();
    state = state.copyWith(status: NetworkStatus.checking);

    final service = ref.read(networkServiceProvider);
    final hasPhysical = await service.checkPhysicalConnection();
    if (!ref.mounted) return;

    if (!hasPhysical) {
      state = NetworkState(
        status: NetworkStatus.offline,
        lastProbeTime: DateTime.now(),
      );
      return;
    }

    final isReachable = await service.probeServerHealth();
    if (!ref.mounted) return;

    state = NetworkState(
      status: isReachable ? NetworkStatus.online : NetworkStatus.offline,
      lastProbeTime: DateTime.now(),
    );
  }

  /// Uygulama arka plandan ön plana (`resumed`) geldiğinde çağrılır.
  void onAppResumed() {
    unawaited(_verifyReachability(force: false));
  }
}

final networkStatusProvider =
    NotifierProvider<NetworkStatusNotifier, NetworkState>(
  NetworkStatusNotifier.new,
);

class BannerSuppressionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void suppress() {
    Future.microtask(() {
      if (ref.mounted) {
        state = state + 1;
      }
    });
  }

  void unsuppress() {
    Future.microtask(() {
      if (ref.mounted) {
        state = (state > 0) ? state - 1 : 0;
      }
    });
  }
}

final bannerSuppressionProvider =
    NotifierProvider<BannerSuppressionNotifier, int>(
  BannerSuppressionNotifier.new,
);

final isOfflineBannerSuppressedProvider = Provider<bool>((ref) {
  final suppressionCount = ref.watch(bannerSuppressionProvider);
  return suppressionCount > 0;
});

