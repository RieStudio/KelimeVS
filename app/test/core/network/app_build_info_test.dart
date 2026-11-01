import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/network/app_build_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    AppBuildInfo.resetForTesting();
  });

  tearDown(() {
    AppBuildInfo.resetForTesting();
  });

  group('AppBuildInfo tests', () {
    test('initializes correctly with integer build number', () async {
      final fakePackageInfo = PackageInfo(
        appName: 'KelimeGO',
        packageName: 'com.riestudio.kelimego',
        version: '1.0.0',
        buildNumber: '11',
      );

      await AppBuildInfo.initialize(packageInfo: fakePackageInfo);
      expect(AppBuildInfo.buildNumber, equals('11'));

      final headers = FakeHttpHeaders();
      await AppBuildInfo.applyHeaders(headers);

      expect(headers.values['x-app-build'], equals('11'));
    });

    test('omits header when build number is non-numeric or empty', () async {
      final fakePackageInfo = PackageInfo(
        appName: 'KelimeGO',
        packageName: 'com.riestudio.kelimego',
        version: '1.0.0',
        buildNumber: 'invalid_alpha',
      );

      await AppBuildInfo.initialize(packageInfo: fakePackageInfo);
      expect(AppBuildInfo.buildNumber, isNull);

      final headers = FakeHttpHeaders();
      await AppBuildInfo.applyHeaders(headers);

      expect(headers.values.containsKey('x-app-build'), isFalse);
    });

    test('omits header when buildNumber <= 0', () async {
      AppBuildInfo.setMockBuildNumber(0);
      expect(AppBuildInfo.buildNumber, equals('0'));

      final headers = FakeHttpHeaders();
      await AppBuildInfo.applyHeaders(headers);

      expect(headers.values.containsKey('x-app-build'), isFalse);
    });

    test('setMockBuildNumber overrides build number for testing', () async {
      AppBuildInfo.setMockBuildNumber(15);
      expect(AppBuildInfo.buildNumber, equals('15'));

      final headers = FakeHttpHeaders();
      await AppBuildInfo.applyHeaders(headers);

      expect(headers.values['x-app-build'], equals('15'));
    });

    test('lazy loading: applies headers when not initialized upfront', () async {
      AppBuildInfo.setMockPackageInfoLoader(() async {
        return PackageInfo(
          appName: 'KelimeGO',
          packageName: 'com.riestudio.kelimego',
          version: '1.0.0',
          buildNumber: '11',
        );
      });

      final headers = FakeHttpHeaders();
      await AppBuildInfo.applyHeaders(headers);

      expect(headers.values['x-app-build'], equals('11'));
      expect(AppBuildInfo.buildNumber, equals('11'));
    });

    test('concurrent lazy loading shares a single Future and calls loader once', () async {
      int callCount = 0;
      AppBuildInfo.setMockPackageInfoLoader(() async {
        callCount++;
        await Future.delayed(const Duration(milliseconds: 20));
        return PackageInfo(
          appName: 'KelimeGO',
          packageName: 'com.riestudio.kelimego',
          version: '1.0.0',
          buildNumber: '11',
        );
      });

      final h1 = FakeHttpHeaders();
      final h2 = FakeHttpHeaders();
      final h3 = FakeHttpHeaders();

      await Future.wait([
        AppBuildInfo.applyHeaders(h1),
        AppBuildInfo.applyHeaders(h2),
        AppBuildInfo.applyHeaders(h3),
      ]);

      expect(callCount, equals(1));
      expect(h1.values['x-app-build'], equals('11'));
      expect(h2.values['x-app-build'], equals('11'));
      expect(h3.values['x-app-build'], equals('11'));
    });

    test('retry on error: initial failure completes safely without throwing and retries on next call', () async {
      int attempts = 0;
      AppBuildInfo.setMockPackageInfoLoader(() async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('Platform channel not available');
        }
        return PackageInfo(
          appName: 'KelimeGO',
          packageName: 'com.riestudio.kelimego',
          version: '1.0.0',
          buildNumber: '11',
        );
      });

      // 1. çağrı hata fırlatır ancak applyHeaders patlamaz
      final h1 = FakeHttpHeaders();
      await expectLater(AppBuildInfo.applyHeaders(h1), completes);
      expect(h1.values.containsKey('x-app-build'), isFalse);
      expect(AppBuildInfo.buildNumber, isNull);
      expect(attempts, equals(1));

      // 2. çağrı yeniden dener ve başarılı olur
      final h2 = FakeHttpHeaders();
      await expectLater(AppBuildInfo.applyHeaders(h2), completes);
      expect(h2.values['x-app-build'], equals('11'));
      expect(AppBuildInfo.buildNumber, equals('11'));
      expect(attempts, equals(2));
    });
  });
}
