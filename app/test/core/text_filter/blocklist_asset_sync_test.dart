import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Blocklist Asset Integrity & Client Sync Test', () {
    test('app/assets/text_filter/blocklist.json dosyası mevcut ve geçerlidir', () {
      File? file;
      for (final p in [
        'assets/text_filter/blocklist.json',
        'app/assets/text_filter/blocklist.json',
        '../app/assets/text_filter/blocklist.json',
      ]) {
        final f = File(p);
        if (f.existsSync()) {
          file = f;
          break;
        }
      }

      expect(
        file,
        isNotNull,
        reason: 'blocklist.json dosyası mevcut olmalıdır. Gerekirse "npm run export:blocklist" çalıştırın.',
      );

      final content = file!.readAsStringSync();
      expect(content.isNotEmpty, isTrue);

      final decoded = json.decode(content);
      expect(decoded is Map<String, dynamic>, isTrue);

      final map = decoded as Map<String, dynamic>;
      expect(map['version'], 1);
      expect(map['allow'], isA<List>());
      expect(map['exact'], isA<List>());
      expect(map['contains'], isA<List>());

      final allow = map['allow'] as List;
      final exact = map['exact'] as List;
      final contains = map['contains'] as List;

      expect(allow.length, greaterThanOrEqualTo(50));
      expect(exact.length, greaterThanOrEqualTo(25));
      expect(contains.length, greaterThanOrEqualTo(100));

      // Bilinen kritik kelimelerin varlığı
      expect(allow.contains('kemal'), isTrue);
      expect(allow.contains('tamam'), isTrue);
      expect(allow.contains('finnigan'), isTrue);
      expect(exact.contains('pic'), isTrue);
      expect(exact.contains('sik'), isTrue);
      expect(contains.contains('orospu'), isTrue);
      expect(contains.contains('siktir'), isTrue);
    });
  });
}
