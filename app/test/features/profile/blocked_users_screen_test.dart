import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
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

  testWidgets('1. Engel listesi boşken boş durum kartı gösterilir', (tester) async {
    final client = FakeBlockedUsersApiClient(usersToReturn: []);
    await tester.pumpWidget(buildTestScreen(client));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.blockedUsersTitle), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsers), findsOneWidget);
    expect(find.text(AppStrings.emptyBlockedUsersSubtitle), findsOneWidget);
  });

  testWidgets('2. Engellenen kullanıcılar listelenir', (tester) async {
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
