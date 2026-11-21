import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/text_filter/app_text_filter.dart';

void main() {
  group('Shared TextMasker Parity Test Vectors (TypeScript vs Dart)', () {
    late AppTextFilter filter;
    late List<Map<String, dynamic>> testCases;

    setUpAll(() {
      // 1. Blocklist JSON'u yükle
      File? blocklistFile;
      for (final p in [
        'assets/text_filter/blocklist.json',
        'app/assets/text_filter/blocklist.json',
        '../app/assets/text_filter/blocklist.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          blocklistFile = f;
          break;
        }
      }
      expect(
        blocklistFile,
        isNotNull,
        reason: 'assets/text_filter/blocklist.json bulunmalıdır. npm run export:blocklist çalıştırın.',
      );

      final blocklistJson = json.decode(blocklistFile!.readAsStringSync()) as Map<String, dynamic>;
      filter = AppTextFilter.fromJson(blocklistJson);

      // 2. Shared test vektörlerini yükle
      File? vectorsFile;
      for (final p in [
        '../shared/test-vectors/text_masker.json',
        'shared/test-vectors/text_masker.json',
        '../../shared/test-vectors/text_masker.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          vectorsFile = f;
          break;
        }
      }
      expect(
        vectorsFile,
        isNotNull,
        reason: 'shared/test-vectors/text_masker.json bulunmalıdır.',
      );

      final vectorsJson = json.decode(vectorsFile!.readAsStringSync()) as Map<String, dynamic>;
      testCases = (vectorsJson['cases'] as List<dynamic>)
          .map((c) => c as Map<String, dynamic>)
          .toList();
    });

    test('Tüm ortak test vektörleri (80 durum) sunucu ile birebir eşleşir', () {
      expect(testCases.length, 80);

      for (int i = 0; i < testCases.length; i++) {
        final c = testCases[i];
        final input = c['input'] as String;
        final expected = c['expected'] as String;

        final actual = filter.apply(input);
        expect(
          actual,
          expected,
          reason: 'Test vektörü #$i başarısız: girdi="$input", beklenen="$expected", alınan="$actual"',
        );
      }
    });
  });
}
