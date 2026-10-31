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
      AppBuildInfo.applyHeaders(headers);

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
      AppBuildInfo.applyHeaders(headers);

      expect(headers.values.containsKey('x-app-build'), isFalse);
    });

    test('omits header when buildNumber <= 0', () async {
      AppBuildInfo.setMockBuildNumber(0);
      expect(AppBuildInfo.buildNumber, equals('0'));

      final headers = FakeHttpHeaders();
      AppBuildInfo.applyHeaders(headers);

      expect(headers.values.containsKey('x-app-build'), isFalse);
    });

    test('setMockBuildNumber overrides build number for testing', () {
      AppBuildInfo.setMockBuildNumber(15);
      expect(AppBuildInfo.buildNumber, equals('15'));

      final headers = FakeHttpHeaders();
      AppBuildInfo.applyHeaders(headers);

      expect(headers.values['x-app-build'], equals('15'));
    });
  });
}
