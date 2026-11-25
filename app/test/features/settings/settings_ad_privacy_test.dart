import 'package:app/core/ads/ad_providers.dart';
import 'package:app/core/ads/ad_service.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _OnlineNetworkNotifier extends NetworkStatusNotifier {
  @override
  NetworkState build() => const NetworkState(status: NetworkStatus.online);
}

class _TestAdConsentNotifier extends AdConsentNotifier {
  final AdConsentState _initial;
  _TestAdConsentNotifier(this._initial)
      : super(isAdsEnabledOverride: () => true);

  @override
  AdConsentState build() => _initial;
}

void main() {
  final testPackageInfo = PackageInfo(
    appName: 'KelimeVS',
    packageName: 'com.kelimevs.app',
    version: '1.3.1',
    buildNumber: '21',
    buildSignature: '',
  );

  Widget buildSettings({
    required AdConsentPrivacyStatus privacyStatus,
    required FakeAdService fakeAdService,
  }) {
    return ProviderScope(
      overrides: [
        networkStatusProvider.overrideWith(_OnlineNetworkNotifier.new),
        packageInfoProvider.overrideWith((ref) async => testPackageInfo),
        adServiceProvider.overrideWithValue(fakeAdService),
        adConsentProvider.overrideWith(
          () => _TestAdConsentNotifier(
            AdConsentState(
              isConsentChecked: true,
              canRequestAds: true,
              isSdkInitialized: true,
              privacyOptionsStatus: privacyStatus,
            ),
          ),
        ),
      ],
      child: const MaterialApp(
        home: SettingsScreen(isDebug: false),
      ),
    );
  }

  testWidgets('privacyOptionsStatus notRequired iken satır gizlidir',
      (tester) async {
    final fakeAdService = FakeAdService();
    await tester.pumpWidget(
      buildSettings(
        privacyStatus: AdConsentPrivacyStatus.notRequired,
        fakeAdService: fakeAdService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_ad_privacy_options')), findsNothing);
    expect(find.text(AppStrings.adPrivacyOptions), findsNothing);
  });

  testWidgets(
      'privacyOptionsStatus required iken satır görünür ve dokununca formu açar',
      (tester) async {
    final fakeAdService = FakeAdService();
    await tester.pumpWidget(
      buildSettings(
        privacyStatus: AdConsentPrivacyStatus.required,
        fakeAdService: fakeAdService,
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const Key('settings_ad_privacy_options'));
    expect(tileFinder, findsOneWidget);
    expect(find.text(AppStrings.adPrivacyOptions), findsOneWidget);

    await tester.ensureVisible(tileFinder);
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(fakeAdService.showPrivacyOptionsCallCount, 1);
  });
}
