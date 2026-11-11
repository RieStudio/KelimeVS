import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/match_tip_card.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/friend_match/data/friend_match_client.dart';
import 'package:app/features/friend_match/presentation/friend_duel_bottom_sheet.dart';
import 'package:app/features/friend_match/presentation/friend_host_screen.dart';
import 'package:app/features/friend_match/presentation/friend_join_screen.dart';
import 'package:app/features/game/presentation/match_screen.dart';

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

Widget _buildBottomSheetHostApp() {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: true,
                  enableDrag: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FriendDuelBottomSheet(),
                );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    ),
  );
}

class MockFriendMatchClient implements FriendMatchClient {
  final StreamController<FriendMatchEvent> _controller =
      StreamController<FriendMatchEvent>.broadcast();

  String? createdName;
  String? resumedCode;
  String? joinedCode;
  String? joinedName;
  String? cancelledCode;

  @override
  Stream<FriendMatchEvent> get events => _controller.stream;

  @override
  Future<void> createRoom({String? name}) async {
    createdName = name;
  }

  @override
  Future<void> resumeRoom(String code) async {
    resumedCode = code;
  }

  @override
  Future<void> joinRoom(String code, {String? name}) async {
    joinedCode = code;
    joinedName = name;
  }

  @override
  Future<void> cancelRoom({String? code}) async {
    cancelledCode = code;
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emit(FriendMatchEvent event) {
    _controller.add(event);
  }
}

void main() {
  group('FriendDuelBottomSheet Widget Tests', () {
    testWidgets(
        '1. BottomSheet başlığı sola hizalı gösterir, kapatma (X) butonu yoktur ve iki SVG ikonu çerçevesiz görünür',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FriendDuelBottomSheet(),
            ),
          ),
        ),
      );

      // Başlık ve alt başlık
      expect(find.text(AppStrings.friendDuel), findsOneWidget);
      expect(find.text(AppStrings.friendDuelSubtitle), findsOneWidget);

      // Kapatma (X) butonu bulunmaz
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byType(IconButton), findsNothing);

      // Kart seçenekleri
      expect(find.text(AppStrings.createRoom), findsOneWidget);
      expect(find.text(AppStrings.createRoomSubtitle), findsOneWidget);
      expect(find.text(AppStrings.joinRoom), findsOneWidget);
      expect(find.text(AppStrings.joinRoomSubtitle), findsOneWidget);

      // Eski ikon kutuları ve ikonlar bulunmaz
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.key_rounded), findsNothing);

      // İki SVG ikonu çerçevesiz ve 56 dp boyutunda gösterilir
      final createSvgFinder = findSvgAsset(FriendDuelBottomSheet.createRoomAsset);
      final joinSvgFinder = findSvgAsset(FriendDuelBottomSheet.joinRoomAsset);
      expect(createSvgFinder, findsOneWidget);
      expect(joinSvgFinder, findsOneWidget);

      final createSvg = tester.widget<SvgPicture>(createSvgFinder);
      final joinSvg = tester.widget<SvgPicture>(joinSvgFinder);
      expect(createSvg.width, FriendDuelBottomSheet.iconSize);
      expect(createSvg.height, FriendDuelBottomSheet.iconSize);
      expect(joinSvg.width, FriendDuelBottomSheet.iconSize);
      expect(joinSvg.height, FriendDuelBottomSheet.iconSize);

      // Erişilebilirlik: İkonlar ExcludeSemantics ile sarılı olmalıdır
      expect(
        find.ancestor(of: createSvgFinder, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: joinSvgFinder, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
    });

    testWidgets('1b. "Oda Kur" kartına dokunulduğunda modal kapanır ve FriendHostScreen açılır',
        (tester) async {
      await tester.pumpWidget(_buildBottomSheetHostApp());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsOneWidget);

      await tester.tap(find.text(AppStrings.createRoom));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsNothing);
      expect(find.byType(FriendHostScreen), findsOneWidget);
    });

    testWidgets('1c. "Koda Katıl" kartına dokunulduğunda modal kapanır ve FriendJoinScreen açılır',
        (tester) async {
      await tester.pumpWidget(_buildBottomSheetHostApp());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsOneWidget);

      await tester.tap(find.text(AppStrings.joinRoom));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsNothing);
      expect(find.byType(FriendJoinScreen), findsOneWidget);
    });

    testWidgets('1d. Modal pencere dışına dokunulduğunda (barrier tap) kapanır',
        (tester) async {
      await tester.pumpWidget(_buildBottomSheetHostApp());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsOneWidget);

      // Modal dışındaki üst alana dokun
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsNothing);
    });

    testWidgets('1e. Modal aşağı sürüklendiğinde (drag down) kapanır',
        (tester) async {
      await tester.pumpWidget(_buildBottomSheetHostApp());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsOneWidget);

      // Başlık veya tutamaç üzerinden aşağı kaydır
      await tester.drag(find.text(AppStrings.friendDuel), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsNothing);
    });
  });

  group('FriendHostScreen Widget Tests', () {
    late MockFriendMatchClient mockClient;

    setUp(() {
      mockClient = MockFriendMatchClient();
    });

    testWidgets('2. Oda oluşturulunca kod ekranda gösterilir ve kopyalanabilir',
        (tester) async {
      // Pano verisini mockla
      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          log.add(methodCall);
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FriendHostScreen(client: mockClient),
          ),
        ),
      );

      // Başlangıçta yükleniyor gösterir
      expect(find.text(AppStrings.creatingRoom), findsOneWidget);

      // Sunucudan oda kuruldu olayı gelsin
      mockClient.emit(
        FriendMatchRoomCreated(
          code: 'K7M9P2',
          expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
        ),
      );

      await tester.pumpAndSettle();

      // Kod ekranda görünür
      expect(find.text('K7M9P2'), findsOneWidget);
      expect(find.text(AppStrings.shareCode), findsOneWidget);
      expect(find.text(AppStrings.waitingForOpponent), findsOneWidget);
      expect(find.byType(MatchTipCard), findsOneWidget);
      expect(find.text(AppStrings.searchTipTitle), findsOneWidget);

      // Kopyalama düğmesine bas
      await tester.tap(find.byKey(const Key('copy_invite_code_button')));
      await tester.pump();

      // Panoya kopyalandı mesajı görünür
      expect(find.text(AppStrings.codeCopied), findsOneWidget);
    });

    testWidgets('3. matched olayı geldiğinde MatchScreen sayfasına geçiş yapar',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FriendHostScreen(client: mockClient),
          ),
        ),
      );

      mockClient.emit(
        FriendMatchRoomCreated(
          code: 'K7M9P2',
          expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
        ),
      );
      await tester.pumpAndSettle();

      // Rakip katıldı
      mockClient.emit(
        const FriendMatchMatched(
          matchId: 'friend_match_123',
          opponentName: 'Ahmet',
        ),
      );

      await tester.pumpAndSettle();

      // MatchScreen'e geçmiş olmalıdır
      expect(find.byType(MatchScreen), findsOneWidget);
    });

    testWidgets('3b. İpucu kartı initState içinde bir kez seçilir ve nokta animasyonlarında değişmez',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FriendHostScreen(client: mockClient),
          ),
        ),
      );

      mockClient.emit(
        FriendMatchRoomCreated(
          code: 'K7M9P2',
          expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
        ),
      );
      await tester.pumpAndSettle();

      final tipCardFinder = find.byType(MatchTipCard);
      expect(tipCardFinder, findsOneWidget);
      final tipBefore = tester.widget<MatchTipCard>(tipCardFinder).tip;
      expect(tipBefore, isNotEmpty);

      // 3 nokta animasyonunun tetiklediği setState'ler
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      final tipAfter = tester.widget<MatchTipCard>(tipCardFinder).tip;
      expect(tipAfter, equals(tipBefore));
    });
  });

  group('FriendJoinScreen Widget Tests', () {
    late MockFriendMatchClient mockClient;

    setUp(() {
      mockClient = MockFriendMatchClient();
    });

    testWidgets('4. Kod giriş alanı sadece 6 geçerli karakter kabul eder ve butonu aktifleştirir',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FriendJoinScreen(client: mockClient),
          ),
        ),
      );

      final buttonFinder = find.byKey(const Key('friend_join_button'));
      final inputFinder = find.byKey(const Key('friend_code_input_field'));

      // Başlangıçta Katıl butonu pasiftir
      final initialButton = tester.widget<PrimaryButton>(buttonFinder);
      expect(initialButton.onPressed, isNull);

      // Geçersiz harfler (A, E, 0, 1) yazmayı dene -> filtrelenmeli
      await tester.enterText(inputFinder, 'ae01bcdf');
      await tester.pump();

      // Sadece BCDF kalmalı (4 karakter)
      expect(tester.widget<TextField>(inputFinder).controller?.text, 'BCDF');

      // 6 karaktere tamamla
      await tester.enterText(inputFinder, 'BCDFGH');
      await tester.pump();

      expect(tester.widget<TextField>(inputFinder).controller?.text, 'BCDFGH');

      // Buton aktifleşti
      final enabledButton = tester.widget<PrimaryButton>(buttonFinder);
      expect(enabledButton.onPressed, isNotNull);

      // Katıl butonuna bas
      await tester.tap(buttonFinder);
      await tester.pump();

      expect(mockClient.joinedCode, 'BCDFGH');
    });

    testWidgets('5. Hata durumunda Türkçe anlaşılır hata mesajı gösterilir',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FriendJoinScreen(client: mockClient),
          ),
        ),
      );

      final buttonFinder = find.byKey(const Key('friend_join_button'));
      final inputFinder = find.byKey(const Key('friend_code_input_field'));

      await tester.enterText(inputFinder, 'BCDFGH');
      await tester.pump();
      await tester.tap(buttonFinder);
      await tester.pump();

      // Sunucudan oda bulunamadı hatası gelsin
      mockClient.emit(
        const FriendMatchFailed(
          code: 'room_not_found',
          message: 'Bu oda bulunamadı veya süresi dolmuş.',
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.roomNotFound), findsOneWidget);
    });
  });
}
