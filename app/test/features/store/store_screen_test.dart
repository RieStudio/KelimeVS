import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/player_avatar.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/store/data/store_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/store_screen.dart';
import 'package:app/features/store/presentation/widgets/purchase_bottom_sheet.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => const [];

  @override
  Future<void> clear() async {}
}

class FakeStoreApiClient implements StoreApiClient {
  int coins;
  String equippedFrame;
  final Set<String> ownedItems;
  bool shouldFailPurchase;
  bool shouldFailEquip;

  final List<String> equipHistory = [];
  StoreEquipResult? customEquipResult;

  FakeStoreApiClient({
    this.coins = 500,
    this.equippedFrame = 'classic',
    Set<String>? owned,
    this.shouldFailPurchase = false,
    this.shouldFailEquip = false,
    this.customEquipResult,
  }) : ownedItems = owned ?? {'classic'};

  @override
  Future<StoreState?> getStore() async {
    const catalog = [
      ('classic', 'Klasik', 0),
      ('mint', 'Nane', 100),
      ('sunset', 'Gün Batımı', 150),
      ('ocean', 'Okyanus', 150),
      ('gold', 'Altın', 300),
      ('neon', 'Neon', 300),
      ('rainbow', 'Gökkuşağı', 500),
      ('diamond', 'Elmas', 800),
    ];

    final items = catalog.map((c) {
      final isOwned = ownedItems.contains(c.$1);
      return StoreItem.fromJson({
        'id': c.$1,
        'name': c.$2,
        'cost': c.$3,
        'isOwned': isOwned,
        'isEquipped': equippedFrame == c.$1,
      });
    }).toList();

    return StoreState(
      coins: coins,
      equippedFrame: equippedFrame,
      items: items,
    );
  }

  @override
  Future<StorePurchaseResult> purchaseItem(String itemId) async {
    if (shouldFailPurchase) {
      return const StorePurchaseNotEnoughCoins();
    }
    final price = itemId == 'mint' ? 100 : 300;
    if (coins < price) {
      return const StorePurchaseNotEnoughCoins();
    }
    coins -= price;
    ownedItems.add(itemId);
    return StorePurchaseSuccess(coins: coins, itemId: itemId);
  }

  @override
  Future<StoreEquipResult> equipFrame(String frameId) async {
    equipHistory.add(frameId);
    if (customEquipResult != null) {
      return customEquipResult!;
    }
    if (shouldFailEquip) {
      return const StoreEquipNotOwned();
    }
    if (!ownedItems.contains(frameId)) {
      return const StoreEquipNotOwned();
    }
    equippedFrame = frameId;
    return StoreEquipSuccess(frameId);
  }

  @override
  Future<StorePurchaseEnergyResult> purchaseEnergy(String pack) async {
    return StorePurchaseEnergySuccess(
      coins: coins,
      energy: 5,
      max: 5,
      nextEnergyAtMs: null,
      serverNowMs: DateTime.now().millisecondsSinceEpoch,
      pack: pack,
    );
  }
}

class FakeProfileApiClient implements ProfileApiClient {
  @override
  Future<UserProfileModel?> getProfile() async => null;
  @override
  Future<ProfileUpdateResult> updateNickname(String nickname) async =>
      ProfileUpdateSuccess(nickname);
  @override
  Future<bool> deleteProfile() async => true;
}

class FakeProfileRepository implements ProfileRepository {
  String? _nickname = 'Deniz';
  int _coins = 500;
  String _equippedFrame = 'classic';
  bool _syncPending = false;

  @override
  Future<String?> getNickname() async => _nickname;
  @override
  Future<void> setNickname(String nickname) async => _nickname = nickname;
  @override
  Future<bool> hasNickname() async => _nickname != null && _nickname!.isNotEmpty;
  @override
  Future<int> getCoins({int defaultCoins = 100}) async => _coins;
  @override
  Future<void> setCoins(int coins) async => _coins = coins;
  @override
  Future<String> getEquippedFrame({String defaultFrame = 'classic'}) async =>
      _equippedFrame;
  @override
  Future<void> setEquippedFrame(String frame) async => _equippedFrame = frame;
  @override
  Future<bool> isNicknameSyncPending() async => _syncPending;
  @override
  Future<void> setNicknameSyncPending(bool pending) async =>
      _syncPending = pending;
  @override
  Future<UserStats> getStats({String? uid}) async => const UserStats();
  @override
  Future<void> setStats(String uid, UserStats stats) async {}
  @override
  Future<void> clear({String? uid}) async {}
}

Widget createStoreScreen({
  required StoreApiClient storeClient,
  ProfileRepository? profileRepo,
}) {
  final repo = profileRepo ?? FakeProfileRepository();
  return ProviderScope(
    overrides: [
      storeApiClientProvider.overrideWithValue(storeClient),
      profileApiClientProvider.overrideWithValue(FakeProfileApiClient()),
      profileRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(
      home: StoreScreen(),
    ),
  );
}

void main() {
  group('StoreScreen Tests', () {
    testWidgets('renders title, CoinPill and all catalog items',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeClient = FakeStoreApiClient(coins: 500);
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.storeTitle), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text(AppStrings.avatarFramesSection), findsOneWidget);

      // Verify some frame names
      expect(find.text(AppStrings.frameClassic), findsOneWidget);
      expect(find.text(AppStrings.frameMint), findsOneWidget);
      expect(find.text(AppStrings.frameSunset), findsOneWidget);

      // Klasik should show "Kuşanıldı"
      expect(find.text(AppStrings.equippedStatus), findsOneWidget);

      // Fiyat haplarında "0" görünmemeli, gerçek fiyatlar görünmeli
      expect(find.text('100'), findsOneWidget);
      expect(find.text('150'), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('tapping buy opens PurchaseBottomSheet and completes purchase',
        (tester) async {
      final fakeClient = FakeStoreApiClient(coins: 500);
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      // Find Mint card (100 coins)
      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      expect(mintCard, findsOneWidget);

      // Tap buy on Mint
      final buyButton = find.descendant(
        of: mintCard,
        matching: find.byKey(const ValueKey('buy_mint')),
      );
      expect(buyButton, findsOneWidget);
      await tester.tap(buyButton);
      await tester.pumpAndSettle();

      // PurchaseBottomSheet should be open
      expect(find.byType(PurchaseBottomSheet), findsOneWidget);
      expect(find.text('100 Jeton'), findsOneWidget);

      // Tap confirm button in sheet
      final confirmButton = find.text('${AppStrings.buyAction} (100 Jeton)');
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // Modal closed, coins deducted to 400, OTOMATİK KUŞANMA YOK: kuşanılan hala classic
      expect(find.byType(PurchaseBottomSheet), findsNothing);
      expect(fakeClient.coins, equals(400));
      expect(fakeClient.equippedFrame, equals('classic'));
      expect(find.text('400'), findsOneWidget);
      expect(find.text(AppStrings.framePurchasedSuccess), findsOneWidget);

      // Kart artık Kuşan durumuna geçer
      final equipButton = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipButton, findsOneWidget);
    });

    testWidgets(
        'satın alma sonrası otomatik kuşanma olmaz; ardından kuşanılınca mağaza, profil ve ana ekran tutarlıdır',
        (tester) async {
      final fakeClient = FakeStoreApiClient(coins: 500);
      final repo = FakeProfileRepository();

      final container = ProviderContainer(
        overrides: [
          storeApiClientProvider.overrideWithValue(fakeClient),
          profileApiClientProvider.overrideWithValue(FakeProfileApiClient()),
          profileRepositoryProvider.overrideWithValue(repo),
          matchHistoryRepositoryProvider
              .overrideWithValue(FakeMatchHistoryRepository()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: StoreScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      final classicCard = find.byKey(const ValueKey('store_frame_classic'));

      // 1. Mint satın al
      final buyButton = find.descendant(
        of: mintCard,
        matching: find.byKey(const ValueKey('buy_mint')),
      );
      await tester.tap(buyButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('${AppStrings.buyAction} (100 Jeton)'));
      await tester.pumpAndSettle();

      // Satın alma sonrası:
      // a. Bakiye 400'e indi
      expect(fakeClient.coins, equals(400));
      expect(container.read(profileProvider).coins, equals(400));
      // b. Otomatik kuşanma yok: Kuşanılan çerçeve HALA 'classic'
      expect(fakeClient.equippedFrame, equals('classic'));
      expect(container.read(profileProvider).equippedFrame, equals('classic'));
      expect(await repo.getEquippedFrame(), equals('classic'));
      // c. Mağazada Mint kartı 'Kuşan' butonuna geçti, Klasik kartı 'Kuşanıldı'
      final mintEquipButton = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(mintEquipButton, findsOneWidget);
      expect(
        find.descendant(
          of: classicCard,
          matching: find.text(AppStrings.equippedStatus),
        ),
        findsOneWidget,
      );

      // 2. Şimdi Mint'i kuşan
      await tester.tap(mintEquipButton);
      await tester.pumpAndSettle();

      // Kuşanma sonrası:
      // a. fakeClient'ta çerçeve artık 'mint'
      expect(fakeClient.equippedFrame, equals('mint'));
      // b. Profil state'inde çerçeve artık 'mint'
      expect(container.read(profileProvider).equippedFrame, equals('mint'));
      expect(await repo.getEquippedFrame(), equals('mint'));
      // c. Mağazada Mint kartı 'Kuşanıldı', Klasik kartı 'Kuşan'
      expect(
        find.descendant(
          of: mintCard,
          matching: find.text(AppStrings.equippedStatus),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: classicCard,
          matching: find.text(AppStrings.equipAction),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.frameEquippedSuccess), findsOneWidget);

      // 3. Ana ekranı render et ve avatarın Nane çerçevesini kullandığını doğrula
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ana ekrandaki avatar Nane çerçeveli olmalıdır
      final avatarFinder = find.byType(PlayerAvatar);
      expect(avatarFinder, findsOneWidget);
      final avatarWidget = tester.widget<PlayerAvatar>(avatarFinder);
      expect(avatarWidget.frame, equals('mint'));
      expect(avatarWidget.name, equals('Deniz'));
      expect(find.text('400'), findsOneWidget); // HomeScreen CoinPill bakiyesi de 400 olmalı
    });

    testWidgets('equipping an owned frame updates state and shows SnackBar',
        (tester) async {
      final fakeClient = FakeStoreApiClient(
        coins: 300,
        equippedFrame: 'classic',
        owned: {'classic', 'mint'},
      );
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      // Mint frame should show "Kuşan" button
      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      expect(mintCard, findsOneWidget);

      final equipButton = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipButton, findsOneWidget);

      await tester.tap(equipButton);
      await tester.pumpAndSettle();

      expect(fakeClient.equippedFrame, equals('mint'));
      expect(find.text(AppStrings.frameEquippedSuccess), findsOneWidget);
    });

    testWidgets('unowned item card displays non-zero price and bottom sheet shows matching price',
        (tester) async {
      final fakeClient = FakeStoreApiClient(coins: 500);
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      expect(mintCard, findsOneWidget);

      // Kart üzerindeki hapta 100 yazmalı, 0 olmamalı
      expect(
        find.descendant(of: mintCard, matching: find.text('100')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mintCard, matching: find.text('0')),
        findsNothing,
      );

      // Karta tıkla -> PurchaseBottomSheet açılır
      await tester.tap(mintCard);
      await tester.pumpAndSettle();

      expect(find.byType(PurchaseBottomSheet), findsOneWidget);
      expect(find.text('100 Jeton'), findsOneWidget);
      expect(find.text('${AppStrings.buyAction} (100 Jeton)'), findsOneWidget);
    });

    testWidgets(
        'switching between multiple owned frames (classic -> mint -> gold -> mint -> classic) updates state and sends requests without blocking',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeClient = FakeStoreApiClient(
        coins: 1000,
        equippedFrame: 'classic',
        owned: {'classic', 'mint', 'gold'},
      );
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      final goldCard = find.byKey(const ValueKey('store_frame_gold'));
      final classicCard = find.byKey(const ValueKey('store_frame_classic'));

      // 1. mint kuşan
      final equipMint = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipMint, findsOneWidget);
      await tester.tap(equipMint);
      await tester.pumpAndSettle();

      expect(fakeClient.equippedFrame, equals('mint'));
      expect(fakeClient.equipHistory, equals(['mint']));
      expect(find.text(AppStrings.frameEquippedSuccess), findsOneWidget);

      // 2. gold kuşan
      final equipGold = find.descendant(
        of: goldCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipGold, findsOneWidget);
      await tester.tap(equipGold);
      await tester.pumpAndSettle();

      expect(fakeClient.equippedFrame, equals('gold'));
      expect(fakeClient.equipHistory, equals(['mint', 'gold']));

      // 3. tekrar mint kuşan
      final equipMintAgain = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipMintAgain, findsOneWidget);
      await tester.tap(equipMintAgain);
      await tester.pumpAndSettle();

      expect(fakeClient.equippedFrame, equals('mint'));
      expect(fakeClient.equipHistory, equals(['mint', 'gold', 'mint']));

      // 4. classic kuşan
      final equipClassic = find.descendant(
        of: classicCard,
        matching: find.text(AppStrings.equipAction),
      );
      expect(equipClassic, findsOneWidget);
      await tester.tap(equipClassic);
      await tester.pumpAndSettle();

      expect(fakeClient.equippedFrame, equals('classic'));
      expect(
          fakeClient.equipHistory, equals(['mint', 'gold', 'mint', 'classic']));
    });

    testWidgets(
        'equipping error shows specific Turkish error message instead of generic fallback',
        (tester) async {
      final fakeClient = FakeStoreApiClient(
        coins: 500,
        equippedFrame: 'classic',
        owned: {'classic', 'mint'},
        customEquipResult:
            const StoreEquipInvalidFrame(AppStrings.storeInvalidFrameError),
      );
      await tester.pumpWidget(createStoreScreen(storeClient: fakeClient));
      await tester.pumpAndSettle();

      final mintCard = find.byKey(const ValueKey('store_frame_mint'));
      final equipMint = find.descendant(
        of: mintCard,
        matching: find.text(AppStrings.equipAction),
      );
      await tester.tap(equipMint);
      await tester.pumpAndSettle();

      // Spesifik hata mesajı görünmeli
      expect(find.text(AppStrings.storeInvalidFrameError), findsOneWidget);
      expect(find.text(AppStrings.storeGenericError), findsNothing);
    });
  });
}

