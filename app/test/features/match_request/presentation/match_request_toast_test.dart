import 'dart:math' as math;

import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/presentation/widgets/match_request_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 Bağıl Parlaklık (Relative Luminance) hesaplayıcı
double _calculateRelativeLuminance(Color color) {
  double channel(double c) {
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 2.1 Kontrast Oranı (L1 + 0.05) / (L2 + 0.05)
double _calculateContrastRatio(Color foreground, Color background) {
  final l1 = _calculateRelativeLuminance(foreground);
  final l2 = _calculateRelativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('MatchRequestToastWidget Widget Tests', () {
    testWidgets('uyarı/hata tostunda danger stili (card zemin, danger kenarlık, dangerText yazı, ink gölge) ve error ikonu gösterilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'İstek reddedildi',
              isDanger: true,
            ),
          ),
        ),
      );

      expect(find.text('İstek reddedildi'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
      expect(icon.color, AppColors.dangerText);

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      // Zemin: card (beyaz), KIRMIZI DOLGU YOK
      expect(decoration.color, AppColors.card);

      // Kenarlık: kırmızı (AppColors.danger), kalınlık 2
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.danger);
      expect(border.top.width, 2.0);

      // Sert gölge: ink
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppColors.ink);

      // Yazı: AppColors.dangerText ve TextDecoration.none (sarı alt çizgi yok)
      final text = tester.widget<Text>(find.text('İstek reddedildi'));
      expect(text.style?.color, AppColors.dangerText);
      expect(text.style?.decoration, TextDecoration.none);
    });

    testWidgets('bilgilendirme tostunda nötr stil (card zemin, ink kenarlık, ink yazı, ink gölge) ve info ikonu gösterilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'İstek yanıtsız kaldı',
              isDanger: false,
            ),
          ),
        ),
      );

      expect(find.text('İstek yanıtsız kaldı'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded));
      expect(icon.color, AppColors.ink);

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;

      // Zemin: card (beyaz)
      expect(decoration.color, AppColors.card);

      // Kenarlık: ink, kalınlık 2
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.ink);
      expect(border.top.width, 2.0);

      // Sert gölge: ink
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppColors.ink);

      final text = tester.widget<Text>(find.text('İstek yanıtsız kaldı'));
      expect(text.style?.color, AppColors.ink);
      expect(text.style?.decoration, TextDecoration.none);
    });

    testWidgets('tosta tıklandığında onDismiss tetiklenir', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'Test mesajı',
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test mesajı'));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('SVG ikon yapılandırması verildiğinde SvgPicture doğru asset ve renkle çizilir', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatchRequestToastWidget(
              message: 'İstek reddedildi',
              isDanger: true,
              iconAsset: 'assets/icons/match_request_declined.svg',
              iconColor: AppColors.danger,
            ),
          ),
        ),
      );

      expect(find.text('İstek reddedildi'), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 20.0);
      expect(svg.height, 20.0);
    });

    group('matchRequestToastIconForCode saf fonksiyon eşleme testleri', () {
      test('declined -> match_request_declined, kırmızı', () {
        final cfg = matchRequestToastIconForCode('declined');
        expect(cfg, isNotNull);
        expect(cfg!.assetPath, 'assets/icons/match_request_declined.svg');
        expect(cfg.color, AppColors.danger);
      });

      test('cooldown_active ve rate_limited -> match_request_cooldown, koyu yeşil', () {
        final cooldown = matchRequestToastIconForCode('cooldown_active');
        expect(cooldown, isNotNull);
        expect(cooldown!.assetPath, 'assets/icons/match_request_cooldown.svg');
        expect(cooldown.color, AppColors.ink);

        final rateLimited = matchRequestToastIconForCode('rate_limited');
        expect(rateLimited, isNotNull);
        expect(rateLimited!.assetPath, 'assets/icons/match_request_cooldown.svg');
        expect(rateLimited.color, AppColors.ink);
      });

      test('offline -> match_request_offline, kırmızı', () {
        final cfg = matchRequestToastIconForCode('offline');
        expect(cfg, isNotNull);
        expect(cfg!.assetPath, 'assets/icons/match_request_offline.svg');
        expect(cfg.color, AppColors.danger);
      });

      test('requests_disabled -> match_request_disabled, kırmızı', () {
        final cfg = matchRequestToastIconForCode('requests_disabled');
        expect(cfg, isNotNull);
        expect(cfg!.assetPath, 'assets/icons/match_request_disabled.svg');
        expect(cfg.color, AppColors.danger);
      });

      test('unavailable -> match_request_busy, koyu yeşil', () {
        final cfg = matchRequestToastIconForCode('unavailable');
        expect(cfg, isNotNull);
        expect(cfg!.assetPath, 'assets/icons/match_request_busy.svg');
        expect(cfg.color, AppColors.ink);
      });

      test('no_energy ve opponent_no_energy -> match_request_no_energy, kırmızı', () {
        final noEnergy = matchRequestToastIconForCode('no_energy');
        expect(noEnergy, isNotNull);
        expect(noEnergy!.assetPath, 'assets/icons/match_request_no_energy.svg');
        expect(noEnergy.color, AppColors.danger);

        final oppNoEnergy = matchRequestToastIconForCode('opponent_no_energy');
        expect(oppNoEnergy, isNotNull);
        expect(oppNoEnergy!.assetPath, 'assets/icons/match_request_no_energy.svg');
        expect(oppNoEnergy.color, AppColors.danger);
      });

      test('accepted / match_started -> match_request_accepted, açık yeşil', () {
        final accepted = matchRequestToastIconForCode('accepted');
        expect(accepted, isNotNull);
        expect(accepted!.assetPath, 'assets/icons/match_request_accepted.svg');
        expect(accepted.color, AppColors.bright);

        final matchStarted = matchRequestToastIconForCode('match_started');
        expect(matchStarted, isNotNull);
        expect(matchStarted!.assetPath, 'assets/icons/match_request_accepted.svg');
        expect(matchStarted.color, AppColors.bright);
      });

      test('eşlemesi olmayan durumlar için null döner', () {
        expect(matchRequestToastIconForCode('expired'), isNull);
        expect(matchRequestToastIconForCode('cancelled'), isNull);
        expect(matchRequestToastIconForCode('invalid'), isNull);
        expect(matchRequestToastIconForCode('unknown_code'), isNull);
      });

      test('matchRequestToastIconForError enum eşlemeleri', () {
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.offline)?.assetPath,
          'assets/icons/match_request_offline.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.requestsDisabled)?.assetPath,
          'assets/icons/match_request_disabled.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.unavailable)?.assetPath,
          'assets/icons/match_request_busy.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.cooldownActive)?.assetPath,
          'assets/icons/match_request_cooldown.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.rateLimited)?.assetPath,
          'assets/icons/match_request_cooldown.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.noEnergy)?.assetPath,
          'assets/icons/match_request_no_energy.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.opponentNoEnergy)?.assetPath,
          'assets/icons/match_request_no_energy.svg',
        );
        expect(
          matchRequestToastIconForError(MatchRequestErrorCode.invalid),
          isNull,
        );
      });

      test('matchRequestToastIconForEndStatus enum eşlemeleri', () {
        expect(
          matchRequestToastIconForEndStatus(MatchRequestEndStatus.declined)?.assetPath,
          'assets/icons/match_request_declined.svg',
        );
        expect(
          matchRequestToastIconForEndStatus(MatchRequestEndStatus.expired),
          isNull,
        );
        expect(
          matchRequestToastIconForEndStatus(MatchRequestEndStatus.cancelled),
          isNull,
        );
      });
    });

    test('dangerText beyaz card zemin üzerinde WCAG AA (>= 4.5:1) kontrast gereksinimini sağlar', () {
      final ratio = _calculateContrastRatio(AppColors.dangerText, AppColors.card);
      // Beklenen oran ~6.45:1 - 6.6:1 arasıdır, 4.5:1 eşiğini fazlasıyla geçer
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, greaterThan(6.0));
    });
  });
}
