import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_api_client.dart';
import 'package:app/features/settings/presentation/settings_screen.dart';

class FakeProfileApiClientSuccess implements ProfileApiClient {
  bool lastAllowedValue = true;

  @override
  Future<bool> updateAllowMatchRequests(bool allow) async {
    lastAllowedValue = allow;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileApiClientFail implements ProfileApiClient {
  @override
  Future<bool> updateAllowMatchRequests(bool allow) async {
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final testPackageInfo = PackageInfo(
    appName: 'KelimeVS',
    packageName: 'com.riestudio.kelimevs',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );

  group('SettingsScreen Match Requests Switch Tests', () {
    testWidgets('1. Varsayılan olarak anahtar açık gelir ve başlık/alt metin doğru gösterilir', (tester) async {
      final fakeApi = FakeProfileApiClientSuccess();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageInfoProvider.overrideWith((ref) async => testPackageInfo),
            profileApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            home: SettingsScreen(isDebug: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsSectionMatchRequests), findsOneWidget);
      expect(find.text(AppStrings.settingsAllowMatchRequestsTitle), findsOneWidget);
      expect(find.text(AppStrings.settingsAllowMatchRequestsSubtitle), findsOneWidget);

      final switchFinder = find.byKey(const Key('settings_allow_match_requests_switch'));
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isTrue);
    });

    testWidgets('2. Anahtara basılınca durum güncellenir (başarılı API çağrısı)', (tester) async {
      final fakeApi = FakeProfileApiClientSuccess();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageInfoProvider.overrideWith((ref) async => testPackageInfo),
            profileApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            home: SettingsScreen(isDebug: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('settings_allow_match_requests_switch'));
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(fakeApi.lastAllowedValue, isFalse);
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);
    });

    testWidgets('3. API çağrısı başarısız olduğunda durum geri alınır ve hata snackbar gösterilir', (tester) async {
      final fakeApi = FakeProfileApiClientFail();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageInfoProvider.overrideWith((ref) async => testPackageInfo),
            profileApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(
            home: SettingsScreen(isDebug: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('settings_allow_match_requests_switch'));
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Hata sonrasında değer eski haline (true) dönmeli
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isTrue);

      // Hata snackbar'ı görünmeli
      expect(find.text(AppStrings.settingsUpdateError), findsOneWidget);
    });
  });
}
