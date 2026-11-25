import 'user_achievement.dart';

/// Arayüzde gösterilecek başarım metin ve görsel verileri.
class AchievementUiItem {
  final String id;
  final String title;
  final String description;
  final int rank;

  /// Rozetin kart sol kenarına göre yatay konumu (px, sola negatif, varsayılan -12.0).
  final double badgeDx;

  /// Rozetin dikey konum kaydırması (px; badgeAlignBottom true iken alt kenara göre
  /// mesafe, false iken merkezden aşağı/yukarı ofset, varsayılan 0.0).
  final double badgeDy;

  /// Rozetin dikey ortalama yerine kartın alt kenarına hizalanıp hizalanmayacağı.
  final bool badgeAlignBottom;

  /// Rozetin dönme açısı derece cinsinden (varsayılan -6.0).
  final double badgeRotationDeg;

  const AchievementUiItem({
    required this.id,
    required this.title,
    required this.description,
    this.rank = 99,
    this.badgeDx = -12.0,
    this.badgeDy = 0.0,
    this.badgeAlignBottom = false,
    this.badgeRotationDeg = -6.0,
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
          description == other.description &&
          rank == other.rank &&
          badgeDx == other.badgeDx &&
          badgeDy == other.badgeDy &&
          badgeAlignBottom == other.badgeAlignBottom &&
          badgeRotationDeg == other.badgeRotationDeg;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      description.hashCode ^
      rank.hashCode ^
      badgeDx.hashCode ^
      badgeDy.hashCode ^
      badgeAlignBottom.hashCode ^
      badgeRotationDeg.hashCode;
}

/// İstemci tarafında başarım kimliklerini (ID) Türkçe başlık ve açıklamalara eşleyen manifest.
/// Bilinmeyen ID'leri sessizce null döner (ileride sunucu yeni başarım eklediğinde eski istemci çökmez).
abstract final class AchievementUiManifest {
  static const Map<String, AchievementUiItem> _items = {
    'first_match': AchievementUiItem(
      id: 'first_match',
      title: 'İlk Adım',
      description: 'İlk maçını tamamla',
      rank: 10,
      // Çimen tabanı kart içinde, alt 3 px border'ın hemen üstünde ve sol kenardan içeride oturur; bayrak eğimi SVG'nin içindedir.
      badgeDx: 4.0,
      badgeDy: 0.0,
      badgeAlignBottom: true,
      badgeRotationDeg: 0.0,
    ),
    'matches_10': AchievementUiItem(
      id: 'matches_10',
      title: 'Alışma Süreci',
      description: '10 maç tamamla',
      rank: 8,
    ),
    'matches_50': AchievementUiItem(
      id: 'matches_50',
      title: 'Düzenli Oyuncu',
      description: '50 maç tamamla',
      rank: 5,
    ),
    'matches_100': AchievementUiItem(
      id: 'matches_100',
      title: 'Yüzlük',
      description: '100 maç tamamla',
      rank: 2,
    ),
    'first_win': AchievementUiItem(
      id: 'first_win',
      title: 'İlk Zafer',
      description: 'İlk galibiyetini al',
      rank: 9,
      badgeDx: -6.0,
      badgeRotationDeg: -6.0,
    ),
    'wins_10': AchievementUiItem(
      id: 'wins_10',
      title: 'Yükselen Yıldız',
      description: '10 galibiyet al',
      rank: 6,
      badgeDx: -14.0,
      badgeRotationDeg: -12.0,
    ),
    'wins_50': AchievementUiItem(
      id: 'wins_50',
      title: 'Usta Oyuncu',
      description: '50 galibiyet al',
      rank: 3,
    ),
    'wins_100': AchievementUiItem(
      id: 'wins_100',
      title: 'Efsane',
      description: '100 galibiyet al',
      rank: 0,
    ),
    'streak_3': AchievementUiItem(
      id: 'streak_3',
      title: 'Üçlü Seri',
      description: 'Üst üste 3 maç kazan',
      rank: 7,
    ),
    'streak_5': AchievementUiItem(
      id: 'streak_5',
      title: 'Beşli Seri',
      description: 'Üst üste 5 maç kazan',
      rank: 4,
    ),
    'streak_10': AchievementUiItem(
      id: 'streak_10',
      title: 'Durdurulamaz',
      description: 'Üst üste 10 maç kazan',
      rank: 1,
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

  /// Bilinen başarımları sabit prestij sırasına ([AchievementUiItem.rank]) göre sıralar.
  /// Manifestte bulunmayan ID'ler sessizce elenir.
  static List<UserAchievement> sortByPrestige(
    Iterable<UserAchievement> achievements,
  ) {
    final known = achievements
        .where((a) => _items.containsKey(a.id))
        .toList();
    known.sort((a, b) => _items[a.id]!.rank.compareTo(_items[b.id]!.rank));
    return known;
  }
}
