import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/app_build_info.dart';

/// Sunucu sağlık kontrolünü (GET /health) yürüten soyut arayüz.
abstract interface class HttpHealthChecker {
  /// [url] adresine GET isteği atarak gövdeyi metin olarak döndürür.
  Future<String> checkHealth(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  });
}

/// `dart:io` [HttpClient] kullanan sağlık kontrolcüsü.
class IoHttpHealthChecker implements HttpHealthChecker {
  const IoHttpHealthChecker();

  @override
  Future<String> checkHealth(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse(url);

    if (kDebugMode) {
      try {
        final addresses = await InternetAddress.lookup(uri.host);
        final ipv4 = addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .length;
        final ipv6 = addresses
            .where((a) => a.type == InternetAddressType.IPv6)
            .length;
        debugPrint(
          '[server-test] dns: host=${uri.host} ipv4=$ipv4 ipv6=$ipv6',
        );
      } catch (e) {
        debugPrint(
          '[server-test] dns: host=${uri.host} hata=${e.runtimeType} mesaj=$e',
        );
      }
    }

    final client = HttpClient()..connectionTimeout = timeout;
    if (kDebugMode) {
      debugPrint(
        '[server-test] http_client: connectionTimeout=${client.connectionTimeout}',
      );
    }

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      AppBuildInfo.applyHeaders(request.headers);
      final response = await request.close().timeout(timeout);
      final responseBody =
          await response.transform(utf8.decoder).join().timeout(timeout);

      if (kDebugMode) {
        debugPrint(
          '[server-test] yanıt: status=${response.statusCode} len=${responseBody.length}',
        );
      }

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return responseBody.trim();
    } finally {
      client.close(force: true);
    }
  }
}

/// Test ortamında sahte yanıtlar dönen sağlık kontrolcüsü.
class FakeHttpHealthChecker implements HttpHealthChecker {
  String responseToReturn;
  Object? errorToThrow;
  String? lastCheckedUrl;

  FakeHttpHealthChecker({
    this.responseToReturn = 'ok',
    this.errorToThrow,
  });

  @override
  Future<String> checkHealth(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastCheckedUrl = url;
    if (errorToThrow != null) {
      // ignore: only_throw_errors
      throw errorToThrow!;
    }
    return responseToReturn;
  }
}

