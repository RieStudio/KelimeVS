@Timeout(Duration(seconds: 30))
library;

import 'package:app/features/online/application/network_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkDiagnostics (Ağ Tanılama Servisi)', () {
    test('başarılı akış: 5 hedefin tümü sorgulanır ve özet üretilir', () async {
      final probeUrls = <String>[];

      final diagnostics = NetworkDiagnostics(
        probeFunction: (url, timeout) async {
          probeUrls.add(url);
          final is204 = url.contains('generate_204');
          return DiagnosticTargetResult(
            url: url,
            isSuccess: true,
            statusCode: is204 ? 204 : 200,
            durationMs: 42,
            ipv4Count: 2,
            ipv6Count: 1,
          );
        },
      );

      final report = await diagnostics.run();

      expect(report.results.length, 5);
      expect(probeUrls, NetworkDiagnostics.defaultTargets);

      // İlk hedef generate_204
      expect(report.results[0].url, 'https://www.google.com/generate_204');
      expect(report.results[0].isSuccess, isTrue);
      expect(report.results[0].statusCode, 204);
      expect(report.results[0].ipv4Count, 2);
      expect(report.results[0].ipv6Count, 1);
      expect(report.results[0].summaryLine, contains('Tamam (HTTP 204)'));

      // Son hedef workers health
      expect(
        report.results[4].url,
        'https://server.riestudio.workers.dev/health',
      );
      expect(report.results[4].isSuccess, isTrue);
      expect(report.results[4].statusCode, 200);
      expect(report.results[4].summaryLine, contains('Tamam (HTTP 200)'));
    });

    test('SocketException (errno 104 / Connection reset) durumunda hata kodu ve türü kaydedilir', () async {
      final diagnostics = NetworkDiagnostics(
        targets: const ['https://server.riestudio.workers.dev/health'],
        probeFunction: (url, timeout) async {
          return const DiagnosticTargetResult(
            url: 'https://server.riestudio.workers.dev/health',
            isSuccess: false,
            durationMs: 267,
            errorType: 'SocketException',
            osErrorCode: 104,
            ipv4Count: 2,
            ipv6Count: 2,
          );
        },
      );

      final report = await diagnostics.run();

      expect(report.results.length, 1);
      final r = report.results.first;
      expect(r.isSuccess, isFalse);
      expect(r.statusCode, isNull);
      expect(r.errorType, 'SocketException');
      expect(r.osErrorCode, 104);
      expect(r.summaryLine, contains('HATA (SocketException, errno 104)'));
      expect(r.summaryLine, contains('IPv4: 2, IPv6: 2'));
    });

    test('HandshakeException (TLS hatası) durumunda hata türü kaydedilir', () async {
      final diagnostics = NetworkDiagnostics(
        targets: const ['https://cloudflare.com/cdn-cgi/trace'],
        probeFunction: (url, timeout) async {
          return const DiagnosticTargetResult(
            url: 'https://cloudflare.com/cdn-cgi/trace',
            isSuccess: false,
            durationMs: 150,
            errorType: 'HandshakeException',
            ipv4Count: 1,
            ipv6Count: 0,
          );
        },
      );

      final report = await diagnostics.run();

      expect(report.results.length, 1);
      final r = report.results.first;
      expect(r.isSuccess, isFalse);
      expect(r.errorType, 'HandshakeException');
      expect(r.osErrorCode, isNull);
      expect(r.summaryLine, contains('HATA (HandshakeException)'));
    });

    test('TimeoutException (zaman aşımı) durumunda net hata türü kaydedilir', () async {
      final diagnostics = NetworkDiagnostics(
        targets: const ['https://1.1.1.1/cdn-cgi/trace'],
        probeFunction: (url, timeout) async {
          return const DiagnosticTargetResult(
            url: 'https://1.1.1.1/cdn-cgi/trace',
            isSuccess: false,
            durationMs: 10000,
            errorType: 'TimeoutException',
            ipv4Count: 1,
            ipv6Count: 0,
          );
        },
      );

      final report = await diagnostics.run();

      expect(report.results.length, 1);
      final r = report.results.first;
      expect(r.isSuccess, isFalse);
      expect(r.errorType, 'TimeoutException');
      expect(r.summaryLine, contains('HATA (TimeoutException)'));
    });

    test('GÜVENLİK VE GİZLİLİK: Sonuç satırlarında yanıt gövdesi veya HTTP başlığı yer almaz', () async {
      const sensitiveResponseBody = 'fl=123h1\nh=cloudflare.com\nip=1.2.3.4\n';
      const sensitiveHeader = 'CF-RAY: 8d12345678-IST';

      final result = const DiagnosticTargetResult(
        url: 'https://cloudflare.com/cdn-cgi/trace',
        isSuccess: true,
        statusCode: 200,
        durationMs: 50,
        ipv4Count: 2,
        ipv6Count: 2,
      );

      final summary = result.summaryLine;

      expect(summary, isNot(contains(sensitiveResponseBody)));
      expect(summary, isNot(contains(sensitiveHeader)));
      expect(summary, isNot(contains('CF-RAY')));
      expect(summary, isNot(contains('ip=')));
    });
  });
}
