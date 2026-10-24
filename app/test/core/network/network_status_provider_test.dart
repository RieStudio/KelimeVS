import 'dart:async';

import 'package:app/core/network/network_service.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkService implements NetworkService {
  bool hasPhysical;
  bool isReachable;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  int probeCallCount = 0;

  FakeNetworkService({
    this.hasPhysical = true,
    this.isReachable = true,
  });

  @override
  Future<bool> checkPhysicalConnection() async => hasPhysical;

  @override
  Stream<bool> get onPhysicalConnectionChanged => _controller.stream;

  void emitPhysicalConnection(bool value) {
    hasPhysical = value;
    _controller.add(value);
  }

  @override
  Future<bool> probeServerHealth() async {
    probeCallCount++;
    return isReachable;
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('NetworkStatusNotifier Tests', () {
    late FakeNetworkService fakeService;

    setUp(() {
      fakeService = FakeNetworkService();
    });

    tearDown(() {
      fakeService.dispose();
    });

    test('1. Başlangıçta fiziksel ağ yoksa durum offline olur', () async {
      fakeService.hasPhysical = false;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      // Async initial check tamamlansın
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(networkStatusProvider).status, NetworkStatus.offline);
      expect(container.read(networkStatusProvider).isConnected, false);
      expect(fakeService.probeCallCount, 0); // Fiziksel yokken gereksiz probe atılmaz
    });

    test('2. Başlangıçta fiziksel ağ var ve sunucu erişilebilirse durum online olur', () async {
      fakeService.hasPhysical = true;
      fakeService.isReachable = true;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(networkStatusProvider).status, NetworkStatus.online);
      expect(container.read(networkStatusProvider).isConnected, true);
      expect(fakeService.probeCallCount, 1);
    });

    test('3. Başlangıçta fiziksel ağ var ama sunucu probe başarısız ise offline olur', () async {
      fakeService.hasPhysical = true;
      fakeService.isReachable = false;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(networkStatusProvider).status, NetworkStatus.offline);
      expect(container.read(networkStatusProvider).isConnected, false);
      expect(fakeService.probeCallCount, 1);
    });

    test('4. Çevrimiçiyken bağlantı kopunca 2 sn debounce çalışır; süre dolmadan dönerse offline olmaz', () async {
      fakeService.hasPhysical = true;
      fakeService.isReachable = true;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(networkStatusProvider).status, NetworkStatus.online);

      // Fiziksel bağlantı koptu sinyali
      fakeService.emitPhysicalConnection(false);
      await pumpEventQueue();

      // 2 sn dolmadığı için henüz online kalmalı (debouncing)
      expect(container.read(networkStatusProvider).status, NetworkStatus.online);

      // 100 ms sonra bağlantı geri geldi
      await Future<void>.delayed(const Duration(milliseconds: 100));
      fakeService.emitPhysicalConnection(true);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Durum offline'a hiç düşmeden online kaldı
      expect(container.read(networkStatusProvider).status, NetworkStatus.online);
    });

    test('5. Çevrimiçiyken bağlantı kopunca 2 sn debounce süresi dolunca offline olur', () async {
      fakeService.hasPhysical = true;
      fakeService.isReachable = true;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(networkStatusProvider).status, NetworkStatus.online);

      fakeService.emitPhysicalConnection(false);
      await pumpEventQueue();

      // 2.1 saniye bekle
      await Future<void>.delayed(const Duration(milliseconds: 2100));

      expect(container.read(networkStatusProvider).status, NetworkStatus.offline);
    });

    test('6. refresh() çağrısı throttling aşar ve durumu günceller', () async {
      fakeService.hasPhysical = true;
      fakeService.isReachable = false;

      final container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);
      container.listen(networkStatusProvider, (_, _) {});

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(networkStatusProvider).status, NetworkStatus.offline);
      expect(fakeService.probeCallCount, 1);

      // Tekrar Dene
      fakeService.isReachable = true;
      await container.read(networkStatusProvider.notifier).refresh();

      expect(container.read(networkStatusProvider).status, NetworkStatus.online);
      expect(fakeService.probeCallCount, 2);
    });

    test('7. bannerSuppressionProvider doğru sayaçla şerit bastırmasını yönetir', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isOfflineBannerSuppressedProvider), false);

      container.read(bannerSuppressionProvider.notifier).suppress();
      await pumpEventQueue();
      expect(container.read(isOfflineBannerSuppressedProvider), true);

      container.read(bannerSuppressionProvider.notifier).suppress();
      await pumpEventQueue();
      expect(container.read(isOfflineBannerSuppressedProvider), true);

      container.read(bannerSuppressionProvider.notifier).unsuppress();
      await pumpEventQueue();
      expect(container.read(isOfflineBannerSuppressedProvider), true);

      container.read(bannerSuppressionProvider.notifier).unsuppress();
      await pumpEventQueue();
      expect(container.read(isOfflineBannerSuppressedProvider), false);
    });
  });
}
