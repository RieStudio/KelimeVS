import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final responseBody =
          await response.transform(utf8.decoder).join().timeout(timeout);
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

