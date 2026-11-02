import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/settings/presentation/licenses_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockPackages = [
    const PackageLicenses(
      name: 'archive',
      licenseTexts: [
        'Archive License text paragraph 1.\nArchive License text paragraph 2.',
      ],
    ),
    const PackageLicenses(
      name: 'flutter',
      licenseTexts: [
        'Copyright 2014 The Flutter Authors. All rights reserved.\nRedistribution and use in source and binary forms...',
        'Secondary Flutter Engine License...',
      ],
    ),
  ];

  Widget buildTestWidget({
    String? applicationName = 'KelimeVS',
    String? applicationVersion = 'v1.0.0 (13)',
    String? applicationLegalese = '© 2026 RieStudio',
    Future<List<PackageLicenses>> Function()? licensesLoader,
  }) {
    return MaterialApp(
      home: LicensesScreen(
        applicationName: applicationName,
        applicationVersion: applicationVersion,
        applicationLegalese: applicationLegalese,
        licensesLoader: licensesLoader ?? () async => mockPackages,
      ),
    );
  }

  group('LicensesScreen & PackageLicenseDetailScreen Tests', () {
    testWidgets('1. Lisans ekranı başlığı, uygulama bilgisi, sürüm ve yasal metni sade düz metin olarak (kart/çerçeve olmadan) gösterir', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.licensesTitle), findsOneWidget);
      expect(find.text('KelimeVS'), findsOneWidget);
      expect(find.text('v1.0.0 (13)'), findsOneWidget);
      expect(find.text('© 2026 RieStudio'), findsOneWidget);
      expect(find.byKey(const Key('licenses_back_button')), findsOneWidget);

      // Başlık metinlerinin bir kart/çerçeve içinde olmadığını (düz Padding + Column içinde olduğunu) doğrula
      final appNameFinder = find.text('KelimeVS');
      final columnFinder = find.ancestor(of: appNameFinder, matching: find.byType(Column)).first;
      // Column'ın doğrudan üst ebeveyni Padding olmalı, kart/border Container olmamalı
      final directParent = find.ancestor(of: columnFinder, matching: find.byType(Padding)).first;
      expect(directParent, findsOneWidget);
      expect(find.ancestor(of: columnFinder, matching: find.byType(Card)), findsNothing);
    });

    testWidgets('2. "Powered by Flutter" veya Flutter logosu hiçbir yerde yer almaz', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Powered by Flutter'), findsNothing);
      expect(find.textContaining('Flutter ile geliştirildi'), findsNothing);
      expect(find.byType(FlutterLogo), findsNothing);
    });

    testWidgets('3. Paket listesi paket adı ve lisans sayısı ile listelenir', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('archive'), findsOneWidget);
      expect(find.text('1 lisans'), findsOneWidget);

      expect(find.text('flutter'), findsOneWidget);
      expect(find.text('2 lisans'), findsOneWidget);
    });

    testWidgets('4. Bir pakete dokunulduğunda detay ekranı açılır ve tam lisans metni gösterilir', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // "archive" paketine dokun
      await tester.tap(find.text('archive'));
      await tester.pumpAndSettle();

      expect(find.byType(PackageLicenseDetailScreen), findsOneWidget);
      expect(find.text('archive'), findsOneWidget);
      expect(find.textContaining('Archive License text paragraph 1.'), findsOneWidget);
      expect(find.textContaining('Archive License text paragraph 2.'), findsOneWidget);

      // Detay ekranında da "Powered by Flutter" olmadığını doğrula
      expect(find.textContaining('Powered by Flutter'), findsNothing);
      expect(find.textContaining('Flutter ile geliştirildi'), findsNothing);
      expect(find.byType(FlutterLogo), findsNothing);

      // Geri butonuna dokunulunca liste ekranına döner
      await tester.tap(find.byKey(const Key('license_detail_back_button')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensesScreen), findsOneWidget);
      expect(find.byType(PackageLicenseDetailScreen), findsNothing);
    });

    testWidgets('5. Birden fazla lisansı olan pakette tüm lisans metinleri numaralandırılarak gösterilir', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // "flutter" (2 lisans) paketine dokun
      await tester.tap(find.text('flutter'));
      await tester.pumpAndSettle();

      expect(find.byType(PackageLicenseDetailScreen), findsOneWidget);
      expect(find.text('Lisans 1'), findsOneWidget);
      expect(find.text('Lisans 2'), findsOneWidget);
      expect(find.textContaining('The Flutter Authors'), findsOneWidget);
      expect(find.textContaining('Secondary Flutter Engine License...'), findsOneWidget);
    });

    testWidgets('6. Yüklenme aşamasında CircularProgressIndicator gösterilir', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          licensesLoader: () => Future.delayed(
            const Duration(seconds: 5),
            () => mockPackages,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('archive'), findsOneWidget);
    });

    testWidgets('7. Boş lisans listesinde noLicensesFound uyarısı gösterilir', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          licensesLoader: () async => const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.noLicensesFound), findsOneWidget);
    });

    testWidgets('8. loadLicensesFromRegistry gerçek LicenseRegistry akışını doğru parse eder', (tester) async {
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(
          ['custom_test_pkg'],
          'Custom Test Package License Full Text',
        );
      });

      final loaded = await loadLicensesFromRegistry();
      expect(loaded.any((pkg) => pkg.name == 'custom_test_pkg'), isTrue);
      final customPkg = loaded.firstWhere((pkg) => pkg.name == 'custom_test_pkg');
      expect(customPkg.licenseTexts.first, contains('Custom Test Package License Full Text'));
    });
  });
}

