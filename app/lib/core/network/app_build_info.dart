import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Uygulamanın derleme numarasını (build number) yöneten ve
/// sunucuya giden HTTP isteklerine "X-App-Build" başlığı ekleyen yardımcı sınıf.
abstract final class AppBuildInfo {
  static String? _cachedBuildNumber;
  static bool _initialized = false;
  static Future<void>? _loadingFuture;
  static Future<PackageInfo> Function()? _customLoader;

  /// Açılışta veya tembel olarak çağrılır (package_info_plus üzerinden buildNumber okur ve önbelleğe alır).
  static Future<void> initialize({
    PackageInfo? packageInfo,
    Future<PackageInfo> Function()? loader,
  }) async {
    if (loader != null) {
      _customLoader = loader;
    }
    if (packageInfo != null) {
      _parseAndCache(packageInfo);
      _initialized = true;
      return;
    }
    await _ensureLoaded();
  }

  static void _parseAndCache(PackageInfo info) {
    final raw = info.buildNumber.trim();
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed > 0) {
      _cachedBuildNumber = raw;
    } else {
      _cachedBuildNumber = null;
    }
  }

  /// Eşzamanlı isteklerde birden çok kez çağrılmaması için tek bir Future paylaşılır.
  /// Hata oluşursa sonraki istekte tekrar denenebilmesi için _loadingFuture sıfırlanır.
  static Future<void> _ensureLoaded() async {
    if (_cachedBuildNumber != null) return;
    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    _loadingFuture = () async {
      try {
        final info = _customLoader != null
            ? await _customLoader!()
            : await PackageInfo.fromPlatform();
        _parseAndCache(info);
      } catch (e, st) {
        debugPrint('[AppBuildInfo] Paket bilgisi okunamadı: $e\n$st');
        _cachedBuildNumber = null;
      } finally {
        _initialized = true;
        _loadingFuture = null;
      }
    }();

    await _loadingFuture;
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
  static void setMockPackageInfoLoader(Future<PackageInfo> Function()? loader) {
    _customLoader = loader;
  }

  @visibleForTesting
  static void reset() {
    _cachedBuildNumber = null;
    _initialized = false;
    _loadingFuture = null;
    _customLoader = null;
  }

  @visibleForTesting
  static void resetForTesting() => reset();

  /// Sunucuya giden HTTP isteklerine X-App-Build başlığını ekler.
  /// Önbellek boşsa tembel (lazy) olarak yükler.
  /// İstek başlık eklenemezse bile ASLA patlamaz / başarısız olmaz.
  static Future<void> applyHeaders(HttpHeaders headers) async {
    try {
      if (_cachedBuildNumber == null) {
        await _ensureLoaded();
      }
      if (_cachedBuildNumber != null && _cachedBuildNumber!.isNotEmpty) {
        final parsed = int.tryParse(_cachedBuildNumber!);
        if (parsed != null && parsed > 0) {
          headers.set('X-App-Build', _cachedBuildNumber!);
        }
      }
    } catch (e, st) {
      debugPrint('[AppBuildInfo] Başlık eklenirken hata: $e\n$st');
    }
  }
}
