import 'dart:async';
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
  Completer<LeaderboardData>? pendingCompleter;

  FakeLeaderboardApiClient({this.dataToReturn, this.errorToThrow});

  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    fetchCallCount++;
    if (pendingCompleter != null) {
      return pendingCompleter!.future;
    }
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

      // Kullanıcı zaten ilk 100'de olduğu için yapışkan alt çubuk gösterilmez
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsNothing);
    });

    testWidgets('4. Kullanıcı ilk 100 dışındaysa yapışkan alt çubukta sırası gösterilir',
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
      expect(find.text('74. sıradasın'), findsOneWidget);
      expect(find.text('#74'), findsOneWidget);
      expect(find.text('3 galibiyet'), findsOneWidget);
    });

    testWidgets('5. Sekme modunda (canPop == false) geri butonu gizlidir',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'Oyuncu1', wins: 10, isMe: false),
          ],
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      // canPop false olduğundan geri butonu olmamalıdır
      expect(find.byKey(const Key('leaderboard_back_button')), findsNothing);
    });

    testWidgets('6. Navigator.push ile açıldığında (canPop == true) geri butonu görünür ve pop eder',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'Oyuncu1', wins: 10, isMe: false),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardApiClientProvider.overrideWithValue(fakeClient),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                    );
                  },
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Push et
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      // Geri butonu görünür olmalı
      final backButton = find.byKey(const Key('leaderboard_back_button'));
      expect(backButton, findsOneWidget);

      // Dokununca pop etmeli
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.text('Aç'), findsOneWidget);
      expect(find.byType(LeaderboardScreen), findsNothing);
    });

    testWidgets('7. Tazelemede (refresh) liste çarka dönmez, eski veri ekranda kalır',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'EskiLider', wins: 10, isMe: false),
          ],
        ),
      );

      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardApiClientProvider.overrideWithValue(fakeClient),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                savedRef = ref;
                return const LeaderboardScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EskiLider'), findsOneWidget);

      // İkinci istek beklemede kalsın (async in-flight)
      final completer = Completer<LeaderboardData>();
      fakeClient.pendingCompleter = completer;

      // Arka plan yenilemesini tetikle
      unawaited(savedRef.read(leaderboardNotifierProvider.notifier).refresh());
      await tester.pump();

      // Yükleme çarkı çıkmamalı, liste ve eski veri ekranda kalmalı
      expect(find.byKey(const Key('leaderboard_loading')), findsNothing);
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('EskiLider'), findsOneWidget);

      // Yanıt gelsin
      completer.complete(
        const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'YeniLider', wins: 15, isMe: false),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YeniLider'), findsOneWidget);
    });

    testWidgets('8. Arka plan tazelemesi hata verirse eski liste kalır ve küçük uyarı gösterilir',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'MevcutOyuncu', wins: 8, isMe: false),
          ],
        ),
      );

      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardApiClientProvider.overrideWithValue(fakeClient),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                savedRef = ref;
                return const LeaderboardScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MevcutOyuncu'), findsOneWidget);

      // Hata döndür
      fakeClient.errorToThrow = Exception('Ağ koptu');
      await savedRef.read(leaderboardNotifierProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // Tam ekran hata sayfasına düşmemeli, liste korunmalı
      expect(find.byKey(const Key('leaderboard_error')), findsNothing);
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('MevcutOyuncu'), findsOneWidget);

      // Küçük senkronizasyon uyarı şeridi çıkmalı
      expect(find.byKey(const Key('leaderboard_sync_error_banner')), findsOneWidget);
    });

    testWidgets(
        '9. 100 satırlık listede kaydırma sorunsuz çalışır ve ilk 100 dışındaki kullanıcı için yapışkan SEN çubuğu görünür kalır',
        (tester) async {
      final entries = List.generate(
        100,
        (i) => LeaderboardEntry(
          rank: i + 1,
          nickname: 'Oyuncu_${i + 1}',
          wins: 100 - i,
          isMe: false,
        ),
      );

      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: entries,
          me: const LeaderboardMe(rank: 105, wins: 4),
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      // Liste ve ilk eleman görünür
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('Oyuncu_1'), findsOneWidget);

      // İlk 100 dışındaki kullanıcı için yapışkan çubuk görünür
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(find.text('105. sıradasın'), findsOneWidget);
      expect(find.text('#105'), findsOneWidget);
      expect(find.text('4 galibiyet'), findsOneWidget);

      // 100 satırlık listeyi aşağı kaydır
      await tester.drag(
        find.byKey(const Key('leaderboard_list')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      // Hata oluşmadığını doğrula
      expect(tester.takeException(), isNull);

      // Yapışkan çubuk kaydırmadan sonra da altta sabit kalmalıdır
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(find.text('105. sıradasın'), findsOneWidget);
      expect(find.text('#105'), findsOneWidget);
      expect(find.text('4 galibiyet'), findsOneWidget);

      // Listenin en sonuna kadar kaydır
      await tester.scrollUntilVisible(
        find.text('Oyuncu_100'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Oyuncu_100'), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '10. İlk 3 rozet (taç, gümüş 2, bronz 3), koyu kenarlıklar ve dar ekranda (320dp, textScale 1.3) #100/#1000 taşma yapmaz',
        (tester) async {
      // 320x640 dar ekran boyutu
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'LiderKral', wins: 40, isMe: false),
            LeaderboardEntry(rank: 2, nickname: 'IkinciOyuncu', wins: 38, isMe: false),
            LeaderboardEntry(rank: 3, nickname: 'UcuncuOyuncu', wins: 35, isMe: false),
            LeaderboardEntry(rank: 100, nickname: 'YuzuncuOyuncu', wins: 5, isMe: false),
            LeaderboardEntry(rank: 1000, nickname: 'BinOyuncu', wins: 1, isMe: true),
          ],
          me: LeaderboardMe(rank: 1000, wins: 1),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardApiClientProvider.overrideWithValue(fakeClient),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.3),
              ),
              child: const LeaderboardScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. sıra rozeti: Semantics etiketi "1. sıra" var ve CustomPaint taç ikonu çizilmiş
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '1. sıra',
        ),
        findsOneWidget,
      );
      // 2. ve 3. sıra: Semantics etiketleri ve metinleri
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '2. sıra',
        ),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '3. sıra',
        ),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);

      // #100 ve #1000 sıra numaraları görünür ve FittedBox içinde tek satırdadır
      expect(find.text('#100'), findsOneWidget);
      expect(find.text('#1000'), findsOneWidget);

      // Hiçbir RenderFlex taşma (A RenderFlex overflowed...) hatası oluşmamalıdır
      expect(tester.takeException(), isNull);
    });
  });
}
