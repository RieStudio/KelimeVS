import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/leaderboard/presentation/leaderboard_screen.dart';

class FakeLeaderboardApiClient implements LeaderboardApiClient {
  LeaderboardData? dataToReturn;
  Object? errorToThrow;
  int fetchCallCount = 0;

  FakeLeaderboardApiClient({this.dataToReturn, this.errorToThrow});

  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    fetchCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return dataToReturn ??
        const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [],
        );
  }
}

Widget createLeaderboardScreen({
  required LeaderboardApiClient client,
}) {
  return ProviderScope(
    overrides: [
      leaderboardApiClientProvider.overrideWithValue(client),
    ],
    child: const MaterialApp(
      home: LeaderboardScreen(),
    ),
  );
}

void main() {
  group('LeaderboardScreen Widget Tests', () {
    testWidgets('1. Boş veri durumunda (empty state) doğru başlık ve Hızlı Maç butonu çıkar',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [],
          me: null,
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_screen')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_empty')), findsOneWidget);
      expect(find.text(AppStrings.emptyLeaderboard), findsOneWidget);
      expect(find.text(AppStrings.emptyLeaderboardSubtitle), findsOneWidget);
      expect(find.text(AppStrings.quickMatch), findsOneWidget);
    });

    testWidgets('2. Hata durumunda hata kartı ve Tekrar Dene butonu gösterilir',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        errorToThrow: Exception('Bağlantı hatası'),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_error')), findsOneWidget);
      expect(find.text(AppStrings.leaderboardError), findsOneWidget);
      expect(find.text(AppStrings.retry), findsOneWidget);

      // Tekrar dene butonuna dokunulunca fetch tekrar çağrılır
      fakeClient.errorToThrow = null;
      fakeClient.dataToReturn = const LeaderboardData(
        weekKey: '2026-W42',
        endsAt: 1792357200000,
        top: [
          LeaderboardEntry(rank: 1, nickname: 'Lider', wins: 5, isMe: true),
        ],
      );

      await tester.tap(find.text(AppStrings.retry));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('Lider'), findsOneWidget);
    });

    testWidgets('3. Dolu listede 1., 2. ve 3. sıra rozetleri ve kullanıcı vurgusu doğrulanır',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'Birinci', wins: 15, isMe: false),
            LeaderboardEntry(rank: 2, nickname: 'IkinciBen', wins: 12, isMe: true),
            LeaderboardEntry(rank: 3, nickname: 'Ucuncu', wins: 9, isMe: false),
            LeaderboardEntry(rank: 4, nickname: 'Dorduncu', wins: 6, isMe: false),
          ],
          me: LeaderboardMe(rank: 2, wins: 12),
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('Birinci'), findsOneWidget);
      expect(find.text('IkinciBen'), findsOneWidget);
      expect(find.text('Ucuncu'), findsOneWidget);
      expect(find.text('Dorduncu'), findsOneWidget);

      // Kullanıcı vurgusu (Sen rozeti)
      expect(find.text(AppStrings.you), findsOneWidget);

      // Kullanıcı zaten ilk 50'de olduğu için yapışkan alt çubuk gösterilmez
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsNothing);
    });

    testWidgets('4. Kullanıcı ilk 50 dışındaysa yapışkan alt çubukta sırası gösterilir',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'TopOyuncu', wins: 20, isMe: false),
          ],
          me: LeaderboardMe(rank: 74, wins: 3),
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(find.text('Senin sıran: #74 (3 galibiyet)'), findsOneWidget);
    });
  });
}

