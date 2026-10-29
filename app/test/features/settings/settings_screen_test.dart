import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:app/core/config/app_config.dart';
import 'package:app/core/network/network_status_provider.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/history/match_history_repository.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/settings/presentation/settings_screen.dart';
import 'package:app/gallery/component_gallery.dart';

class _FakeMatchHistoryRepository implements MatchHistoryRepository {
  @override
  Future<void> add(MatchHistoryEntry entry) async {}

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async => [];

  @override
  Future<void> clear() async {}
}

class _FakeNetworkNotifier extends NetworkStatusNotifier {
  final bool _online;
  _FakeNetworkNotifier(this._online);

  @override
  NetworkState build() {
    return NetworkState(
      status: _online ? NetworkStatus.online : NetworkStatus.offline,
    );
  }
}

void main() {
  final testPackageInfo = PackageInfo(
    appName: 'KelimeVS',
    packageName: 'com.riestudio.kelimevs',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );

  Widget createWidget({
    bool online = true,
    bool isDebug = true,
    Future<bool> Function(Uri)? urlLauncher,
  }) {
    return ProviderScope(
      overrides: [
        networkStatusProvider.overrideWith(() => _FakeNetworkNotifier(online)),
        packageInfoProvider.overrideWith((ref) async => testPackageInfo),
      ],
      child: MaterialApp(
        home: SettingsScreen(
          isDebug: isDebug,
          urlLauncher: urlLauncher,
        ),
      ),
    );
  }

  group('SettingsScreen Widget Tests', () {
    testWidgets('renders all main elements, titles, and version footer', (tester) async {
      await tester.pumpWidget(createWidget(isDebug: false));
      await tester.pumpAndSettle();

      // Top bar title
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect(find.byKey(const Key('settings_back_button')), findsOneWidget);

      // Section labels
      expect(find.text(AppStrings.settingsSectionLegal), findsOneWidget);
      expect(find.text(AppStrings.settingsSectionSupport), findsOneWidget);

      // Tiles
      expect(find.text(AppStrings.privacyPolicy), findsOneWidget);
      expect(find.text(AppStrings.thirdPartyLicenses), findsOneWidget);
      expect(find.text(AppStrings.contactSupport), findsOneWidget);
      expect(find.text(AppConfig.supportEmail), findsOneWidget);

      // Version footer
      expect(find.text('KelimeVS v1.2.3 (45)'), findsOneWidget);

      // Copyright & RieStudio Logo footer
      expect(find.text(AppStrings.copyrightPrefix), findsOneWidget);
      final imageFinder = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == AppStrings.companyName,
      );
      expect(imageFinder, findsOneWidget);
      final logoImage = tester.widget<Image>(imageFinder);
      final imageProvider = logoImage.image;
      final assetImage = imageProvider is ResizeImage
          ? imageProvider.imageProvider as AssetImage
          : imageProvider as AssetImage;
      expect(assetImage.assetName, 'assets/images/riestudio_logo_black_trimmed.png');
      expect(logoImage.height, 15.0);
    });

    testWidgets('footer logo renders fallback text when image load fails', (tester) async {
      await tester.pumpWidget(createWidget(isDebug: false));
      await tester.pumpAndSettle();

      // Find the Image widget
      final imageFinder = find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == AppStrings.companyName,
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);

      // Test errorBuilder
      final context = tester.element(imageFinder);
      final fallbackWidget = imageWidget.errorBuilder!(
        context,
        Exception('Asset not found'),
        StackTrace.empty,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: fallbackWidget)),
        ),
      );
      expect(find.text(AppStrings.companyName), findsOneWidget);
    });

    testWidgets('320 dp width and 1.5 textScaler renders without overflow in settings footer', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: createWidget(isDebug: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.copyrightPrefix), findsOneWidget);
    });

    testWidgets('Gallery row is HIDDEN in release mode (isDebug = false)', (tester) async {
      await tester.pumpWidget(createWidget(isDebug: false));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_dev_gallery')), findsNothing);
      expect(find.text(AppStrings.devComponentGallery), findsNothing);
      expect(find.text(AppStrings.settingsSectionDeveloper), findsNothing);
    });

    testWidgets('Gallery row IS PRESENT in debug mode (isDebug = true) and opens ComponentGallery',
        (tester) async {
      await tester.pumpWidget(createWidget(isDebug: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_dev_gallery')), findsOneWidget);
      expect(find.text(AppStrings.devComponentGallery), findsOneWidget);
      expect(find.text(AppStrings.settingsSectionDeveloper), findsOneWidget);

      // Tap gallery tile
      await tester.tap(find.byKey(const Key('settings_dev_gallery')));
      await tester.pumpAndSettle();

      // ComponentGallery should now be visible on top
      expect(find.byType(ComponentGallery), findsOneWidget);
    });

    testWidgets('offline shows SnackBar and blocks external launch', (tester) async {
      Uri? launchedUri;
      await tester.pumpWidget(createWidget(
        online: false,
        urlLauncher: (uri) async {
          launchedUri = uri;
          return true;
        },
      ));
      await tester.pumpAndSettle();

      // Tap Privacy Policy while offline
      await tester.tap(find.byKey(const Key('settings_privacy_policy')));
      await tester.pumpAndSettle();

      expect(launchedUri, isNull);
      expect(find.text(AppStrings.noInternetActionError), findsOneWidget);
    });

    testWidgets('online launches Privacy Policy URL', (tester) async {
      Uri? launchedUri;
      await tester.pumpWidget(createWidget(
        online: true,
        urlLauncher: (uri) async {
          launchedUri = uri;
          return true;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_privacy_policy')));
      await tester.pumpAndSettle();

      expect(launchedUri, isNotNull);
      expect(launchedUri.toString(), AppConfig.privacyPolicyUrl);
    });

    testWidgets('online launches Contact Support mailto URI with subject', (tester) async {
      Uri? launchedUri;
      await tester.pumpWidget(createWidget(
        online: true,
        urlLauncher: (uri) async {
          launchedUri = uri;
          return true;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_contact_support')));
      await tester.pumpAndSettle();

      expect(launchedUri, isNotNull);
      expect(launchedUri!.scheme, 'mailto');
      expect(launchedUri!.path, AppConfig.supportEmail);
      expect(launchedUri!.queryParameters['subject'], AppConfig.supportSubject);
    });

    testWidgets('failed URL launch displays linkOpenError SnackBar', (tester) async {
      await tester.pumpWidget(createWidget(
        online: true,
        urlLauncher: (uri) async => false, // simulates failure to launch
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_privacy_policy')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.linkOpenError), findsOneWidget);
    });

    testWidgets('tapping Third Party Licenses opens showLicensePage', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_licenses')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('back button pops SettingsScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkStatusProvider.overrideWith(() => _FakeNetworkNotifier(true)),
            packageInfoProvider.overrideWith((ref) async => testPackageInfo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  child: const Text('Open Settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open settings
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);

      // Tap back button
      await tester.tap(find.byKey(const Key('settings_back_button')));
      await tester.pumpAndSettle();

      // Returned to home
      expect(find.text(AppStrings.settingsTitle), findsNothing);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('tapping Settings button on HomeScreen navigates to SettingsScreen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkStatusProvider.overrideWith(() => _FakeNetworkNotifier(true)),
            packageInfoProvider.overrideWith((ref) async => testPackageInfo),
            matchHistoryRepositoryProvider.overrideWithValue(_FakeMatchHistoryRepository()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final settingsButton = find.byKey(const Key('settings_button'));
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
    });
  });
}
