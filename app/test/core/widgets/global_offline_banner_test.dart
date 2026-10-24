import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/global_offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalOfflineBanner Widget Tests', () {
    testWidgets('1. Şerit wifi_off ikonu, uyarı metni ve Tekrar Dene butonu gösterir', (tester) async {
      bool retryClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GlobalOfflineBanner(
              onRetry: () => retryClicked = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('global_offline_banner')), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text(AppStrings.noInternetBanner), findsOneWidget);
      expect(find.byKey(const Key('global_offline_banner_retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('global_offline_banner_retry')));
      await tester.pump();

      expect(retryClicked, true);
    });

    testWidgets('2. Şerit içeriğin üstüne binmez; içeriği aşağı iter ve üst butonlar tıklanabilir kalır', (tester) async {
      bool buttonClicked = false;

      // Banner olmadan önceki üst pozisyonu ölç
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ElevatedButton(
                      key: const Key('test_top_button'),
                      onPressed: () => buttonClicked = true,
                      child: const Text('Üst Buton'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final initialButtonTop = tester.getTopLeft(find.byKey(const Key('test_top_button'))).dy;

      // Banner varken
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                const GlobalOfflineBanner(),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ElevatedButton(
                      key: const Key('test_top_button'),
                      onPressed: () => buttonClicked = true,
                      child: const Text('Üst Buton'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final withBannerButtonTop = tester.getTopLeft(find.byKey(const Key('test_top_button'))).dy;
      final bannerHeight = tester.getSize(find.byKey(const Key('global_offline_banner'))).height;

      // Buton aşağı itilmiş olmalı (üstüne binme yok)
      expect(withBannerButtonTop, greaterThan(initialButtonTop));
      expect(withBannerButtonTop, closeTo(initialButtonTop + bannerHeight, 1.0));

      // Butona dokunulabilmeli
      await tester.tap(find.byKey(const Key('test_top_button')));
      await tester.pump();

      expect(buttonClicked, true);
    });
  });
}
