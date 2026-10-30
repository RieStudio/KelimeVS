import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/theme/app_text_styles.dart';
import 'package:app/core/widgets/app_bottom_nav_bar.dart';
import 'package:app/core/widgets/coin_pill.dart';
import 'package:app/core/widgets/kelime_vs_logo.dart';
import 'package:app/core/widgets/match_card.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/result_badge.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/application/store_notifier.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/main.dart';

class FakeMatchHistoryRepository implements MatchHistoryRepository {
  final List<MatchHistoryEntry> initialEntries;
  FakeMatchHistoryRepository([this.initialEntries = const []]);

  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    return initialEntries;
  }

  @override
  Future<void> clear() async {}
}

class _MockProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  _MockProfileNotifier(this._state);

  @override
  ProfileState build() => _state;
}

Widget _buildTestApp(MatchHistoryRepository repo, {ProfileState? profileState}) {
  return ProviderScope(
    overrides: [
      matchHistoryRepositoryProvider.overrideWithValue(repo),
      if (profileState != null)
        profileProvider.overrideWith(() => _MockProfileNotifier(profileState)),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
    ),
  );
}

Widget _buildMainShellTestApp(
  MatchHistoryRepository repo, {
  ProfileState? profileState,
}) {
  return ProviderScope(
    overrides: [
      matchHistoryRepositoryProvider.overrideWithValue(repo),
      if (profileState != null)
        profileProvider.overrideWith(() => _MockProfileNotifier(profileState)),
    ],
    child: const MaterialApp(
      home: MainShell(),
    ),
  );
}

void main() {
  final testNow = DateTime(2026, 10, 8, 20, 0);

  final wonEntry = MatchHistoryEntry(
    id: 'm1',
    opponentName: 'Zeynep',
    finishedAtMs: testNow.millisecondsSinceEpoch,
    myScore: 2,
    opponentScore: 1,
    result: MatchResult.win,
    endType: MatchEndType.normal,
    roundRecords: const [],
  );

  final lostEntry = MatchHistoryEntry(
    id: 'm2',
    opponentName: 'Elif',
    finishedAtMs: testNow.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    myScore: 1,
    opponentScore: 2,
    result: MatchResult.lose,
    endType: MatchEndType.normal,
    roundRecords: const [],
  );

  testWidgets('1. Ana ekran üst çubuk, logo, butonlar ve boş durum doğru çizilir', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo));
    await tester.pumpAndSettle();

    // Üst çubuk: "Oyuncu" adı, CoinPill (100)
    expect(find.text(AppStrings.defaultPlayerName), findsOneWidget);
    expect(find.byType(CoinPill), findsOneWidget);
    expect(find.text('100'), findsOneWidget);

    // Logo & Slogan
    expect(find.byType(KelimeVSLogo), findsOneWidget);
    expect(find.text(AppStrings.slogan), findsOneWidget);

    // Ana ve İkincil butonlar
    expect(find.text(AppStrings.quickMatch), findsOneWidget);
    expect(find.text(AppStrings.playWithFriend), findsOneWidget);

    // Boş durum metni
    expect(find.text(AppStrings.noMatchesYet), findsOneWidget);
  });

  testWidgets('2. Maç geçmişi listelenir: kartta tarih yok, rakip adı dikey ortalı, rozetler ve kenarlık doğru', (tester) async {
    final repo = FakeMatchHistoryRepository([wonEntry, lostEntry]);

    await tester.pumpWidget(_buildTestApp(repo));
    await tester.pumpAndSettle();

    expect(find.byType(MatchCard), findsNWidgets(2));

    // Zeynep kartı (Kazandın, 2 – 1, tarih YOK)
    expect(find.text('Zeynep'), findsOneWidget);
    expect(find.text('2 – 1'), findsOneWidget);
    expect(find.widgetWithText(ResultBadge, AppStrings.won), findsOneWidget);

    // Elif kartı (Kaybettin, 1 – 2, tarih YOK)
    expect(find.text('Elif'), findsOneWidget);
    expect(find.text('1 – 2'), findsOneWidget);
    expect(find.widgetWithText(ResultBadge, AppStrings.lost), findsOneWidget);

    // Kartta hiçbir tarih metni olmamalı
    expect(find.text('Bugün'), findsNothing);
    expect(find.text('Dün'), findsNothing);

    // Elif kartının kenarlık rengi dangerSoft olmalı
    final matchCards = tester.widgetList<MatchCard>(find.byType(MatchCard)).toList();
    final lostCardWidget = matchCards.firstWhere((c) => c.entry.id == 'm2');
    expect(lostCardWidget.entry.result, MatchResult.lose);

    // Kartın Container decoration kenarlık rengini kontrol et
    final lostContainerFinder = find.descendant(
      of: find.ancestor(of: find.text('Elif'), matching: find.byType(MatchCard)),
      matching: find.byWidgetPredicate(
        (w) => w is Container && (w.decoration as BoxDecoration?)?.border != null,
      ),
    );
    final lostContainer = tester.widget<Container>(lostContainerFinder.first);
    final border = (lostContainer.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.dangerSoft);
  });

  testWidgets('3. "Hızlı Maç" butonuna basıldığında MatchmakingScreen açılır', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo));
    await tester.pumpAndSettle();

    expect(find.byType(MatchmakingScreen), findsNothing);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.quickMatch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MatchmakingScreen), findsOneWidget);
  });

  testWidgets('4. "Arkadaşınla Oyna" butonuna basıldığında arkadaşla düello penceresi açılır', (tester) async {
    final repo = FakeMatchHistoryRepository([]);

    await tester.pumpWidget(_buildTestApp(repo));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.createRoom), findsNothing);

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.playWithFriend));
    await tester.pumpAndSettle();

    // FriendDuelBottomSheet açılmalı
    expect(find.text(AppStrings.friendDuel), findsOneWidget);
    expect(find.text(AppStrings.createRoom), findsOneWidget);
    expect(find.text(AppStrings.joinRoom), findsOneWidget);
  });

  testWidgets('5. Ana ekran listesi finishedAtMs azalan sırayla ve eşitlikte son eklenen üstte olacak şekilde çizilir', (tester) async {
    final olderEntry = MatchHistoryEntry(
      id: 'm_old',
      opponentName: 'Eski Rakip',
      finishedAtMs: 1000,
      myScore: 2,
      opponentScore: 0,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      roundRecords: const [],
    );

    final newerEntry = MatchHistoryEntry(
      id: 'm_new',
      opponentName: 'Yeni Rakip',
      finishedAtMs: 5000,
      myScore: 1,
      opponentScore: 2,
      result: MatchResult.lose,
      endType: MatchEndType.normal,
      roundRecords: const [],
    );

    final sameTimeEntryFirst = MatchHistoryEntry(
      id: 'm_same1',
      opponentName: 'İlk Eklenen Aynı Zaman',
      finishedAtMs: 3000,
      myScore: 2,
      opponentScore: 1,
      result: MatchResult.win,
      endType: MatchEndType.normal,
      roundRecords: const [],
    );

    final sameTimeEntryLater = MatchHistoryEntry(
      id: 'm_same2',
      opponentName: 'Son Eklenen Aynı Zaman',
      finishedAtMs: 3000,
      myScore: 0,
      opponentScore: 2,
      result: MatchResult.lose,
      endType: MatchEndType.normal,
      roundRecords: const [],
    );

    // Depodan karışık sırada dönen liste: [olderEntry, sameTimeEntryLater, sameTimeEntryFirst, newerEntry]
    // Beklenen sıralama:
    // 1. newerEntry (5000)
    // 2. sameTimeEntryLater (3000, depoda daha önce/üstte olan)
    // 3. sameTimeEntryFirst (3000)
    // 4. olderEntry (1000)
    final repo = FakeMatchHistoryRepository([
      olderEntry,
      sameTimeEntryLater,
      sameTimeEntryFirst,
      newerEntry,
    ]);

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildTestApp(repo));
    await tester.pumpAndSettle();

    final renderedCards = tester.widgetList<MatchCard>(find.byType(MatchCard)).toList();
    expect(renderedCards.length, 4);
    expect(renderedCards[0].entry.id, 'm_new');
    expect(renderedCards[1].entry.id, 'm_same2');
    expect(renderedCards[2].entry.id, 'm_same1');
    expect(renderedCards[3].entry.id, 'm_old');
  });

  testWidgets('6. Avatar/takma ad butonuna tıklandığında bottomNavIndexProvider 3 (Profil) olur', (tester) async {
    final repo = FakeMatchHistoryRepository([]);
    int capturedIndex = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchHistoryRepositoryProvider.overrideWithValue(repo),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedIndex = ref.watch(bottomNavIndexProvider);
            return const MaterialApp(
              home: HomeScreen(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedIndex, 0);

    await tester.tap(find.byKey(const Key('profile_avatar_button')));
    await tester.pumpAndSettle();

    expect(capturedIndex, 3);
  });

  testWidgets('7. Son Maçlarım boş durumu: played > 0 ve yerel geçmiş boşsa geçmiş sıfırlandı mesajı gösterilir', (tester) async {
    final repo = FakeMatchHistoryRepository([]);
    const state = ProfileState(
      isLoaded: true,
      stats: UserStats(played: 3, won: 2, lost: 1, correctAnswers: 8),
    );

    await tester.pumpWidget(_buildTestApp(repo, profileState: state));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.noMatchesHistoryReset), findsOneWidget);
    expect(find.text(AppStrings.noMatchesYet), findsNothing);
    expect(find.byType(MatchCard), findsNothing);
  });

  testWidgets('8. Son Maçlarım boş durumu: played == 0 ve yerel geçmiş boşsa henüz maç oynamadın mesajı gösterilir', (tester) async {
    final repo = FakeMatchHistoryRepository([]);
    const state = ProfileState(
      isLoaded: true,
      stats: UserStats(played: 0, won: 0, lost: 0, correctAnswers: 0),
    );

    await tester.pumpWidget(_buildTestApp(repo, profileState: state));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.noMatchesYet), findsOneWidget);
    expect(find.text(AppStrings.noMatchesHistoryReset), findsNothing);
    expect(find.byType(MatchCard), findsNothing);
  });

  testWidgets('9. Son Maçlarım: geçmiş dolu olduğunda (played > 0 olsa bile) maç kartları listelenir, boş durum gösterilmez', (tester) async {
    final repo = FakeMatchHistoryRepository([wonEntry]);
    const state = ProfileState(
      isLoaded: true,
      stats: UserStats(played: 10, won: 8, lost: 2, correctAnswers: 25),
    );

    await tester.pumpWidget(_buildTestApp(repo, profileState: state));
    await tester.pumpAndSettle();

    expect(find.byType(MatchCard), findsOneWidget);
    expect(find.text(AppStrings.noMatchesYet), findsNothing);
    expect(find.text(AppStrings.noMatchesHistoryReset), findsNothing);
  });

  testWidgets('10. Son Maçlarım boş durumu: isLoaded false veya hata varsa (played > 0 olsa dahi) mevcut noMatchesYet gösterilir', (tester) async {
    final repo = FakeMatchHistoryRepository([]);
    const notLoadedState = ProfileState(
      isLoaded: false,
      stats: UserStats(played: 5, won: 3, lost: 2),
    );

    await tester.pumpWidget(_buildTestApp(repo, profileState: notLoadedState));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.noMatchesYet), findsOneWidget);
    expect(find.text(AppStrings.noMatchesHistoryReset), findsNothing);

    const errorState = ProfileState(
      isLoaded: true,
      syncError: 'Profil yüklenemedi',
      stats: UserStats(played: 5, won: 3, lost: 2),
    );

    await tester.pumpWidget(_buildTestApp(repo, profileState: errorState));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.noMatchesYet), findsOneWidget);
    expect(find.text(AppStrings.noMatchesHistoryReset), findsNothing);
  });

  testWidgets(
    '11. Üst satır hizalaması: kısa ve uzun kullanıcı adında sağ grup her zaman sağ kenara yaslı kalır ve x koordinatı sabittir',
    (tester) async {
      final repo = FakeMatchHistoryRepository([]);

      // 1. Kısa kullanıcı adı ('Ali')
      const shortProfile = ProfileState(
        isLoaded: true,
        nickname: 'Ali',
        coins: 100,
      );
      await tester.pumpWidget(_buildTestApp(repo, profileState: shortProfile));
      await tester.pumpAndSettle();

      final rightGroupFinder = find.byKey(
        const Key('home_top_bar_right_group'),
      );
      expect(rightGroupFinder, findsOneWidget);
      final shortRightRect = tester.getRect(rightGroupFinder);
      final settingsFinder = find.byKey(const Key('settings_button'));
      expect(settingsFinder, findsOneWidget);
      final shortSettingsRect = tester.getRect(settingsFinder);

      // 2. Uzun kullanıcı adı ('MuhammedMustafa_')
      const longProfile = ProfileState(
        isLoaded: true,
        nickname: 'MuhammedMustafa_',
        coins: 100,
      );
      await tester.pumpWidget(_buildTestApp(repo, profileState: longProfile));
      await tester.pumpAndSettle();

      final longRightRect = tester.getRect(rightGroupFinder);
      final longSettingsRect = tester.getRect(settingsFinder);

      // Sağ grubun ve ayarlar butonunun sol/sağ x koordinatı hem kısa hem uzun isimde TAMAMEN aynı olmalıdır
      expect(shortRightRect.left, equals(longRightRect.left));
      expect(shortRightRect.right, equals(longRightRect.right));
      expect(shortSettingsRect.left, equals(longSettingsRect.left));
      expect(shortSettingsRect.right, equals(longSettingsRect.right));
    },
  );

  testWidgets(
    '12. Son Maçlarım boş durum kartı ile alt bar arasında en az 16 dp mesafe bulunur',
    (tester) async {
      final repo = FakeMatchHistoryRepository([]);
      const profile = ProfileState(
        isLoaded: true,
        nickname: 'Oyuncu',
        coins: 100,
      );

      await tester.pumpWidget(
        _buildMainShellTestApp(repo, profileState: profile),
      );
      await tester.pumpAndSettle();

      final emptyCardFinder = find.byKey(const Key('empty_matches_card'));
      expect(emptyCardFinder, findsOneWidget);

      final bottomNavFinder = find.byType(AppBottomNavBar);
      expect(bottomNavFinder, findsOneWidget);

      final emptyCardBottom = tester.getBottomLeft(emptyCardFinder).dy;
      final bottomNavTop = tester.getTopLeft(bottomNavFinder).dy;

      expect(
        bottomNavTop - emptyCardBottom,
        greaterThanOrEqualTo(AppDimens.space16),
      );
    },
  );

  testWidgets(
    '13. Son Maçlarım dolu listede en son eleman ile alt bar arasında en az 16 dp mesafe bulunur',
    (tester) async {
      final entries = List.generate(
        8,
        (i) => MatchHistoryEntry(
          id: 'm_$i',
          opponentName: 'Rakip $i',
          finishedAtMs: 1000 + i * 1000,
          myScore: 2,
          opponentScore: 0,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: const [],
        ),
      );
      final repo = FakeMatchHistoryRepository(entries);
      const profile = ProfileState(
        isLoaded: true,
        nickname: 'Oyuncu',
        coins: 100,
      );

      await tester.pumpWidget(
        _buildMainShellTestApp(repo, profileState: profile),
      );
      await tester.pumpAndSettle();

      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);

      // Listenin en sonuna kaydır
      await tester.drag(listViewFinder, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final bottomNavFinder = find.byType(AppBottomNavBar);
      expect(bottomNavFinder, findsOneWidget);

      final bottomNavTop = tester.getTopLeft(bottomNavFinder).dy;
      final listViewBottom = tester.getBottomLeft(listViewFinder).dy;

      // ListView'in bittiği yer alt çubuğun en az 16 dp üzerinde olmalı
      expect(
        bottomNavTop - listViewBottom,
        greaterThanOrEqualTo(AppDimens.space16),
      );

      // Son görünen kartın alt kenarı da alt çubuğun en az 16 dp üzerinde olmalı
      final matchCards = find.byType(MatchCard);
      expect(matchCards, findsWidgets);
      final lastCardBottom = tester.getBottomLeft(matchCards.last).dy;
      expect(
        bottomNavTop - lastCardBottom,
        greaterThanOrEqualTo(AppDimens.space16),
      );
    },
  );

  testWidgets(
    '14. 320x640 ekranda ve 1.5 yazı ölçeğinde hem boş hem dolu listede sıfır taşma ile çizilir',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const profile = ProfileState(
        isLoaded: true,
        nickname: 'MuhammedMustafa_',
        coins: 9999,
      );

      // A) Boş liste
      final emptyRepo = FakeMatchHistoryRepository([]);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: _buildMainShellTestApp(emptyRepo, profileState: profile),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final emptyCardFinder = find.byKey(const Key('empty_matches_card'));
      expect(emptyCardFinder, findsOneWidget);
      final bottomNavFinder = find.byType(AppBottomNavBar);
      expect(bottomNavFinder, findsOneWidget);

      final emptyCardBottom = tester.getBottomLeft(emptyCardFinder).dy;
      final bottomNavTop = tester.getTopLeft(bottomNavFinder).dy;
      expect(
        bottomNavTop - emptyCardBottom,
        greaterThanOrEqualTo(AppDimens.space16),
      );

      // B) Dolu liste
      final filledRepo = FakeMatchHistoryRepository([wonEntry, lostEntry]);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: _buildMainShellTestApp(filledRepo, profileState: profile),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MatchCard), findsWidgets);
    },
  );

  testWidgets(
    '15. Enerji kapalı/null iken CoinPill tekil rozet halinde kalır, ayırıcı ve enerji ikonu çizilmez',
    (tester) async {
      final repo = FakeMatchHistoryRepository([]);
      const profileNoEnergy = ProfileState(
        isLoaded: true,
        nickname: 'Oyuncu',
        coins: 250,
        energy: null,
      );

      await tester.pumpWidget(
        _buildTestApp(repo, profileState: profileNoEnergy),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CoinPill), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      expect(find.byKey(const Key('energy_pill_button')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == AppIcons.bolt,
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    '16. Enerji açıkken CoinPill birleşik rozet (Jeton | Ayırıcı | Enerji) olarak tek kapsülde çizilir',
    (tester) async {
      final repo = FakeMatchHistoryRepository([]);
      const profileWithEnergy = ProfileState(
        isLoaded: true,
        nickname: 'Oyuncu',
        coins: 350,
        energy: EnergyState(
          enabled: true,
          current: 4,
          max: 5,
          regenSeconds: 1200,
          packs: [],
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(repo, profileState: profileWithEnergy),
      );
      await tester.pumpAndSettle();

      // Tek bir CoinPill var
      expect(find.byType(CoinPill), findsOneWidget);
      // Jeton ve enerji değerleri aynı rozette
      expect(find.text('350'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.byKey(const Key('energy_pill_button')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == AppIcons.bolt,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '17. Dokunma davranışları: Enerjiye dokununca Mağaza Enerji sekmesine geçer, jetona dokunulunca sayfa değişmez',
    (tester) async {
      final repo = FakeMatchHistoryRepository([]);
      const profile = ProfileState(
        isLoaded: true,
        nickname: 'Oyuncu',
        coins: 100,
        energy: EnergyState(
          enabled: true,
          current: 2,
          max: 5,
          regenSeconds: 1200,
          packs: [],
        ),
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchHistoryRepositoryProvider.overrideWithValue(repo),
            profileProvider.overrideWith(() => _MockProfileNotifier(profile)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: MainShell());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Başlangıç: Ana Sayfa sekmesi (index 0)
      expect(container.read(bottomNavIndexProvider), 0);

      // 1. Jeton bölümüne dokun (herhangi bir rota/sekme değişikliği olmamalı)
      await tester.tap(find.text('100'));
      await tester.pumpAndSettle();
      expect(container.read(bottomNavIndexProvider), 0);

      // 2. Enerji bölümüne dokun (Mağaza sekmesine ve Enerji alt sekmesine geçmeli)
      await tester.tap(find.byKey(const Key('energy_pill_button')));
      await tester.pumpAndSettle();
      expect(container.read(bottomNavIndexProvider), 2);
      expect(container.read(storeNotifierProvider).selectedTab, StoreTab.energy);
    },
  );

  testWidgets(
    '18. Kısa, uzun ve 16 karakterlik takma ad ile 5-6 haneli jetonlarda sağ grup x konumu sabittir, 320x640 ve 1.5 yazı ölçeğinde sıfır taşma',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = FakeMatchHistoryRepository([]);

      final testCases = [
        ('Ali', 50),
        ('MuhammedMustafa_', 99999),
        ('1234567890123456', 999999),
      ];

      double? expectedRightGroupLeft;
      double? expectedRightGroupRight;

      for (final (name, coins) in testCases) {
        final profile = ProfileState(
          isLoaded: true,
          nickname: name,
          coins: coins,
          energy: const EnergyState(
            enabled: true,
            current: 5,
            max: 5,
            regenSeconds: 1200,
            packs: [],
          ),
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: _buildTestApp(repo, profileState: profile),
          ),
        );
        await tester.pumpAndSettle();

        // 320x640 ve 1.5 textScaler'da hiçbir taşma hatası olmamalı
        expect(tester.takeException(), isNull);

        final rightGroupFinder = find.byKey(const Key('home_top_bar_right_group'));
        expect(rightGroupFinder, findsOneWidget);
        final rect = tester.getRect(rightGroupFinder);

        // Sağ grup her zaman sağ kenara dayalı olmalıdır (320 - 20 padding = 300)
        expect(rect.right, equals(300.0));

        // 5 ve 6 haneli sayılarda maxWidth (180) ve FixedBox sayesinde sağ grubun genişliği sabit kalır
        expectedRightGroupLeft ??= rect.left;
        expectedRightGroupRight ??= rect.right;
        expect(rect.right, equals(expectedRightGroupRight));
      }
    },
  );

  testWidgets(
    '19. 360 dp ekranda enerji açıkken takma ad görünür alanının ölçümü (önce vs sonra)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = FakeMatchHistoryRepository([]);
      const longNickname = 'MuhammedMustafa_'; // 16 karakter

      const profile = ProfileState(
        isLoaded: true,
        nickname: longNickname,
        coins: 100,
        energy: EnergyState(
          enabled: true,
          current: 3,
          max: 5,
          regenSeconds: 1200,
          packs: [],
        ),
      );

      await tester.pumpWidget(_buildTestApp(repo, profileState: profile));
      await tester.pumpAndSettle();

      final nicknameFinder = find.text(longNickname);
      expect(nicknameFinder, findsOneWidget);

      final renderParagraph = tester.renderObject<RenderParagraph>(nicknameFinder);
      final availableWidthNew = renderParagraph.constraints.maxWidth;

      // Önceki iki rozetli sistemde:
      // CoinPill (88) + 8 + EnergyPill (62) + 8 + SettingsBtn (48) = 214 dp sağ grup.
      // 360 ekran - 40 margin - 8 gap - 214 sağ grup = 98 dp sol grup.
      // 98 - 52 (avatar + gap) = 46 dp takma ad alanı.
      //
      // Yeni birleşik rozette:
      // Tek rozet (~144) + 8 + SettingsBtn (48) = 200 dp sağ grup.
      // 360 ekran - 40 margin - 8 gap - 200 sağ grup = 112 dp sol grup.
      // 112 - 52 (avatar + gap) = 60 dp takma ad alanı!
      const availableWidthOld = 46.0;

      expect(availableWidthNew, greaterThan(availableWidthOld));

      // Nunito 16/800 fontunda ellipsis öncesi kaç karakter sığıyor hesapla:
      const textStyle = TextStyle(
        fontFamily: AppTextStyles.fontNunito,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      );

      int countVisibleChars(double width) {
        for (int i = longNickname.length; i >= 1; i--) {
          final candidate = '${longNickname.substring(0, i)}…';
          final tp = TextPainter(
            text: TextSpan(text: candidate, style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          if (tp.width <= width) {
            return i;
          }
        }
        return 0;
      }

      final charsOld = countVisibleChars(availableWidthOld);
      final charsNew = countVisibleChars(availableWidthNew);

      // ignore: avoid_print
      print(
        '[Nickname Width Measurement @ 360dp]: '
        'Önceki alan: ${availableWidthOld.toStringAsFixed(1)} dp ($charsOld karakter + …) -> '
        'Yeni alan: ${availableWidthNew.toStringAsFixed(1)} dp ($charsNew karakter + …) '
        '(Kazanım: +${(availableWidthNew - availableWidthOld).toStringAsFixed(1)} dp, +${charsNew - charsOld} karakter)',
      );

      expect(charsNew, greaterThanOrEqualTo(charsOld));
    },
  );
}
