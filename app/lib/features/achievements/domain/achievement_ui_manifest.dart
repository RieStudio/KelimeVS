/// Arayüzde gösterilecek başarım metin ve görsel verileri.
class AchievementUiItem {
  final String id;
  final String title;
  final String description;

  const AchievementUiItem({
    required this.id,
    required this.title,
    required this.description,
  });

  /// Başarıma ait çok renkli SVG ikon dosyasının asset yolu.
  String get iconAsset => 'assets/icons/ach_$id.svg';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AchievementUiItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description;

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ description.hashCode;
}

/// İstemci tarafında başarım kimliklerini (ID) Türkçe başlık ve açıklamalara eşleyen manifest.
/// Bilinmeyen ID'leri sessizce null döner (ileride sunucu yeni başarım eklediğinde eski istemci çökmez).
abstract final class AchievementUiManifest {
  static const Map<String, AchievementUiItem> _items = {
    'first_match': AchievementUiItem(
      id: 'first_match',
      title: 'İlk Adım',
      description: 'İlk maçını tamamla',
    ),
    'matches_10': AchievementUiItem(
      id: 'matches_10',
      title: 'Alışma Süreci',
      description: '10 maç tamamla',
    ),
    'matches_50': AchievementUiItem(
      id: 'matches_50',
      title: 'Düzenli Oyuncu',
      description: '50 maç tamamla',
    ),
    'matches_100': AchievementUiItem(
      id: 'matches_100',
      title: 'Yüzlük',
      description: '100 maç tamamla',
    ),
    'first_win': AchievementUiItem(
      id: 'first_win',
      title: 'İlk Zafer',
      description: 'İlk galibiyetini al',
    ),
    'wins_10': AchievementUiItem(
      id: 'wins_10',
      title: 'Yükselen Yıldız',
      description: '10 galibiyet al',
    ),
    'wins_50': AchievementUiItem(
      id: 'wins_50',
      title: 'Usta Oyuncu',
      description: '50 galibiyet al',
    ),
    'wins_100': AchievementUiItem(
      id: 'wins_100',
      title: 'Efsane',
      description: '100 galibiyet al',
    ),
    'streak_3': AchievementUiItem(
      id: 'streak_3',
      title: 'Üçlü Seri',
      description: 'Üst üste 3 maç kazan',
    ),
    'streak_5': AchievementUiItem(
      id: 'streak_5',
      title: 'Beşli Seri',
      description: 'Üst üste 5 maç kazan',
    ),
    'streak_10': AchievementUiItem(
      id: 'streak_10',
      title: 'Durdurulamaz',
      description: 'Üst üste 10 maç kazan',
    ),
  };

  /// Bilinen tüm başarım UI tanımları.
  static Map<String, AchievementUiItem> get items => _items;

  /// Belirtilen kimliğe karşılık gelen başarım UI bilgisini döner.
  /// Bilinmeyen ID gelirse sessizce null döner.
  static AchievementUiItem? get(String id) => _items[id];

  /// Belirtilen kimliğe karşılık gelen çok renkli SVG ikon asset yolunu döner.
  /// Bilinmeyen ID gelirse sessizce null döner.
  static String? iconAssetFor(String id) =>
      _items.containsKey(id) ? 'assets/icons/ach_$id.svg' : null;
}
