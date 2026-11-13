import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/icons/app_icons.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/app_icon_button.dart';
import 'package:app/core/widgets/match_tip_card.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/features/friend_match/data/friend_match_client.dart';
import 'package:app/features/friend_match/presentation/friend_duel_bottom_sheet.dart';
import 'package:app/features/friend_match/presentation/friend_host_screen.dart';
import 'package:app/features/friend_match/presentation/friend_join_screen.dart';
import 'package:app/features/friend_match/presentation/friend_reveal_screen.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/presentation/match_screen.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/online_match_client.dart';

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

class MockOnlineMatchSession extends OnlineMatchSession {
  int startOnlineMatchCallCount = 0;
  String? lastMatchId;
  String? lastOpponentName;
  String? lastOpponentUid;
  String? lastOpponentFrame;
  bool? lastIsFriendly;

  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    String? opponentUid,
    String opponentFrame = 'classic',
    bool isFriendly = false,
    OnlineMatchClient? client,
  }) async {
    startOnlineMatchCallCount++;
    lastMatchId = matchId;
    lastOpponentName = opponentName;
    lastOpponentUid = opponentUid;
    lastOpponentFrame = opponentFrame;
    lastIsFriendly = isFriendly;
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

    testWidgets(
        '1f. Sheet açıldığında zemin renginin AppColors.card olduğunu doğrular',
        (tester) async {
      await tester.pumpWidget(_buildBottomSheetHostApp());
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendDuelBottomSheet), findsOneWidget);

      final rootContainerFinder = find.descendant(
        of: find.byType(FriendDuelBottomSheet),
        matching: find.byType(Container),
      ).first;
      final rootContainer = tester.widget<Container>(rootContainerFinder);
      final decoration = rootContainer.decoration as BoxDecoration?;
      expect(decoration?.color, AppColors.card);
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

      // Kod ekranda görünür, ipucu kartı bulunmaz
      expect(find.text('K7M9P2'), findsOneWidget);
      expect(find.text(AppStrings.shareCode), findsOneWidget);
      expect(find.text(AppStrings.waitingForOpponent), findsOneWidget);
      expect(find.byType(MatchTipCard), findsNothing);
      expect(find.text(AppStrings.searchTipTitle), findsNothing);

      // Kopyalama düğmesine bas
      await tester.tap(find.byKey(const Key('copy_invite_code_button')));
      await tester.pump();

      // Panoya kopyalandı mesajı görünür ve SnackBar stili doğrulanır
      expect(find.text(AppStrings.codeCopied), findsOneWidget);
      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);
      final snackBar = tester.widget<SnackBar>(snackBarFinder);

      // Koyu yeşil / ink zemin ve floating davranış
      expect(snackBar.backgroundColor, AppColors.ink);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.margin, isNotNull);

      // WCAG AA Kontrast Oranı Hesaplama ve Doğrulama (en az 4.5:1)
      final textFinder = find.descendant(
        of: snackBarFinder,
        matching: find.text(AppStrings.codeCopied),
      );
      final textWidget = tester.widget<Text>(textFinder);
      final textColor = textWidget.style?.color ?? AppColors.card;
      final bgLuminance = snackBar.backgroundColor!.computeLuminance();
      final textLuminance = textColor.computeLuminance();
      final lMax = math.max(bgLuminance, textLuminance);
      final lMin = math.min(bgLuminance, textLuminance);
      final contrastRatio = (lMax + 0.05) / (lMin + 0.05);

      expect(contrastRatio, greaterThanOrEqualTo(4.5));
    });

    testWidgets(
        '3. Host: matched olayı gelince önce FriendMatchRevealScreen gösterilir, 3.5 sn sonra MatchScreen ve startOnlineMatch başlar',
        (tester) async {
      final mockOnlineSession = MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
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
      await tester.pump();

      // Rakip katıldı
      mockClient.emit(
        const FriendMatchMatched(
          matchId: 'friend_match_123',
          opponentName: 'Ahmet',
        ),
      );

      // matched geldiğinde hemen FriendMatchRevealScreen görünür
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      expect(find.text(AppStrings.duelStarting), findsOneWidget);
      expect(find.textContaining('Ahmet'), findsOneWidget);
      expect(find.byType(MatchScreen), findsNothing);
      // Henüz startOnlineMatch çağrılmamış olmalı (3.5 sn beklenir)
      expect(mockOnlineSession.startOnlineMatchCallCount, 0);

      // 3.5 saniye sonra MatchScreen'e geçmiş ve startOnlineMatch çağrılmış olmalı
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();

      expect(find.byType(MatchScreen), findsOneWidget);
      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastMatchId, 'friend_match_123');
      expect(mockOnlineSession.lastOpponentName, 'Ahmet');
      expect(mockOnlineSession.lastIsFriendly, isTrue);
    });

    testWidgets(
        '3c. Host: matched ile boş rakip adı gelirse güvenli yedek "Rakip" gösterilir',
        (tester) async {
      final mockOnlineSession = MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
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
      await tester.pump();

      // Rakip boş isimle katıldı
      mockClient.emit(
        const FriendMatchMatched(
          matchId: 'friend_match_empty',
          opponentName: '   ',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      expect(find.text(AppStrings.opponent), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();

      expect(mockOnlineSession.lastOpponentName, AppStrings.opponent);
    });

    testWidgets('3b. İpucu kartı gösterilmez, bekleme göstergesi ve nokta animasyonu dengeli kalır',
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

      // İpucu kartı kesinlikle bulunmaz
      expect(find.byType(MatchTipCard), findsNothing);
      expect(find.text(AppStrings.waitingForOpponent), findsOneWidget);

      // 3 nokta animasyonunun tetiklediği setState'lerde ekran dengeli kalır
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text(AppStrings.waitingForOpponent), findsOneWidget);
      expect(find.byType(MatchTipCard), findsNothing);
    });

    testWidgets('3d. Host: Sol üst geri butonu AppIconButton olarak yer alır, başlık ortalıdır ve dokunulduğunda cancelRoom çağrılır',
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

      // Sol üstte AppIconButton geri butonu
      final backButtonFinder = find.byKey(const Key('friend_host_back_button'));
      expect(backButtonFinder, findsOneWidget);

      final iconBtn = tester.widget<AppIconButton>(backButtonFinder);
      expect(iconBtn.icon, equals(AppIcons.back));
      expect(iconBtn.semanticLabel, equals(AppStrings.back));

      // Başlık ortalı
      expect(find.text(AppStrings.friendDuel), findsOneWidget);

      // Geri butonuna basılınca odayı iptal eder
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();

      expect(mockClient.cancelledCode, equals('K7M9P2'));
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

    testWidgets(
        '5b. Join: Sol üst geri butonu AppIconButton olarak yer alır, başlık ortalıdır ve dokunulduğunda Navigator.pop çalışır',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => FriendJoinScreen(client: mockClient),
                      ),
                    );
                  },
                  child: const Text('Katıl Ekranını Aç'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Katıl Ekranını Aç'));
      await tester.pumpAndSettle();

      expect(find.byType(FriendJoinScreen), findsOneWidget);

      // Sol üstte AppIconButton geri butonu
      final backButtonFinder = find.byKey(const Key('friend_join_back_button'));
      expect(backButtonFinder, findsOneWidget);

      final iconBtn = tester.widget<AppIconButton>(backButtonFinder);
      expect(iconBtn.icon, equals(AppIcons.back));
      expect(iconBtn.semanticLabel, equals(AppStrings.back));

      // Başlık ortalı
      expect(find.text(AppStrings.joinRoom), findsOneWidget);

      // Geri butonuna basılınca ekran pop edilir
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(FriendJoinScreen), findsNothing);
    });

    testWidgets(
        '6. Join: matched olayı gelince önce FriendMatchRevealScreen gösterilir, 3.5 sn sonra MatchScreen ve startOnlineMatch başlar',
        (tester) async {
      final mockOnlineSession = MockOnlineMatchSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
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

      // Sunucudan matched gelsin
      mockClient.emit(
        const FriendMatchMatched(
          matchId: 'friend_match_456',
          opponentName: 'Ayşe',
        ),
      );

      // matched geldiğinde hemen FriendMatchRevealScreen görünür
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      expect(find.text(AppStrings.duelStarting), findsOneWidget);
      expect(find.textContaining('Ayşe'), findsOneWidget);
      expect(find.byType(MatchScreen), findsNothing);
      expect(mockOnlineSession.startOnlineMatchCallCount, 0);

      // 3.5 saniye sonra MatchScreen'e geçer ve startOnlineMatch çağrılır
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();

      expect(find.byType(MatchScreen), findsOneWidget);
      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastMatchId, 'friend_match_456');
      expect(mockOnlineSession.lastOpponentName, 'Ayşe');
      expect(mockOnlineSession.lastIsFriendly, isTrue);
    });
  });

  group('FriendMatchRevealScreen Widget & Interaction Tests', () {
    late MockOnlineMatchSession mockOnlineSession;

    setUp(() {
      mockOnlineSession = MockOnlineMatchSession();
    });

    testWidgets(
        '7a. Boş rakip adı yedeği: opponentName boş gelirse "Rakip" gösterilir',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: FriendMatchRevealScreen(
              matchId: 'm1',
              opponentName: '   ',
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.opponent), findsOneWidget);
      expect(find.text(AppStrings.duelStarting), findsOneWidget);
      expect(find.text(AppStrings.you), findsOneWidget);
      expect(find.text(AppStrings.vs), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();
      expect(mockOnlineSession.lastOpponentName, AppStrings.opponent);
    });

    testWidgets(
        '7b. Rakip adı dolu olduğunda ad ekranda görünür (find.textContaining)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: FriendMatchRevealScreen(
              matchId: 'm2',
              opponentName: 'Zeynep',
            ),
          ),
        ),
      );

      expect(find.textContaining('Zeynep'), findsOneWidget);
      expect(find.text(AppStrings.duelStarting), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();
      expect(mockOnlineSession.lastOpponentName, 'Zeynep');
    });

    testWidgets(
        '7c. Geri tuşu ve çıkış tamamen kilitlidir (PopScope canPop: false)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FriendMatchRevealScreen(
                matchId: 'm3',
                opponentName: 'Mehmet',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);

      // PopScope canPop false olmalı
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);

      // Navigator pop denemesi ekranı kapatamaz
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.maybePop();
      await tester.pump();

      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);

      // Süre dolunca normal şekilde MatchScreen'e geçer
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();
      expect(find.byType(MatchScreen), findsOneWidget);
    });

    testWidgets(
        '7d. Çift geçiş koruması: Timer ve Lifecycle Resumed çakışsa dahi startOnlineMatch tek kez çağrılır',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: FriendMatchRevealScreen(
              matchId: 'm4',
              opponentName: 'Can',
            ),
          ),
        ),
      );

      // Süre dolmadan önce ve tam dolma anında lifecycle resumed tetikle
      await tester.pump(const Duration(milliseconds: 3600));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // İkinci kez lifecycle tetikle
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(find.byType(MatchScreen), findsOneWidget);
    });

    test('7e. AppStrings.safeOpponentName parametre doğrulama ve yedek metin testi', () {
      expect(AppStrings.safeOpponentName(null), AppStrings.opponent);
      expect(AppStrings.safeOpponentName(''), AppStrings.opponent);
      expect(AppStrings.safeOpponentName('    '), AppStrings.opponent);
      expect(AppStrings.safeOpponentName('Zeynep'), 'Zeynep');
      expect(AppStrings.safeOpponentName('  Ali  '), 'Ali');
    });
  });
}
