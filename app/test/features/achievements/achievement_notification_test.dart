import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/achievements/application/achievement_notification_service.dart';
import 'package:app/features/achievements/domain/achievement_ui_manifest.dart';
import 'package:app/features/achievements/presentation/achievement_notification_card.dart';
import 'package:app/features/achievements/presentation/achievement_notification_overlay.dart';
import 'package:app/features/match_request/presentation/global_match_request_overlay.dart';

void main() {
  group('AchievementNotificationCard Visual & Interaction Tests', () {
    testWidgets('1. Kart görsel özellikleri: 3px çerçeve, 4px sert gölge, 20px radius, sol taşan -6° SVG, 58px sol boşluk', (tester) async {
      final item = AchievementUiManifest.get('first_win')!;
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AchievementNotificationCard(
                item: item,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );

      // Başlık ve açıklama
      expect(find.text('İlk Zafer'), findsOneWidget);
      expect(find.text('İlk galibiyetini al'), findsOneWidget);

      // "BAŞARIM AÇILDI" rozeti veya sayaç çubuğu OLMAMALIDIR
      expect(find.text('BAŞARIM AÇILDI'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // SVG ikon ColorFilter OLMADAN yüklenmelidir
      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);

      // Kart kutusu tasarımı doğrulaması
      final containers = tester.widgetList<Container>(find.byType(Container));
      final cardContainer = containers.firstWhere((c) {
        final d = c.decoration;
        if (d is BoxDecoration) {
          return d.border != null && d.borderRadius == BorderRadius.circular(20);
        }
        return false;
      });

      final boxDecoration = cardContainer.decoration as BoxDecoration;
      expect(boxDecoration.color, equals(AppColors.card));
      expect(boxDecoration.border!.top.width, equals(3));
      expect(boxDecoration.border!.top.color, equals(AppColors.ink));

      // 4px ofsetli gölge
      expect(boxDecoration.boxShadow, isNotEmpty);
      expect(boxDecoration.boxShadow!.first.offset, equals(const Offset(0, 4)));
      expect(boxDecoration.boxShadow!.first.color, equals(AppColors.ink));

      // Sol iç boşluk 58px (ikona çarpmaması için)
      final edgeInsets = cardContainer.padding as EdgeInsets;
      expect(edgeInsets.left, greaterThanOrEqualTo(56));

      // Dokunulduğunda onDismiss tetiklenmelidir
      await tester.tap(find.byType(AchievementNotificationCard));
      expect(dismissed, isTrue);
    });

    testWidgets('2. Yukarı doğru kaydırıldığında (swipe up) hemen onDismiss tetiklenir', (tester) async {
      final item = AchievementUiManifest.get('streak_3')!;
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AchievementNotificationCard(
                item: item,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );

      // Yukarı doğru hızlıca kaydır
      await tester.fling(
        find.byType(AchievementNotificationCard),
        const Offset(0, -300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('3. Yasaklı kelimeler (bot, yapay zeka, alıştırma maçı) kartta geçmez', (tester) async {
      for (final item in AchievementUiManifest.items.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AchievementNotificationCard(
                item: item,
                onDismiss: () {},
              ),
            ),
          ),
        );

        final textWidgets = tester.widgetList<Text>(find.byType(Text));
        for (final text in textWidgets) {
          final content = text.data?.toLowerCase() ?? '';
          expect(content.contains('bot'), isFalse);
          expect(content.contains('yapay zeka'), isFalse);
          expect(content.contains('alıştırma'), isFalse);
        }
      }
    });

    testWidgets('4. Rozet konumu ve açısı item ve override parametreleriyle ayarlanabilir', (tester) async {
      Transform findBadgeTransform() {
        return tester.widgetList<Transform>(
          find.descendant(
            of: find.byType(AchievementNotificationCard),
            matching: find.byType(Transform),
          ),
        ).first;
      }

      Positioned findBadgePositioned() {
        return tester.widget<Positioned>(
          find.descendant(
            of: find.byType(AchievementNotificationCard),
            matching: find.byType(Positioned),
          ),
        );
      }

      // first_win için varsayılan: badgeDx: -6, badgeRotationDeg: -6
      final firstWin = AchievementUiManifest.get('first_win')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementNotificationCard(item: firstWin),
          ),
        ),
      );

      final positioned1 = findBadgePositioned();
      expect(positioned1.left, equals(-6.0));
      final transform1 = findBadgeTransform();
      // -6° in radians = -6 * pi / 180 ≈ -0.1047 -> cos(-6°) ≈ 0.9945
      expect(transform1.transform.storage[0], closeTo(0.9945, 0.001));

      // wins_10 için: badgeDx: -14, badgeRotationDeg: -12
      final wins10 = AchievementUiManifest.get('wins_10')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementNotificationCard(item: wins10),
          ),
        ),
      );
      final positioned2 = findBadgePositioned();
      expect(positioned2.left, equals(-14.0));
      final transform2 = findBadgeTransform();
      // -12° in radians: cos(-12°) ≈ 0.9781
      expect(transform2.transform.storage[0], closeTo(0.9781, 0.001));

      // Override parametreleri
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementNotificationCard(
              item: firstWin,
              badgeDx: -25.0,
              badgeRotationDeg: -18.0,
            ),
          ),
        ),
      );
      final positioned3 = findBadgePositioned();
      expect(positioned3.left, equals(-25.0));
      final transform3 = findBadgeTransform();
      // cos(-18°) ≈ 0.9510
      expect(transform3.transform.storage[0], closeTo(0.9510, 0.001));
    });
  });

  group('AchievementNotificationNotifier & FIFO Queue Tests', () {
    test('Birden fazla başarım açıldığında FIFO kuyruk sırasıyla gösterilir', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(achievementNotificationProvider.notifier);

      // 3 başarım sıraya al
      notifier.showAll(['streak_3', 'matches_10', 'first_win']);

      // İlk başarım hemen aktiftir
      var state = container.read(achievementNotificationProvider);
      expect(state.currentItem, isNotNull);
      expect(state.currentItem!.id, equals('streak_3'));
      expect(notifier.queueLength, equals(2));

      // İlk başarım kapatılır
      notifier.dismissCurrent();
      expect(container.read(achievementNotificationProvider).currentItem, isNull);

      // 250ms geçiş süresi beklenir
      // Notifier'ın transitionTimer'ını test etmek için timer çalışması beklenir
    });

    test('Tekrarlanan kimlikler (deduplication) elenir', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(achievementNotificationProvider.notifier);

      notifier.showAll(['streak_3', 'streak_3', 'first_match', 'streak_3']);

      expect(container.read(achievementNotificationProvider).currentItem!.id, equals('streak_3'));
      expect(notifier.queueLength, equals(1)); // Sadece 'first_match' kuyrukta kalır
    });

    test('Bilinmeyen kimlikler sessizce yoksayılır, uygulama çökmez', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(achievementNotificationProvider.notifier);

      notifier.showAll(['unknown_achievement_xyz']);
      expect(container.read(achievementNotificationProvider).currentItem, isNull);
      expect(notifier.queueLength, equals(0));
    });

    test('clearQueue tüm bekleyen kuyruğu ve aktif bildirimi temizler', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(achievementNotificationProvider.notifier);

      notifier.showAll(['first_match', 'first_win', 'streak_5']);
      expect(container.read(achievementNotificationProvider).currentItem, isNotNull);
      expect(notifier.queueLength, equals(2));

      notifier.clearQueue();
      expect(container.read(achievementNotificationProvider).currentItem, isNull);
      expect(notifier.queueLength, equals(0));
    });
  });

  group('AchievementNotificationOverlay Widget & Animation Tests', () {
    testWidgets('Overlay başlangıçta boştur, başarım gelince üstten kayarak görünür', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GlobalMatchRequestOverlay(
              child: Scaffold(
                body: Text('Ana İçerik'),
              ),
            ),
          ),
        ),
      );

      // Başlangıçta bildirim kartı yoktur
      expect(find.byType(AchievementNotificationCard), findsNothing);

      // Başarım tetikle
      container.read(achievementNotificationProvider.notifier).show('first_win');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Kart artık ekranda
      expect(find.byType(AchievementNotificationCard), findsOneWidget);
      expect(find.text('İlk Zafer'), findsOneWidget);

      // Dokunarak kapat
      await tester.tap(find.byType(AchievementNotificationCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AchievementNotificationCard), findsNothing);
    });

    testWidgets('Kullanıcı dokunmazsa 4000ms sonra kendiliğinden kapanır', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GlobalMatchRequestOverlay(
              child: Scaffold(
                body: Text('Ana İçerik'),
              ),
            ),
          ),
        ),
      );

      container.read(achievementNotificationProvider.notifier).show('first_match');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AchievementNotificationCard), findsOneWidget);

      // 4000ms sürenin dolmasını bekle
      await tester.pump(const Duration(milliseconds: 4000));
      // Kapanış animasyonunu bekle (250ms)
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AchievementNotificationCard), findsNothing);
    });
  });
}
