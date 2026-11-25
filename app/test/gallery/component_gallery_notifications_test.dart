import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/achievements/application/achievement_notification_service.dart';
import 'package:app/features/achievements/presentation/achievement_notification_card.dart';
import 'package:app/features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import 'package:app/features/match_request/presentation/widgets/match_request_toast.dart';
import 'package:app/features/match_request/presentation/widgets/outgoing_match_request_chip.dart';
import 'package:app/gallery/component_gallery.dart';

void main() {
  group('ComponentGallery Notifications Section Widget Tests', () {
    testWidgets('NotificationsGallerySection tüm banner, çip, tost ve başarım bileşenlerini başarıyla sergiler', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NotificationsGallerySection(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // a) Gelen Maç İsteği Bildirim Bandı
      expect(find.byType(IncomingMatchRequestBanner), findsOneWidget);
      expect(find.text('a) Gelen Maç İsteği Bandı (IncomingMatchRequestBanner)'), findsOneWidget);

      // b) Giden Maç İsteği Bilgi Çipi
      expect(find.byType(OutgoingMatchRequestChip), findsOneWidget);

      // c) Maç İsteği Tostları (tüm varyantlar)
      expect(find.byType(MatchRequestToastWidget), findsWidgets);
      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.text('Zaman Aşımı'), findsOneWidget);
      expect(find.text('Müsait Değil'), findsOneWidget);
      expect(find.text('Çevrimdışı'), findsOneWidget);

      // d) Bağlantı Bandı kontrolleri
      expect(find.text('Yeniden Bağlanıyor'), findsOneWidget);
      expect(find.text('Tekrar Bağlandı (Pill)'), findsOneWidget);

      // e) Başarım Bildirimi önizleme kartı ve kontrolleri
      expect(find.byType(AchievementNotificationCard), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(11));
      expect(find.text("3'lü Seri Başarım Göster (FIFO Kuyruk Testi)"), findsOneWidget);

      // f) Sistem Uyarıları
      expect(find.text('Bilgi SnackBar Göster'), findsOneWidget);
      expect(find.text('Hata SnackBar Göster'), findsOneWidget);

      // Özet kutusu metni
      expect(find.text('Listelenen Bildirim Türleri Özeti:'), findsOneWidget);
    });

    testWidgets('Galeride first_match, first_win ve wins_10 başarım kartları başarıyla seçilip görüntülenir', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NotificationsGallerySection(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Başlangıçta first_match ('İlk Adım') seçilidir ve alt kenara hizalı/dönmesiz yerleşir
      expect(find.text('İlk Adım'), findsWidgets);
      final previewCardPositioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byType(AchievementNotificationCard),
          matching: find.byType(Positioned),
        ),
      );
      expect(previewCardPositioned.left, equals(4.0));
      expect(previewCardPositioned.top, isNull);
      expect(previewCardPositioned.bottom, equals(0.0));
      final previewCardTransform = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(AchievementNotificationCard),
          matching: find.byType(Transform),
        ),
      ).first;
      expect(previewCardTransform.transform.storage[0], closeTo(1.0, 0.0001));

      // 2. 'İlk Zafer' (first_win) çipine dokun
      await tester.tap(find.widgetWithText(ChoiceChip, 'İlk Zafer'));
      await tester.pumpAndSettle();
      expect(find.text('İlk Zafer'), findsWidgets);
      expect(find.text('İlk galibiyetini al'), findsOneWidget);
      final firstWinPositioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byType(AchievementNotificationCard),
          matching: find.byType(Positioned),
        ),
      );
      expect(firstWinPositioned.left, equals(-6.0));
      expect(firstWinPositioned.top, equals(0.0));
      expect(firstWinPositioned.bottom, equals(0.0));

      // 3. 'Yükselen Yıldız' (wins_10) çipine dokun
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yükselen Yıldız'));
      await tester.pumpAndSettle();
      expect(find.text('Yükselen Yıldız'), findsWidgets);
      expect(find.text('10 galibiyet al'), findsOneWidget);
      final wins10Positioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byType(AchievementNotificationCard),
          matching: find.byType(Positioned),
        ),
      );
      expect(wins10Positioned.left, equals(-14.0));
      expect(wins10Positioned.top, equals(0.0));
      expect(wins10Positioned.bottom, equals(0.0));
    });

    testWidgets('3\'lü seri başarım butonu FIFO kuyruğu doğru sırayla tetikler', (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NotificationsGallerySection(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Butona dokun
      final buttonFinder = find.text("3'lü Seri Başarım Göster (FIFO Kuyruk Testi)");
      await tester.tap(buttonFinder);
      await tester.pump();

      final notifier = container.read(achievementNotificationProvider.notifier);
      final state = container.read(achievementNotificationProvider);

      expect(state.currentItem, isNotNull);
      expect(state.currentItem!.id, equals('streak_3'));
      expect(notifier.queueLength, equals(2));
    });

    testWidgets('ComponentGallery içinde Bildirimler bölümü yer alır', (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ComponentGallery(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(NotificationsGallerySection), findsOneWidget);
      expect(
        find.text('BİLDİRİMLER (BANNER, ÇİP, TOST & BAŞARIM BİLDİRİMLERİ)'),
        findsOneWidget,
      );
    });

    testWidgets('Bileşen galerisinde yasaklı kelimeler (bot, yapay zeka, alıştırma maçı) geçmez', (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ComponentGallery(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final text in textWidgets) {
        final content = text.data?.toLowerCase() ?? '';
        expect(content.contains('bot'), isFalse, reason: 'Yasaklı "bot" ifadesi: $content');
        expect(content.contains('yapay zeka'), isFalse, reason: 'Yasaklı "yapay zeka" ifadesi: $content');
        expect(content.contains('alıştırma'), isFalse, reason: 'Yasaklı "alıştırma" ifadesi: $content');
      }
    });
  });
}
