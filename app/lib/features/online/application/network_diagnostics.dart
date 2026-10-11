import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Tek bir hedef adresin tanılama sonucu.
///
/// Güvenlik kuralı: Gövde içeriği ve HTTP başlıkları kesinlikle saklanmaz ve döndürülmez.
class DiagnosticTargetResult {
  /// Şema + Host + Yol formatında adres (örn: https://1.1.1.1/cdn-cgi/trace)
  final String url;

  /// İsteğin başarılı bir HTTP durum kodu (200-399) ile sonuçlanıp sonuçlanmadığı.
  final bool isSuccess;

  /// Alınan HTTP durum kodu (örn: 200, 204). İstek tamamlanamadıysa null.
  final int? statusCode;

  /// İsteğin gidiş-dönüş süresi (milisaniye).
  final int durationMs;

  /// Hata türü (örn: SocketException, HandshakeException, TimeoutException).
  final String? errorType;

  /// İşletim sistemi hata kodu (örn: errno 104 = Connection reset by peer).
  final int? osErrorCode;

  /// DNS çözümleme sonucunda dönen IPv4 adres sayısı.
  final int ipv4Count;

  /// DNS çözümleme sonucunda dönen IPv6 adres sayısı.
  final int ipv6Count;

  const DiagnosticTargetResult({
    required this.url,
    required this.isSuccess,
    this.statusCode,
    required this.durationMs,
    this.errorType,
    this.osErrorCode,
    required this.ipv4Count,
    required this.ipv6Count,
  });

  /// Ekranda ve loglarda gösterilecek özet satırı.
  String get summaryLine {
    final statusPart = isSuccess
        ? 'Tamam (HTTP $statusCode)'
        : 'HATA (${errorType ?? 'Bilinmeyen'}${osErrorCode != null ? ', errno $osErrorCode' : ''})';
    return '$url\n  -> $statusPart | ${durationMs}ms | IPv4: $ipv4Count, IPv6: $ipv6Count';
  }

  @override
  String toString() => summaryLine;
}

/// Tüm ağ tanılama hedeflerinin toplu raporu.
class NetworkDiagnosticsReport {
  final List<DiagnosticTargetResult> results;
  final int totalDurationMs;

  const NetworkDiagnosticsReport({
    required this.results,
    required this.totalDurationMs,
  });
}

/// Özel hedef probe fonksiyonu tipi (testlerde sahtesini enjekte etmek için).
typedef DiagnosticProbeFunction = Future<DiagnosticTargetResult> Function(
  String url,
  Duration timeout,
);

/// Mobil veri ve Wi-Fi arasındaki bağlantı farklılıklarını (DNS, Cloudflare CDN,
/// doğrudan IP, Workers vb.) tespit eden ağ tanılama servisi.
class NetworkDiagnostics {
  static const List<String> defaultTargets = [
    'https://www.google.com/generate_204',
    'https://cloudflare.com/cdn-cgi/trace',
    'https://1.1.1.1/cdn-cgi/trace',
    'https://riestudio.com.tr',
    'https://server.riestudio.workers.dev/health',
  ];

  final List<String> targets;
  final Duration timeout;
  final DiagnosticProbeFunction? probeFunction;

  const NetworkDiagnostics({
    this.targets = defaultTargets,
    this.timeout = const Duration(seconds: 10),
    this.probeFunction,
  });

  /// Belirlenen hedeflere sırayla GET isteği atarak tanılama raporunu üretir.
  Future<NetworkDiagnosticsReport> run() async {
    final results = <DiagnosticTargetResult>[];
    final totalWatch = Stopwatch()..start();

    for (final rawUrl in targets) {
      final probe = probeFunction ?? _defaultProbe;
      final result = await probe(rawUrl, timeout);
      results.add(result);
    }

    totalWatch.stop();
    return NetworkDiagnosticsReport(
      results: results,
      totalDurationMs: totalWatch.elapsedMilliseconds,
    );
  }

  /// Gerçek `dart:io` HttpClient ve DNS sorgusu kullanan varsayılan probe yöntemi.
  static Future<DiagnosticTargetResult> _defaultProbe(
    String rawUrl,
    Duration timeout,
  ) async {
    final uri = Uri.parse(rawUrl);
    final cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';
    final watch = Stopwatch()..start();

    int ipv4 = 0;
    int ipv6 = 0;

    // 1. DNS / IP Çözümleme
    try {
      final parsedIp = InternetAddress.tryParse(uri.host);
      if (parsedIp != null) {
        if (parsedIp.type == InternetAddressType.IPv4) {
          ipv4 = 1;
        } else if (parsedIp.type == InternetAddressType.IPv6) {
          ipv6 = 1;
        }
      } else {
        final addresses = await InternetAddress.lookup(uri.host);
        ipv4 = addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .length;
        ipv6 = addresses
            .where((a) => a.type == InternetAddressType.IPv6)
            .length;
      }
    } catch (_) {
      // DNS hatası durumunda 0 kalır
    }

    // 2. HTTP GET İsteği
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      // Gövde içeriğini güvenli bir şekilde tüket, ancak hiçbir yere kaydetme
      await response.drain<void>().timeout(timeout);
      watch.stop();

      final statusCode = response.statusCode;
      final isSuccess = statusCode >= 200 && statusCode < 400;

      if (kDebugMode) {
        debugPrint(
          '[net-diag] $cleanUrl status=$statusCode ms=${watch.elapsedMilliseconds}',
        );
      }

      return DiagnosticTargetResult(
        url: cleanUrl,
        isSuccess: isSuccess,
        statusCode: statusCode,
        durationMs: watch.elapsedMilliseconds,
        ipv4Count: ipv4,
        ipv6Count: ipv6,
      );
    } catch (e) {
      watch.stop();

      String errorType = e.runtimeType.toString();
      int? osErrorCode;

      if (e is SocketException) {
        errorType = 'SocketException';
        osErrorCode = e.osError?.errorCode;
      } else if (e is HandshakeException) {
        errorType = 'HandshakeException';
        final osErr = e.osError;
        if (osErr != null) {
          osErrorCode = osErr.errorCode;
        }
      } else if (e is TimeoutException) {
        errorType = 'TimeoutException';
      }

      if (kDebugMode) {
        debugPrint(
          '[net-diag] $cleanUrl error=$errorType errno=$osErrorCode ms=${watch.elapsedMilliseconds}',
        );
      }

      return DiagnosticTargetResult(
        url: cleanUrl,
        isSuccess: false,
        durationMs: watch.elapsedMilliseconds,
        errorType: errorType,
        osErrorCode: osErrorCode,
        ipv4Count: ipv4,
        ipv6Count: ipv6,
      );
    } finally {
      client.close(force: true);
    }
  }
}
