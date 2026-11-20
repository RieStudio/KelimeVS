import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/app_pressable.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/application/store_notifier.dart';
import 'package:app/features/store/data/store_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/widgets/energy_tab_view.dart';

class _MockStoreNotifier extends StoreNotifier {
  @override
  StoreState build() => const StoreState(isLoading: false);

  @override
  Future<StorePurchaseEnergyResult> purchaseEnergy(String packId) async {
    return const StorePurchaseEnergySuccess(
      coins: 80,
      energy: 3,
      max: 5,
      nextEnergyAtMs: null,
      serverNowMs: 0,
      pack: 'one',
    );
  }
}

void main() {
  group('EnergyTabView Widget Tests', () {
    testWidgets('3/5 enerji durumunu, hücreleri ve canlı mm:ss sayacını gösterir, sabit yenilenme açıklamasını göstermez',
        (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // 14 dakika 25 saniye sonrası
      final nextAt = now + (14 * 60 + 25) * 1000;

      final energy = EnergyState(
        enabled: true,
        current: 3,
        max: 5,
        nextEnergyAtMs: nextAt,
        packs: const [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
                serverNowMs: now,
              ),
            ),
          ),
        ),
      );

      expect(find.text('3 / 5'), findsOneWidget);
      // mm:ss formatında (14:25) geri sayım metni aranır
      expect(find.textContaining('14:25'), findsOneWidget);

      // Sabit yenilenme cümlesi eksik enerjide de gösterilmemelidir
      expect(find.textContaining('Her 20 dakikada 1 enerji yenilenir'), findsNothing);

      // Paket kartları
      expect(find.text('+1 Enerji'), findsOneWidget);
      expect(find.text('Tam Doldur'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('tam enerji (5/5) durumunda "Tüm enerjin doldu" ve "Enerjin dolu" yazar, sabit yenilenme açıklamasını göstermez',
        (tester) async {
      final energy = const EnergyState(
        enabled: true,
        current: 5,
        max: 5,
        nextEnergyAtMs: null,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text(AppStrings.energyFull), findsOneWidget);
      expect(find.text(AppStrings.energyFullButton), findsNWidgets(2));
      expect(find.textContaining('Her 20 dakikada 1 enerji yenilenir'), findsNothing);
    });

    testWidgets('yeterli jeton varken +1 Enerji ve Tam Doldur butonlarında basma efekti (2 px kayma ve gölge kalkması) çalışır, bırakınca eski haline döner',
        (tester) async {
      const energy = EnergyState(
        enabled: true,
        current: 2,
        max: 5,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeNotifierProvider.overrideWith(() => _MockStoreNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      final buyOneFinder = find.byKey(const ValueKey('buy_energy_pack_one'));
      final buyFullFinder = find.byKey(const ValueKey('buy_energy_pack_full'));
      expect(buyOneFinder, findsOneWidget);
      expect(buyFullFinder, findsOneWidget);

      // 1. "+1 Enerji" Butonu Basma Efekti
      final buyOneContainer = find.descendant(
        of: buyOneFinder,
        matching: find.byType(Container),
      ).first;

      final initialOneTop = tester.getTopLeft(buyOneContainer).dy;
      var oneDec =
          tester.widget<Container>(buyOneContainer).decoration as BoxDecoration;
      expect(oneDec.boxShadow, isNotEmpty);
      expect(oneDec.boxShadow!.first.offset, const Offset(0, 2));

      var gesture = await tester.startGesture(tester.getCenter(buyOneFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyOneContainer).dy,
          closeTo(initialOneTop + 2.0, 0.01));
      oneDec =
          tester.widget<Container>(buyOneContainer).decoration as BoxDecoration;
      expect(oneDec.boxShadow, isNull);

      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyOneContainer).dy, closeTo(initialOneTop, 0.01));
      oneDec =
          tester.widget<Container>(buyOneContainer).decoration as BoxDecoration;
      expect(oneDec.boxShadow, isNotEmpty);

      // 2. "Tam Doldur" Butonu Basma Efekti
      final buyFullContainer = find.descendant(
        of: buyFullFinder,
        matching: find.byType(Container),
      ).first;

      final initialFullTop = tester.getTopLeft(buyFullContainer).dy;
      var fullDec =
          tester.widget<Container>(buyFullContainer).decoration as BoxDecoration;
      expect(fullDec.boxShadow, isNotEmpty);
      expect(fullDec.boxShadow!.first.offset, const Offset(0, 2));

      gesture = await tester.startGesture(tester.getCenter(buyFullFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyFullContainer).dy,
          closeTo(initialFullTop + 2.0, 0.01));
      fullDec =
          tester.widget<Container>(buyFullContainer).decoration as BoxDecoration;
      expect(fullDec.boxShadow, isNull);

      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyFullContainer).dy, closeTo(initialFullTop, 0.01));
      fullDec =
          tester.widget<Container>(buyFullContainer).decoration as BoxDecoration;
      expect(fullDec.boxShadow, isNotEmpty);
    });

    testWidgets('yetersiz jeton durumunda basma efekti çalışmaz ancak tıklanınca yetersiz jeton uyarısı verilir',
        (tester) async {
      const energy = EnergyState(
        enabled: true,
        current: 2,
        max: 5,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 10, // 20'den az
              ),
            ),
          ),
        ),
      );

      final buyOneFinder = find.byKey(const ValueKey('buy_energy_pack_one'));
      final buyOneContainer = find.descendant(
        of: buyOneFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(buyOneContainer).dy;
      final dec =
          tester.widget<Container>(buyOneContainer).decoration as BoxDecoration;
      // Yetersiz jetonda başlangıçta da gölge yoktur (soluk/pasif görünüm)
      expect(dec.boxShadow, isNull);

      // Dokunulduğunda basma hareketi oluşmaz
      final gesture = await tester.startGesture(tester.getCenter(buyOneFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyOneContainer).dy, closeTo(initialTop, 0.01));

      // Bırakılınca yetersiz jeton SnackBar'ı görünür
      await gesture.up();
      await tester.pump();

      expect(find.text(AppStrings.insufficientCoins), findsOneWidget);
    });

    testWidgets('enerji tam dolu iken basma efekti çalışmaz ve tıklanınca "enerjin dolu" uyarısı verilir',
        (tester) async {
      const energy = EnergyState(
        enabled: true,
        current: 5,
        max: 5,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeNotifierProvider.overrideWith(() => _MockStoreNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      final buyOneFinder = find.byKey(const ValueKey('buy_energy_pack_one'));
      final buyOneContainer = find.descendant(
        of: buyOneFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(buyOneContainer).dy;
      final dec =
          tester.widget<Container>(buyOneContainer).decoration as BoxDecoration;
      expect(dec.boxShadow, isNull);

      final gesture = await tester.startGesture(tester.getCenter(buyOneFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.getTopLeft(buyOneContainer).dy, closeTo(initialTop, 0.01));

      await gesture.up();
      await tester.pump();

      expect(find.text(AppStrings.energyAlreadyFull), findsOneWidget);
    });

    testWidgets('hızlı dokunuşta (tester.tap) enerji butonunda basma efekti ilk karelerde görünür ve en az 110 ms korunur',
        (tester) async {
      const energy = EnergyState(
        enabled: true,
        current: 2,
        max: 5,
        packs: [
          EnergyPack(id: 'one', cost: 20, energy: 1),
          EnergyPack(id: 'full', cost: 80, energy: 5),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeNotifierProvider.overrideWith(() => _MockStoreNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EnergyTabView(
                energy: energy,
                userCoins: 100,
              ),
            ),
          ),
        ),
      );

      final buyOneFinder = find.byKey(const ValueKey('buy_energy_pack_one'));
      final buyOneContainer = find.descendant(
        of: buyOneFinder,
        matching: find.byType(Container),
      ).first;

      final initialTop = tester.getTopLeft(buyOneContainer).dy;

      // Hızlı dokun (tap down ve up aynı anda)
      await tester.tap(buyOneFinder);
      await tester.pump();

      // Listener sayesinde hemen basılı duruma geçer
      final state = tester.state<AppPressableState>(buyOneFinder);
      expect(state.isPressed, isTrue);

      // 90 ms animasyon sonunda tam basılı kayma
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(buyOneContainer).dy, closeTo(initialTop + 2.0, 0.01));
      expect(state.isPressed, isTrue);

      // 110 ms minPressedDuration dolduğunda (toplam 120 ms) bırakılır
      await tester.pump(const Duration(milliseconds: 30));
      expect(state.isPressed, isFalse);

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(buyOneContainer).dy, closeTo(initialTop, 0.01));
    });
  });
}
