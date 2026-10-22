import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/data/store_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/store_screen.dart';

class MockStoreApiClient implements StoreApiClient {
  final EnergyState? energyState;
  final List<StoreItem> items;

  MockStoreApiClient({
    this.energyState,
    this.items = const [],
  });

  @override
  Future<StoreState?> getStore() async {
    return StoreState(
      coins: 100,
      equippedFrame: 'classic',
      items: items,
      energy: energyState,
      serverNowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<StorePurchaseResult> purchaseItem(String itemId) async {
    return StorePurchaseSuccess(coins: 50, itemId: itemId);
  }

  @override
  Future<StoreEquipResult> equipFrame(String frameId) async {
    return StoreEquipSuccess(frameId);
  }

  @override
  Future<StorePurchaseEnergyResult> purchaseEnergy(String pack) async {
    return StorePurchaseEnergySuccess(
      coins: 80,
      energy: 4,
      max: 5,
      nextEnergyAtMs: null,
      serverNowMs: DateTime.now().millisecondsSinceEpoch,
      pack: pack,
    );
  }
}

void main() {
  group('StoreScreen Tabs Tests', () {
    testWidgets('enerji kapalıyken Enerji sekmesi gösterilmez, Jeton ve Çerçeve gösterilir',
        (tester) async {
      final mockClient = MockStoreApiClient(
        energyState: const EnergyState(
          enabled: false,
          current: 5,
          max: 5,
          packs: [],
        ),
        items: const [
          StoreItem(id: 'classic', name: 'Klasik', price: 0, owned: true, isEquipped: true),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeApiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: StoreScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jeton'), findsOneWidget);
      expect(find.text('Enerji'), findsNothing);
      expect(find.text('Çerçeve'), findsOneWidget);

      // Varsayılan açık sekme Çerçeve'dir
      expect(find.text('AVATAR ÇERÇEVELERİ'), findsOneWidget);
    });

    testWidgets('enerji açıkken Jeton · Enerji · Çerçeve sırasıyla gösterilir ve sekmeler arası geçiş yapılır',
        (tester) async {
      final mockClient = MockStoreApiClient(
        energyState: const EnergyState(
          enabled: true,
          current: 3,
          max: 5,
          packs: [
            EnergyPack(id: 'one', cost: 20, energy: 1),
          ],
        ),
        items: const [
          StoreItem(id: 'classic', name: 'Klasik', price: 0, owned: true, isEquipped: true),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeApiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: StoreScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jeton'), findsOneWidget);
      expect(find.text('Enerji'), findsOneWidget);
      expect(find.text('Çerçeve'), findsOneWidget);

      // 1. Varsayılan sekme Çerçeve
      expect(find.text('AVATAR ÇERÇEVELERİ'), findsOneWidget);

      // 2. Enerji sekmesine geçiş
      await tester.tap(find.text('Enerji'));
      await tester.pumpAndSettle();

      expect(find.text('3 / 5'), findsOneWidget);
      expect(find.text('+1 Enerji'), findsOneWidget);

      // 3. Jeton sekmesine geçiş
      await tester.tap(find.text('Jeton'));
      await tester.pumpAndSettle();

      expect(find.text('Jeton paketleri çok yakında'), findsOneWidget);
    });
  });
}

