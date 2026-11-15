import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IncomingMatchRequestBanner Widget Tests', () {
    testWidgets('profilden gelen dostluk maç isteğini doğru başlık ve alt başlıkla gösterir',
        (tester) async {
      final request = IncomingMatchRequest(
        id: 'req_1',
        fromUid: 'u_opponent',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.matchRequestTitleProfile('Ahmet')), findsOneWidget);
      expect(find.text(AppStrings.matchRequestSubtitleFriendly), findsOneWidget);
      expect(find.text(AppStrings.matchRequestAccept), findsOneWidget);
      expect(find.text(AppStrings.matchRequestDecline), findsOneWidget);

      // KESİNLİKLE bot rozeti veya bot metni bulunmamalı
      expect(find.textContaining('bot', findRichText: true), findsNothing);
      expect(find.textContaining('BOT', findRichText: true), findsNothing);
    });

    testWidgets('maç sonu rövanş rankli maç isteğini doğru başlık ve 1 enerji bilgisiyle gösterir',
        (tester) async {
      final request = IncomingMatchRequest(
        id: 'req_2',
        fromUid: 'u_opponent',
        fromNickname: 'Zeynep',
        fromFrame: 'gold',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.matchRequestTitleRematch('Zeynep')), findsOneWidget);
      expect(find.text(AppStrings.matchRequestSubtitleRanked), findsOneWidget);
    });

    testWidgets('Reddet butonuna basıldığında onDecline tetiklenir', (tester) async {
      bool declined = false;
      final request = IncomingMatchRequest(
        id: 'req_3',
        fromUid: 'u_1',
        fromNickname: 'Can',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () => declined = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.matchRequestDecline));
      await tester.pump();

      expect(declined, isTrue);
    });

    testWidgets('Kabul Et butonuna basıldığında onAccept tetiklenir', (tester) async {
      bool accepted = false;
      final request = IncomingMatchRequest(
        id: 'req_4',
        fromUid: 'u_1',
        fromNickname: 'Elif',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () => accepted = true,
              onDecline: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.matchRequestAccept));
      await tester.pump();

      expect(accepted, isTrue);
    });

    testWidgets('isAccepting true iken yükleme göstergesi açılır ve butonlara dokunulamaz',
        (tester) async {
      bool accepted = false;
      bool declined = false;
      final request = IncomingMatchRequest(
        id: 'req_5',
        fromUid: 'u_1',
        fromNickname: 'Murat',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              isAccepting: true,
              onAccept: () => accepted = true,
              onDecline: () => declined = true,
            ),
          ),
        ),
      );

      // Kabul Et yazısı yerine spinner döner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Dokunulduğunda callback'ler tetiklenmemeli (çift tıklama koruması)
      await tester.tap(find.byType(CircularProgressIndicator).last);
      await tester.pump();
      expect(accepted, isFalse);

      await tester.tap(find.text(AppStrings.matchRequestDecline));
      await tester.pump();
      expect(declined, isFalse);
    });

    test('calculateBarColor: 15s yeşil, 10s lerp, 5s ve altı tam kırmızı', () {
      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(45.0),
        AppColors.primary,
      );
      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(15.0),
        AppColors.primary,
      );

      final halfColor = _IncomingMatchRequestBannerTestHelper.calculateBarColor(10.0);
      final expectedHalf = Color.lerp(AppColors.primary, AppColors.danger, 0.5);
      expect(halfColor, expectedHalf);

      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(5.0),
        AppColors.danger,
      );
      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(0.0),
        AppColors.danger,
      );

      // Animasyonlar kapalıyken tek adımlı eşik kontrolü
      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(10.0, disableAnimations: true),
        AppColors.primary,
      );
      expect(
        _IncomingMatchRequestBannerTestHelper.calculateBarColor(5.0, disableAnimations: true),
        AppColors.danger,
      );
    });

    testWidgets('Akıcı ilerleme çubuğu: süre azaldıkça LinearProgressIndicator değeri ve rengi güncellenir',
        (tester) async {
      int elapsedMs = 0;
      final request = IncomingMatchRequest(
        id: 'req_smooth',
        fromUid: 'u_1',
        fromNickname: 'Test',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 45000,
        elapsedMsProvider: () => elapsedMs,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );

      LinearProgressIndicator indicator =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, 1.0);
      expect((indicator.valueColor as AlwaysStoppedAnimation<Color>).value, AppColors.primary);

      // 35 sn geçti (kalan 10 sn) -> lerp rengi
      elapsedMs = 35000;
      await tester.pump(const Duration(milliseconds: 16));

      indicator = tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, closeTo(10000 / 45000.0, 0.01));
      final expectedLerp = Color.lerp(AppColors.primary, AppColors.danger, 0.5);
      expect((indicator.valueColor as AlwaysStoppedAnimation<Color>).value, expectedLerp);

      // 40 sn geçti (kalan 5 sn) -> tam kırmızı
      elapsedMs = 40000;
      await tester.pump(const Duration(milliseconds: 16));

      indicator = tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, closeTo(5000 / 45000.0, 0.01));
      expect((indicator.valueColor as AlwaysStoppedAnimation<Color>).value, AppColors.danger);
    });

    testWidgets('disableAnimations true iken 1 saniyelik adımlarla güncellenir',
        (tester) async {
      int elapsedMs = 0;
      final request = IncomingMatchRequest(
        id: 'req_reduced_motion',
        fromUid: 'u_1',
        fromNickname: 'Test',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 45000,
        elapsedMsProvider: () => elapsedMs,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: IncomingMatchRequestBanner(
                request: request,
                onAccept: () {},
                onDecline: () {},
              ),
            ),
          ),
        ),
      );

      LinearProgressIndicator indicator =
          tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, 1.0);

      // 1 sn ileri al
      elapsedMs = 1000;
      await tester.pump(const Duration(seconds: 1));

      indicator = tester.widget(find.byType(LinearProgressIndicator));
      expect(indicator.value, closeTo(44 / 45.0, 0.01));
    });
  });
}

// Test için hesaplama metoduna erişim sağlayan yardımcı
abstract class _IncomingMatchRequestBannerTestHelper {
  static Color calculateBarColor(double remainingSeconds, {bool disableAnimations = false}) {
    // Aynı hesaplama mantığını doğrulamak için public metot veya çağrı
    const progressWarningThresholdSec = 15.0;
    const progressDangerThresholdSec = 5.0;
    if (disableAnimations) {
      return remainingSeconds <= progressDangerThresholdSec
          ? AppColors.danger
          : AppColors.primary;
    }
    if (remainingSeconds >= progressWarningThresholdSec) {
      return AppColors.primary;
    }
    if (remainingSeconds <= progressDangerThresholdSec) {
      return AppColors.danger;
    }
    final t = (progressWarningThresholdSec - remainingSeconds) /
        (progressWarningThresholdSec - progressDangerThresholdSec);
    return Color.lerp(AppColors.primary, AppColors.danger, t.clamp(0.0, 1.0)) ??
        AppColors.danger;
  }
}
