import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/text_filter/app_text_filter.dart';

void main() {
  group('AppTextFilter Unit Tests', () {
    late AppTextFilter filter;

    setUpAll(() {
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
      expect(blocklistFile, isNotNull);
      final jsonMap = json.decode(blocklistFile!.readAsStringSync()) as Map<String, dynamic>;
      filter = AppTextFilter.fromJson(jsonMap);
    });

    group('Normalizasyon (normalizeForFilter)', () {
      test('Türkçe büyük/küçük harf İ/I/ı/i hepsi i olur', () {
        expect(normalizeForFilter('İSTANBUL'), 'istanbul');
        expect(normalizeForFilter('ıslak'), 'islak');
        expect(normalizeForFilter('İĞNE'), 'igne');
      });

      test('Türkçe karakterler ve aksanlar sadeleştirilir', () {
        expect(normalizeForFilter('şeker'), 'seker');
        expect(normalizeForFilter('ağaç'), 'agac');
        expect(normalizeForFilter('üzüm'), 'uzum');
        expect(normalizeForFilter('ördek'), 'ordek');
        expect(normalizeForFilter('çanta'), 'canta');
        expect(normalizeForFilter('hâla'), 'hala');
      });

      test('Leetspeak ve sembol eşlemeleri düzgün çalışır', () {
        // 0->o, 1->i, 3->e, 4->a, 5->s, 7->t, 9->g, @->a, $->s, !->i, |->i, +->t
        expect(normalizeForFilter('0134579'), 'oieastg');
        expect(normalizeForFilter('@\$!|+'), 'asit');
      });

      test('Ayraçlar ve görünmez karakterler atılır', () {
        expect(normalizeForFilter('s.i-k_i m'), 'sikim');
        expect(normalizeForFilter('o\u200Br\u200Co\u200Ds\uFEFFp\u00ADu'), 'orospu');
      });

      test('Üst üste tekrarlanan harfler teke indirilir', () {
        expect(normalizeForFilter('soooorrrruuuun'), 'sorun');
        expect(normalizeForFilter('aaaaabbbbcccc'), 'abc');
      });

      test('NFKC uyumluluk katlaması tam genişlikli karakterleri çözer', () {
        expect(normalizeForFilter('ｏｒｏｓｐｕ'), 'orospu');
        expect(normalizeForFilter('ｓｉｋ'), 'sik');
      });
    });

    group('Uygunsuzluk Tespiti ve Maskeleme', () {
      test('Tekil küfürler ilk harf + yıldızlar olarak maskelenir', () {
        expect(filter.apply('orospu'), 'o*****');
        expect(filter.apply('Orospu'), 'O*****');
        expect(filter.apply('OROSPU'), 'O*****');
        expect(filter.apply('şerefsiz'), 'ş*******');
        expect(filter.apply('Şerefsiz'), 'Ş*******');
        expect(filter.apply('İbne'), 'İ***');
        expect(filter.apply('ıbne'), 'ı***');
      });

      test('Cümle içindeki masum kelimeler korunur, yalnızca küfür maskelenir', () {
        expect(filter.apply('sen bir orospusun'), 'sen bir o********');
        expect(filter.apply('ben, orospu değilim.'), 'ben, o***** değilim.');
        expect(filter.apply('tamam ben geliyorum'), 'tamam ben geliyorum');
        expect(filter.apply('bu cok guzel bir oyun'), 'bu cok guzel bir oyun');
      });

      test('Allow listesindeki masum kelimeler asla maskelenmez', () {
        expect(filter.apply('kemal'), 'kemal');
        expect(filter.apply('kamil'), 'kamil');
        expect(filter.apply('damla'), 'damla');
        expect(filter.apply('amiral'), 'amiral');
        expect(filter.apply('tamam'), 'tamam');
        expect(filter.apply('siklamen'), 'siklamen');
        expect(filter.apply('kasik'), 'kasik');
        expect(filter.apply('fistik'), 'fistik');
        expect(filter.apply('lastik'), 'lastik');
        expect(filter.apply('finnigan'), 'finnigan');
      });

      test('Sayısal girdiler ve trivia cevapları tamamen muaftır', () {
        expect(filter.apply('31'), '31');
        expect(filter.apply('13'), '13');
        expect(filter.apply('1993'), '1993');
        expect(filter.apply('3.1'), '3.1');
        expect(filter.apply('3 1'), '3 1');
        expect(filter.apply('Apollo 13'), 'Apollo 13');
        expect(filter.apply('Windows 3 1'), 'Windows 3 1');
        expect(filter.apply('10/10'), '10/10');
        expect(filter.apply('1923-1938'), '1923-1938');
      });

      test('Aralıklı tek harfli yazımlar maskelenir', () {
        expect(filter.apply('s i k'), 's****');
        expect(filter.apply('s  i  k'), 's******');
        expect(filter.apply('o r o s p u'), 'o**********');
        expect(filter.apply('o.r.o.s.p.u'), 'o**********');
        expect(filter.apply('s_i_k'), 's****');
        expect(filter.apply('p.i.c'), 'p****');
      });

      test('Aralıklı yazım masum tek harfleri maskelemez', () {
        expect(filter.apply('o ve a'), 'o ve a');
        expect(filter.apply('a b c d e'), 'a b c d e');
      });
    });

    group('Güvenlik, İdempotens ve Başarım', () {
      test('İdempotens: apply(apply(text)) == apply(text)', () {
        const samples = [
          'sen bir orospusun',
          's i k kafalı',
          '31 ve 13',
          'tamam kemal fıstık',
          'orospu!',
          'Windows 3 1',
        ];

        for (final s in samples) {
          final once = filter.apply(s);
          final twice = filter.apply(once);
          expect(twice, once, reason: 'İdempotens başarısız: "$s"');
        }
      });

      test('Boşluk ve sınır durumlarında güvenlidir', () {
        expect(filter.apply(''), '');
        expect(filter.apply('   '), '   ');
        expect(filter.apply('a'), 'a');
        expect(filter.apply('1'), '1');
      });

      test('Çok uzun metinlerde hata fırlatmaz ve güvenle çalışır', () {
        final longInnocent = 'Bu masum bir cümledir. ' * 500; // 12,000 karakter
        final start = DateTime.now();
        final result = filter.apply(longInnocent);
        final elapsed = DateTime.now().difference(start);

        expect(result.length, longInnocent.length);
        expect(elapsed.inMilliseconds, lessThan(200));
      });

      test('Başarım: 20 kelimelik cümle < 1 ms ortalama', () {
        const sentence = 'Bu bir oyun testi için yazılmış yirmi kelimelik standart ve gayet uzun bir cümle örneğidir burada kelimeler var.';
        // Isınma turu
        for (int i = 0; i < 50; i++) {
          filter.apply(sentence);
        }

        final stopwatch = Stopwatch()..start();
        const iterations = 1000;
        for (int i = 0; i < iterations; i++) {
          filter.apply(sentence);
        }
        stopwatch.stop();

        final avgMs = stopwatch.elapsedMicroseconds / (iterations * 1000.0);
        // ignore: avoid_print
        print('1000 çağrı toplam: ${stopwatch.elapsedMilliseconds} ms (ortalama: ${avgMs.toStringAsFixed(3)} ms/çağrı)');
        expect(avgMs, lessThan(1.0));
      });
    });
  });
}
