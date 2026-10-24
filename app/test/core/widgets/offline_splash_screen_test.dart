import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/offline_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineSplashScreen Widget Tests', () {
    testWidgets('1. Çevrimdışı açılış ekranı ikon, başlık, açıklama ve tekrar dene butonu çizer', (tester) async {
      bool retryPressed = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: OfflineSplashScreen(
              onRetry: () => retryPressed = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('offline_splash_screen')), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text(AppStrings.noInternetTitle), findsOneWidget);
      expect(find.text(AppStrings.noInternetMessage), findsOneWidget);
      expect(find.byKey(const Key('offline_splash_retry_button')), findsOneWidget);
      expect(find.text(AppStrings.retryConnection), findsOneWidget);

      await tester.tap(find.byKey(const Key('offline_splash_retry_button')));
      await tester.pump();

      expect(retryPressed, true);
    });

    testWidgets('2. OfflineSplashScreen açıkken global şerit bastırılır', (tester) async {
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Consumer(
              builder: (context, ref, _) {
                savedRef = ref;
                return OfflineSplashScreen(onRetry: () {});
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(savedRef.read(isOfflineBannerSuppressedProvider), true);
    });
  });
}

