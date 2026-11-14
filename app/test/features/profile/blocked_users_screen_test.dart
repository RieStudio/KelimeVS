import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/empty_state_card.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/profile/application/blocked_users_notifier.dart';
import 'package:app/features/profile/data/blocked_users_api_client.dart';
import 'package:app/features/profile/domain/blocked_user_model.dart';
import 'package:app/features/profile/presentation/blocked_users_screen.dart';

class FakeBlockedUsersApiClient implements BlockedUsersApiClient {
  List<BlockedUser> usersToReturn;
  bool unblockCalled = false;
  String? unblockedId;

  FakeBlockedUsersApiClient({this.usersToReturn = const []});

  @override
  Future<List<BlockedUser>> getBlockedUsers() async => usersToReturn;

  @override
  Future<bool> unblockUser(String id) async {
    unblockCalled = true;
    unblockedId = id;
    usersToReturn = usersToReturn.where((u) => u.id != id).toList();
    return true;
  }

  @override
  Future<BlockUserResult> blockUser(String matchId) async =>
      const BlockUserSuccess('new_block_id');

  @override
  Future<ReportUserResult> reportUser({
    required String matchId,
    required String reason,
  }) async =>
      const ReportUserSuccess();
}

Finder findSvgAsset(String assetName) {
  return find.byWidgetPredicate((widget) {
    if (widget is SvgPicture) {
      final loader = widget.bytesLoader;
      if (loader is SvgAssetLoader) {
        return loader.assetName == assetName;
      }
    }
    return false;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestScreen(FakeBlockedUsersApiClient client) {
    return ProviderScope(
      overrides: [
        blockedUsersApiClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        home: BlockedUsersScreen(),
      ),
    );
  }

  testWidgets('1. Engel listesi boşken boş durum kartı ve ikonu gösterilir, ortak EmptyStateCard dekorasyonunu kullanır', (tester) async {
    final client = FakeBlockedUsersApiClient(usersToReturn: []);
    await tester.pumpWidget(buildTestScreen(client));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.blockedUsersTitle), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsers), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsersSubtitle), findsOneWidget);

    final emptyCardFinder = find.byType(EmptyStateCard);
    expect(emptyCardFinder, findsOneWidget);

    // Boş durum kalkan ikonu kontrolü
    final iconFinder = findSvgAsset(BlockedUsersScreen.emptyIconAsset);
    expect(iconFinder, findsOneWidget);

    final svgWidget = tester.widget<SvgPicture>(iconFinder);
    expect(svgWidget.width, BlockedUsersScreen.emptyIconSize);
    expect(svgWidget.height, BlockedUsersScreen.emptyIconSize);
    expect(svgWidget.colorFilter, isNull);

    // İkonun dekoratif olup ExcludeSemantics ile sarmalandığı doğrulanır
    final excludedAncestor = find.ancestor(
      of: iconFinder,
      matching: find.byType(ExcludeSemantics),
    );
    expect(excludedAncestor, findsOneWidget);

    // İkonun başlığın üstünde yer aldığı ve aralarında boşluk olduğu doğrulanır
    final iconRect = tester.getRect(iconFinder);
    final titleRect = tester.getRect(find.text(AppStrings.emptyBlockedUsers));
    expect(iconRect.bottom, lessThan(titleRect.top));
    expect(titleRect.top - iconRect.bottom, closeTo(AppDimens.space16, 0.5));

    final container = tester.widget<Container>(
      find.descendant(of: emptyCardFinder, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.card);
    expect(decoration.borderRadius, AppDimens.borderRadiusListCard);
    expect(decoration.border?.top.color, AppColors.ink);
    expect(decoration.border?.top.width, AppDimens.borderThick);
    expect(decoration.boxShadow, AppDimens.shadowQuestionCard);
  });

  testWidgets('2. Engellenen kullanıcılar listelenir ve boş durum ikonu gösterilmez', (tester) async {
    final users = [
      const BlockedUser(id: 'b1', nickname: 'Ali', blockedAt: 1729000000000),
      const BlockedUser(id: 'b2', nickname: 'Veli', blockedAt: 1729100000000),
    ];
    final client = FakeBlockedUsersApiClient(usersToReturn: users);
    await tester.pumpWidget(buildTestScreen(client));
    await tester.pumpAndSettle();

    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Veli'), findsOneWidget);
    expect(find.widgetWithText(SecondaryButton, AppStrings.unblockAction), findsNWidgets(2));

    // Liste doluyken boş durum ikonu ve kartı bulunmaz
    expect(findSvgAsset(BlockedUsersScreen.emptyIconAsset), findsNothing);
    expect(find.byType(EmptyStateCard), findsNothing);
  });

  testWidgets('3. Kaldır butonuna basıldığında unblockUser çağrılır ve SnackBar gösterilir', (tester) async {
    final users = [
      const BlockedUser(id: 'b1', nickname: 'Ali', blockedAt: 1729000000000),
    ];
    final client = FakeBlockedUsersApiClient(usersToReturn: users);
    await tester.pumpWidget(buildTestScreen(client));
    await tester.pumpAndSettle();

    expect(find.text('Ali'), findsOneWidget);

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.unblockAction));
    await tester.pumpAndSettle();

    expect(client.unblockCalled, isTrue);
    expect(client.unblockedId, 'b1');
    expect(find.text('Ali'), findsNothing);
    expect(find.text(AppStrings.unblockSuccess), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsers), findsOneWidget);
  });

  testWidgets('4. Boş liste yüklendikten sonra engelleme yapılınca liste yeniden açıldığında yeni engellenen görünür (autoDispose & taze veri)', (tester) async {
    final client = FakeBlockedUsersApiClient(usersToReturn: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockedUsersApiClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BlockedUsersScreen(),
                        ),
                      );
                    },
                    child: const Text('Engellenenleri Aç'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Ekranı aç: liste boştur
    await tester.tap(find.text('Engellenenleri Aç'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emptyBlockedUsers), findsOneWidget);
    expect(find.text('YeniEngellenen'), findsNothing);

    // 2. Geri çık (ekran kapatılır -> autoDispose tetiklenir)
    await tester.tap(find.bySemanticsLabel(AppStrings.back));
    await tester.pumpAndSettle();

    // 3. Sunucuda yeni bir engelleme gerçekleşti
    client.usersToReturn = [
      const BlockedUser(id: 'b_new', nickname: 'YeniEngellenen', blockedAt: 1729000000000),
    ];

    // 4. Ekran tekrar açılır
    await tester.tap(find.text('Engellenenleri Aç'));
    await tester.pumpAndSettle();

    // 5. autoDispose sayesinde provider yeniden build olmuş ve taze veriyi çekmiştir
    expect(find.text('YeniEngellenen'), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsers), findsNothing);
  });

  testWidgets('5. Provider açıkken ref.invalidate çağrılırsa liste anında yeniden çekilir', (tester) async {
    final client = FakeBlockedUsersApiClient(usersToReturn: []);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockedUsersApiClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const BlockedUsersScreen();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emptyBlockedUsers), findsOneWidget);

    // Sunucuya yeni veri eklendi
    client.usersToReturn = [
      const BlockedUser(id: 'b_active', nickname: 'CanliEngellenen', blockedAt: 1729000000000),
    ];

    // Maç sonu ekranında olduğu gibi ref.invalidate(blockedUsersProvider) çağrılır
    capturedRef.invalidate(blockedUsersProvider);
    await tester.pumpAndSettle();

    expect(find.text('CanliEngellenen'), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsers), findsNothing);
  });
}
