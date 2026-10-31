import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Uygulamanın derleme numarasını (build number) yöneten ve
/// sunucuya giden HTTP isteklerine "X-App-Build" başlığı ekleyen yardımcı sınıf.
abstract final class AppBuildInfo {
  static String? _cachedBuildNumber;
  static bool _initialized = false;

  /// Açılışta bir kez çağrılır (package_info_plus üzerinden buildNumber okur ve önbelleğe alır).
  static Future<void> initialize({PackageInfo? packageInfo}) async {
    try {
      final info = packageInfo ?? await PackageInfo.fromPlatform();
      final raw = info.buildNumber.trim();
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) {
        _cachedBuildNumber = raw;
      } else {
        _cachedBuildNumber = null;
      }
    } catch (_) {
      _cachedBuildNumber = null;
    } finally {
      _initialized = true;
    }
  }

  static String? get buildNumber => _cachedBuildNumber;
  static bool get isInitialized => _initialized;

  @visibleForTesting
  static void setMockBuildNumber(Object? value) {
    if (value == null) {
      _cachedBuildNumber = null;
    } else {
      _cachedBuildNumber = value.toString();
    }
    _initialized = true;
  }

  @visibleForTesting
  static void reset() {
    _cachedBuildNumber = null;
    _initialized = false;
  }

  @visibleForTesting
  static void resetForTesting() => reset();

  /// Sunucuya giden HTTP isteklerine X-App-Build başlığını ekler (varsa).
  static void applyHeaders(HttpHeaders headers) {
    if (_cachedBuildNumber != null && _cachedBuildNumber!.isNotEmpty) {
      final parsed = int.tryParse(_cachedBuildNumber!);
      if (parsed != null && parsed > 0) {
        headers.set('X-App-Build', _cachedBuildNumber!);
      }
    }
  }
}
