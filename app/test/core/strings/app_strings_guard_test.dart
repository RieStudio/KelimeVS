import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';

void main() {
  group('AppStrings Guard and Rule Compliance Tests', () {
    test('Eşleşme ipucu havuzunda tam olarak 26 ipucu bulunmalıdır', () {
      final tips = AppStrings.getMatchTips();
      expect(tips.length, equals(26));
    });

    test(
        'AppStrings içindeki tüm metinler bot/yapay zeka, alıştırma maçı, güçlendirici ve resmi Enerjiniz ifadelerinden arındırılmış olmalıdır',
        () {
      // 1. Çalışma zamanı ipucu havuzu kontrolü
      final tips = AppStrings.getMatchTips();
      final botRegex = RegExp(r'\bbot\b', caseSensitive: false);
      final aiRegex = RegExp(r'yapay\s*zeka', caseSensitive: false);
      final practiceMatchRegex = RegExp(r'al[ıi]şt[ıi]rma\s+maç[ıi]', caseSensitive: false);
      final powerupTermRegex = RegExp(r'güçlendirici', caseSensitive: false);
      final formalEnergyRegex = RegExp(r'enerjiniz', caseSensitive: false);

      for (final tip in tips) {
        expect(botRegex.hasMatch(tip), isFalse,
            reason: 'İpucu "$tip" içinde "bot" kelimesi geçmemelidir.');
        expect(aiRegex.hasMatch(tip), isFalse,
            reason: 'İpucu "$tip" içinde "yapay zeka" ifadesi geçmemelidir.');
        expect(practiceMatchRegex.hasMatch(tip), isFalse,
            reason: 'İpucu "$tip" içinde "alıştırma maçı" ifadesi geçmemelidir.');
        expect(powerupTermRegex.hasMatch(tip), isFalse,
            reason: 'İpucu "$tip" içinde "güçlendirici" kelimesi geçmemelidir (Joker kullanılmalı).');
        expect(formalEnergyRegex.hasMatch(tip), isFalse,
            reason: 'İpucu "$tip" içinde resmi "Enerjiniz" ifadesi geçmemelidir.');
      }

      // 2. app_strings.dart kaynak dosyasındaki tüm string sabitlerinin statik analizi
      final possiblePaths = [
        'lib/core/strings/app_strings.dart',
        'app/lib/core/strings/app_strings.dart',
      ];
      File? sourceFile;
      for (final p in possiblePaths) {
        final f = File(p);
        if (f.existsSync()) {
          sourceFile = f;
          break;
        }
      }

      expect(sourceFile, isNotNull,
          reason: 'app_strings.dart kaynak dosyası bulunamadı.');

      final lines = sourceFile!.readAsLinesSync();
      final stringLiteralRegex = RegExp(r"""['"]([^'"]+)['"]""");

      for (int i = 0; i < lines.length; i++) {
        final rawLine = lines[i].trim();
        // Yorum satırlarını atla
        if (rawLine.startsWith('//') || rawLine.startsWith('/*') || rawLine.startsWith('*')) {
          continue;
        }

        for (final match in stringLiteralRegex.allMatches(rawLine)) {
          final literal = match.group(1)!;

          // Dosya yolları, font veya format şablonları gibi kullanıcıya görünmeyen kod içi literal değerleri atla
          if (literal.startsWith('assets/') ||
              literal == 'Fredoka' ||
              literal == 'Nunito' ||
              literal == '{n}') {
            continue;
          }

          expect(botRegex.hasMatch(literal), isFalse,
              reason: 'Satır ${i + 1} ("$literal") içinde "bot" kelimesi geçmemelidir.');
          expect(aiRegex.hasMatch(literal), isFalse,
              reason: 'Satır ${i + 1} ("$literal") içinde "yapay zeka" ifadesi geçmemelidir.');
          expect(practiceMatchRegex.hasMatch(literal), isFalse,
              reason: 'Satır ${i + 1} ("$literal") içinde "alıştırma maçı" ifadesi geçmemelidir.');
          expect(powerupTermRegex.hasMatch(literal), isFalse,
              reason: 'Satır ${i + 1} ("$literal") içinde "güçlendirici" kelimesi geçmemelidir.');
          expect(formalEnergyRegex.hasMatch(literal), isFalse,
              reason: 'Satır ${i + 1} ("$literal") içinde resmi "Enerjiniz" geçmemelidir ("Enerjin" kullanılmalı).');
        }
      }
    });
  });
}
