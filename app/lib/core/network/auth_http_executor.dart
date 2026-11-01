import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/online/data/auth_token_provider.dart';
import 'app_build_info.dart';

/// Kimlik doğrulamalı HTTP isteklerinden dönen yanıt modeli.
class AuthHttpResponse {
  final int statusCode;
  final String body;
  final HttpHeaders? headers;

  const AuthHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers,
  });

  Map<String, dynamic> decodeJsonMap() =>
      jsonDecode(body) as Map<String, dynamic>;

  List<dynamic> decodeJsonList() =>
      jsonDecode(body) as List<dynamic>;
}

/// Firebase ID token ile korunan tüm HTTP isteklerini yürüten ve
/// 401 Unauthorized durumunda jetonu tek seferlik `forceRefresh: true`
/// ile yenileyip tekrar deneyen merkezi yardımcı sınıf.
abstract final class AuthHttpExecutor {
  static Future<AuthHttpResponse?> execute({
    required AuthTokenProvider authTokenProvider,
    required Uri uri,
    required String method,
    HttpClient Function()? clientFactory,
    Object? jsonBody,
    List<int>? bodyBytes,
    Map<String, String>? customHeaders,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // 1. İlk token'ı al (varsayılan: forceRefresh: false)
    final token = await authTokenProvider.getIdToken(forceRefresh: false);
    if (token == null || token.isEmpty) {
      return null;
    }

    final bytes = bodyBytes ??
        (jsonBody != null ? utf8.encode(jsonEncode(jsonBody)) : null);

    // 2. İlk istek denemesi
    var response = await _send(
      clientFactory: clientFactory,
      uri: uri,
      method: method,
      token: token,
      bodyBytes: bytes,
      hasJsonBody: jsonBody != null,
      customHeaders: customHeaders,
      timeout: timeout,
    );

    // 3. 401 Unauthorized durumunda forceRefresh: true ile token'ı yenileyip TEK BİR KEZ tekrar dene
    if (response.statusCode == 401) {
      final freshToken =
          await authTokenProvider.getIdToken(forceRefresh: true);
      if (freshToken != null && freshToken.isNotEmpty) {
        response = await _send(
          clientFactory: clientFactory,
          uri: uri,
          method: method,
          token: freshToken,
          bodyBytes: bytes,
          hasJsonBody: jsonBody != null,
          customHeaders: customHeaders,
          timeout: timeout,
        );
      }
    }

    return response;
  }

  static Future<AuthHttpResponse> _send({
    required HttpClient Function()? clientFactory,
    required Uri uri,
    required String method,
    required String token,
    required List<int>? bodyBytes,
    required bool hasJsonBody,
    required Map<String, String>? customHeaders,
    required Duration timeout,
  }) async {
    final client = clientFactory != null
        ? clientFactory()
        : (HttpClient()..connectionTimeout = timeout);

    try {
      final HttpClientRequest request;
      switch (method.toUpperCase()) {
        case 'GET':
          request = await client.getUrl(uri).timeout(timeout);
          break;
        case 'POST':
          request = await client.postUrl(uri).timeout(timeout);
          break;
        case 'PUT':
          request = await client.putUrl(uri).timeout(timeout);
          break;
        case 'DELETE':
          request = await client.deleteUrl(uri).timeout(timeout);
          break;
        default:
          request = await client.openUrl(method, uri).timeout(timeout);
      }

      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (hasJsonBody) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
      }

      if (customHeaders != null) {
        for (final entry in customHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }

      await AppBuildInfo.applyHeaders(request.headers);

      if (bodyBytes != null && bodyBytes.isNotEmpty) {
        try {
          request.contentLength = bodyBytes.length;
        } catch (_) {}
        request.add(bodyBytes);
      }

      final response = await request.close().timeout(timeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      HttpHeaders? responseHeaders;
      try {
        responseHeaders = response.headers;
      } catch (_) {}

      return AuthHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: responseHeaders,
      );
    } finally {
      client.close();
    }
  }
}
