// Saf Dart - Flutter veya Riverpod bağımlılığı yoktur.

// TODO: Faz 4'te sunucu tarafı küfür filtresi ve maskeleme
abstract class TextFilter {
  String apply(String text);
}

/// Şimdilik metni olduğu gibi döndüren varsayılan metin filtresi.
class PassthroughTextFilter implements TextFilter {
  const PassthroughTextFilter();

  @override
  String apply(String text) => text;
}

