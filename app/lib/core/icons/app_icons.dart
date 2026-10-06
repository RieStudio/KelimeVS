import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';

/// DESIGN.md Bölüm 5'teki SVG yol verilerini taşıyan model
class AppIconData {
  final String path;
  final bool isTrophy;

  const AppIconData(this.path) : isTrophy = false;
  const AppIconData._trophy(this.path) : isTrophy = true;

  String toSvgString({required Color strokeColor}) {
    final strokeHex = _toHex(strokeColor);
    final coinHex = _toHex(AppColors.coin);

    if (isTrophy) {
      return '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8 4h8v5a4 4 0 01-8 0z" fill="$coinHex" stroke="$strokeHex" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M8 6H5v2a3 3 0 003 3M16 6h3v2a3 3 0 01-3 3M12 13v4M9 20h6M10 17h4" stroke="$strokeHex" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';
    }

    return '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="$path" stroke="$strokeHex" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';
  }

  static String _toHex(Color color) {
    final rgb = (color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb';
  }
}

/// DESIGN.md Bölüm 5'teki 11 ikon tanımı
abstract final class AppIcons {
  // 1. Ana sayfa
  static const AppIconData home = AppIconData('M3 11l9-8 9 8M5 10v10h14V10');

  // 2. Sıralama
  static const AppIconData leaderboard = AppIconData('M5 20V12M12 20V4M19 20V9');

  // 3. Mağaza
  static const AppIconData shop = AppIconData('M5 8h14l-1 12H6zM9 8a3 3 0 016 0');

  // 4. Profil
  static const AppIconData profile = AppIconData('M12 12a4 4 0 100-8 4 4 0 000 8M4 21a8 8 0 0116 0');

  // 5. Ayarlar
  static const AppIconData settings = AppIconData('M4 7h16M4 17h16M9 4v6M15 14v6');

  // 6. Kapat
  static const AppIconData close = AppIconData('M6 6l12 12M18 6L6 18');

  // 7. Geri
  static const AppIconData back = AppIconData('M15 6l-6 6 6 6');

  // 8. Sağ ok (gönder)
  static const AppIconData arrowSend = AppIconData('M5 12h14M13 6l6 6-6 6');

  // 9. Sağ ok (liste)
  static const AppIconData arrowList = AppIconData('M9 6l6 6-6 6');

  // 10. Onay
  static const AppIconData check = AppIconData('M5 12l5 5 9-10');

  // 11. Kupa
  static const AppIconData trophy = AppIconData._trophy('');
}

/// DESIGN.md Bölüm 5 standartlarına uygun İkon Widget'ı
class AppIcon extends StatelessWidget {
  final AppIconData icon;
  final Color color;
  final double size;

  const AppIcon(
    this.icon, {
    super.key,
    this.color = AppColors.ink,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      icon.toSvgString(strokeColor: color),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

