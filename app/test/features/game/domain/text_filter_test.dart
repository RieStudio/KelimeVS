import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/text_filter.dart';

class CustomMaskingTextFilter implements TextFilter {
  final Set<String> blockedWords;
  const CustomMaskingTextFilter(this.blockedWords);

  @override
  String apply(String text) {
    var result = text;
    for (final word in blockedWords) {
      result = result.replaceAll(word, '***');
    }
    return result;
  }
}

void main() {
  group('PassthroughTextFilter', () {
    test('metni değiştirmeden olduğu gibi döndürür', () {
      const filter = PassthroughTextFilter();
      expect(filter.apply('merhaba dünya'), 'merhaba dünya');
      expect(filter.apply('küfürlü veya argo kelime'), 'küfürlü veya argo kelime');
      expect(filter.apply(''), '');
    });
  });

  group('Custom TextFilter (Faz 4 hazırlığı testi)', () {
    test('özel TextFilter uygulaması metni filtreleyebilir', () {
      final filter = CustomMaskingTextFilter({'kötü', 'yasak'});
      expect(filter.apply('bu kötü bir söz'), 'bu *** bir söz');
      expect(filter.apply('bu yasak kelimedir'), 'bu *** kelimedir');
      expect(filter.apply('temiz metin'), 'temiz metin');
    });
  });
}

