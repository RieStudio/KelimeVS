import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/leaderboard/application/leaderboard_providers.dart';
import 'package:app/features/leaderboard/data/leaderboard_api_client.dart';
import 'package:app/features/leaderboard/domain/models/leaderboard_models.dart';
import 'package:app/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:app/features/matchmaking/presentation/matchmaking_screen.dart';
import 'package:app/features/online/data/matchmaking_client.dart';
import 'package:app/features/profile/application/profile_notifier.dart';

class _FakeMatchmakingClient extends MatchmakingClient {
  final StreamController<MatchmakingEvent> _controller =
      StreamController<MatchmakingEvent>.broadcast(sync: true);

  @override
  Stream<MatchmakingEvent> get events => _controller.stream;

  @override
  Future<void> start(String name) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _TestProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  _TestProfileNotifier(this._state);

  @override
  ProfileState build() => _state;
}

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
  ProfileState? profileState,
}) {
  return ProviderScope(
    overrides: [
      leaderboardApiClientProvider.overrideWithValue(client),
      matchmakingClientFactoryProvider.overrideWithValue(() => _FakeMatchmakingClient()),
      if (profileState != null)
        profileProvider.overrideWith(
          () => _TestProfileNotifier(profileState),
        ),
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

      // Boş durum kartının kenarlık stilini doğrula: AppColors.ink, borderThin, gölge ve köşe yarıçapı
      final emptyContainer = tester.firstWidget<Container>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_empty')),
          matching: find.byType(Container),
        ),
      );
      final emptyDecoration = emptyContainer.decoration as BoxDecoration;
      expect(emptyDecoration.border?.top.color, AppColors.ink);
      expect(emptyDecoration.border?.top.width, AppDimens.borderThin);
      expect(emptyDecoration.borderRadius, AppDimens.borderRadiusListCard);
      expect(emptyDecoration.boxShadow, AppDimens.shadowQuestionCard);
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

    testWidgets('3. Dolu listede 1., 2. ve 3. sıra rozetleri ve kullanıcı vurgusu (turuncu zemin, ink metin, SEN etiketsiz) doğrulanır',
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

      // Kullanıcı vurgusu: "SEN" metin rozeti kaldırıldı, kart zemini AppColors.selfHighlight oldu
      expect(find.text(AppStrings.you), findsNothing);

      final myDecoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_2')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final boxDecoration = myDecoratedBox.decoration as BoxDecoration;
      expect(boxDecoration.color, AppColors.selfHighlight);

      // Kullanıcının galibiyet metni yeşil yerine AppColors.ink olmalı
      final myWinsText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_2')),
          matching: find.text('12 galibiyet'),
        ),
      );
      expect(myWinsText.style?.color, AppColors.ink);

      // 1. kartın zemini ise AppColors.card (beyaz), galibiyet metni AppColors.primary
      final firstDecoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_1')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final firstDecoration = firstDecoratedBox.decoration as BoxDecoration;
      expect(firstDecoration.color, AppColors.card);

      final firstWinsText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_1')),
          matching: find.text('15 galibiyet'),
        ),
      );
      expect(firstWinsText.style?.color, AppColors.primary);

      // Kullanıcı zaten ilk 100'de olduğu için yapışkan alt çubuk gösterilmez
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsNothing);

      // Çubuk görünmediğinde ListView alt padding'i screenPaddingHorizontal (20.0) olmalı
      final listView = tester.widget<ListView>(find.byKey(const Key('leaderboard_list')));
      final insets = listView.padding as EdgeInsets;
      expect(insets.bottom, AppDimens.screenPaddingHorizontal);
    });

    testWidgets('4. Kullanıcı ilk 100 dışındaysa yapışkan alt çubuk satır kartı düzeninde, turuncu zemin ve ink metinle görünür',
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

      await tester.pumpWidget(
        createLeaderboardScreen(
          client: fakeClient,
          profileState: const ProfileState(nickname: 'BenimNick'),
        ),
      );
      await tester.pumpAndSettle();

      // Yapışkan çubuk görünür
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);

      // "sıradasın" ve "Sen" rozeti KALDIRILDI
      expect(find.textContaining('sıradasın'), findsNothing);
      expect(find.text(AppStrings.you), findsNothing);

      // Sıra, avatar/takma ad ve galibiyet
      expect(find.text('#74'), findsOneWidget);
      expect(find.text('BenimNick'), findsOneWidget);
      expect(find.text('3 galibiyet'), findsOneWidget);

      // Çubuk arka plan rengi AppColors.selfHighlight
      final stickyContainer = tester.widget<Container>(
        find.byKey(const Key('leaderboard_sticky_me')),
      );
      final stickyDecoration = stickyContainer.decoration as BoxDecoration;
      expect(stickyDecoration.color, AppColors.selfHighlight);

      // Galibiyet metni yeşil yerine AppColors.ink olmalı
      final stickyWinsText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_sticky_me')),
          matching: find.text('3 galibiyet'),
        ),
      );
      expect(stickyWinsText.style?.color, AppColors.ink);

      // Çubuk varken ListView alt padding'i 96.0 olmalı (çubuk yüksekliği kadar boşluk)
      final listView = tester.widget<ListView>(find.byKey(const Key('leaderboard_list')));
      final insets = listView.padding as EdgeInsets;
      expect(insets.bottom, 96.0);
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

      await tester.pumpWidget(
        createLeaderboardScreen(
          client: fakeClient,
          profileState: const ProfileState(nickname: 'BenimProfilim'),
        ),
      );
      await tester.pumpAndSettle();

      // Liste ve ilk eleman görünür
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.text('Oyuncu_1'), findsOneWidget);

      // İlk 100 dışındaki kullanıcı için yapışkan çubuk görünür (sıradasın metni yok, nick ve galibiyet var)
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(find.textContaining('sıradasın'), findsNothing);
      expect(find.text('#105'), findsOneWidget);
      expect(find.text('BenimProfilim'), findsOneWidget);
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
      expect(find.textContaining('sıradasın'), findsNothing);
      expect(find.text('#105'), findsOneWidget);
      expect(find.text('BenimProfilim'), findsOneWidget);
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
        '10. İlk 3 rozet (taç, gümüş 2, bronz 3), kullanıcı 1. olsa bile taç korunur ve turuncu zeminle boyanır',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 1, nickname: 'LiderKralBen', wins: 40, isMe: true),
            LeaderboardEntry(rank: 2, nickname: 'IkinciOyuncu', wins: 38, isMe: false),
            LeaderboardEntry(rank: 3, nickname: 'UcuncuOyuncu', wins: 35, isMe: false),
            LeaderboardEntry(rank: 100, nickname: 'YuzuncuOyuncu', wins: 5, isMe: false),
          ],
          me: LeaderboardMe(rank: 1, wins: 40),
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      // 1. sıra rozeti: Kullanıcı 1. olsa bile taç rozeti korunur (Semantics "1. sıra")
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '1. sıra',
        ),
        findsOneWidget,
      );
      // 1. sıradaki kullanıcının kart zemini turuncu (AppColors.selfHighlight) rengindedir
      final firstDecoratedBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_1')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final firstDecoration = firstDecoratedBox.decoration as BoxDecoration;
      expect(firstDecoration.color, AppColors.selfHighlight);

      // Galibiyet metni yeşil yerine AppColors.ink olmalı
      final firstWinsText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('leaderboard_item_1')),
          matching: find.text('40 galibiyet'),
        ),
      );
      expect(firstWinsText.style?.color, AppColors.ink);

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
      expect(find.text('#100'), findsOneWidget);
    });

    testWidgets(
        '11. Dar ekranda (320dp, textScale 1.3) yapışkan çubuk (#1000, uzun isim) ve liste kartlarında taşma (overflow) olmaz',
        (tester) async {
      // 320x640 dar ekran boyutu ve %130 yazı tipi ölçeği
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
            LeaderboardEntry(rank: 1, nickname: 'CokUzunBirOyuncuAdiBirinci', wins: 40, isMe: false),
            LeaderboardEntry(rank: 99, nickname: 'DoksanDokuzuncu', wins: 5, isMe: false),
          ],
          me: LeaderboardMe(rank: 1000, wins: 12),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaderboardApiClientProvider.overrideWithValue(fakeClient),
            profileProvider.overrideWith(
              () => _TestProfileNotifier(
                const ProfileState(nickname: 'CokUzunProfilIsmiKullanicisi'),
              ),
            ),
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

      // Yapışkan çubuk görünür ve bilgileri tamdır
      expect(find.byKey(const Key('leaderboard_sticky_me')), findsOneWidget);
      expect(find.text('#1000'), findsOneWidget);
      expect(find.text('CokUzunProfilIsmiKullanicisi'), findsOneWidget);
      expect(find.text('12 galibiyet'), findsOneWidget);

      // Hiçbir RenderFlex taşma (A RenderFlex overflowed...) hatası oluşmamalıdır
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '12. İlk 100 içinde 3. sıradan sonraki kullanıcı (#12) satırında turuncu zemin ve beyaz #12 rozet gösterilir',
        (tester) async {
      final fakeClient = FakeLeaderboardApiClient(
        dataToReturn: const LeaderboardData(
          weekKey: '2026-W42',
          endsAt: 1792357200000,
          top: [
            LeaderboardEntry(rank: 11, nickname: 'OnBirinci', wins: 22, isMe: false),
            LeaderboardEntry(rank: 12, nickname: 'BenOnIkinci', wins: 21, isMe: true),
          ],
          me: LeaderboardMe(rank: 12, wins: 21),
        ),
      );

      await tester.pumpWidget(createLeaderboardScreen(client: fakeClient));
      await tester.pumpAndSettle();

      final card12 = find.byKey(const Key('leaderboard_item_12'));
      expect(card12, findsOneWidget);

      // Kart zemini canlı turuncu (AppColors.selfHighlight)
      final decoratedBox12 = tester.widget<DecoratedBox>(
        find.descendant(of: card12, matching: find.byType(DecoratedBox)).first,
      );
      expect((decoratedBox12.decoration as BoxDecoration).color, AppColors.selfHighlight);

      // #12 rozeti beyaz zeminli hap içinde ve metni AppColors.ink
      final rank12TextFinder = find.descendant(of: card12, matching: find.text('#12'));
      expect(rank12TextFinder, findsOneWidget);
      expect(tester.widget<Text>(rank12TextFinder).style?.color, AppColors.ink);

      // 12. sıradaki kullanıcının galibiyet metni yeşil yerine AppColors.ink
      final winsText12 = find.descendant(of: card12, matching: find.text('21 galibiyet'));
      expect(winsText12, findsOneWidget);
      expect(tester.widget<Text>(winsText12).style?.color, AppColors.ink);

      // Diğer oyuncunun (11. sıra) kartı ise beyaz zemin, muted sıra metni ve primary galibiyet metnidir
      final card11 = find.byKey(const Key('leaderboard_item_11'));
      final decoratedBox11 = tester.widget<DecoratedBox>(
        find.descendant(of: card11, matching: find.byType(DecoratedBox)).first,
      );
      expect((decoratedBox11.decoration as BoxDecoration).color, AppColors.card);

      final rank11TextFinder = find.descendant(of: card11, matching: find.text('#11'));
      expect(tester.widget<Text>(rank11TextFinder).style?.color, AppColors.muted);

      final winsText11 = find.descendant(of: card11, matching: find.text('22 galibiyet'));
      expect(tester.widget<Text>(winsText11).style?.color, AppColors.primary);
    });

    testWidgets(
      '13. Boş sıralama ekranı -> Hızlı Maç -> Vazgeç -> Sıralama ekranına güvenli dönüş (siyah ekran oluşmaz)',
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

        expect(find.byKey(const Key('leaderboard_empty')), findsOneWidget);
        expect(find.text(AppStrings.quickMatch), findsOneWidget);

        // Hızlı Maç butonuna dokun
        await tester.tap(find.text(AppStrings.quickMatch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Eşleşme ekranı açılmış olmalı
        expect(find.byType(MatchmakingScreen), findsOneWidget);

        // Vazgeç butonuna dokun
        final cancelButton = find.widgetWithText(SecondaryButton, AppStrings.cancel);
        expect(cancelButton, findsOneWidget);
        await tester.tap(cancelButton);
        await tester.pump();
        await tester.pumpAndSettle();

        // MatchmakingScreen kapanmış ve LeaderboardScreen (boş durum) geri gelmiş olmalı (siyah ekran yok)
        expect(find.byType(MatchmakingScreen), findsNothing);
        expect(find.byKey(const Key('leaderboard_screen')), findsOneWidget);
        expect(find.byKey(const Key('leaderboard_empty')), findsOneWidget);
      },
    );

    testWidgets(
      '14. Boş sıralama ekranı -> Hızlı Maç -> Sistem geri hareketi -> Sıralama ekranına güvenli dönüş',
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

        // Hızlı Maç butonuna dokun
        await tester.tap(find.text(AppStrings.quickMatch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(MatchmakingScreen), findsOneWidget);

        // Sistem geri hareketini simüle et
        final didPop = await tester.binding.handlePopRoute();
        expect(didPop, isTrue);
        await tester.pump();
        await tester.pumpAndSettle();

        // MatchmakingScreen kapanmış ve LeaderboardScreen geri gelmiş olmalı
        expect(find.byType(MatchmakingScreen), findsNothing);
        expect(find.byKey(const Key('leaderboard_screen')), findsOneWidget);
        expect(find.byKey(const Key('leaderboard_empty')), findsOneWidget);
      },
    );
  });
}
