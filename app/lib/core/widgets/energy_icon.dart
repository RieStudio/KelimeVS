import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// KelimeGo Enerji Rozeti İkon Widget'ı.
///
/// `assets/icons/energy_badge.svg` dosyasını çizer (yeşil rozet içinde, rozetten
/// üstten ve alttan taşan sarı şimşek).
///
/// SVG'nin viewBox'ı kare ve şimşek rozetten taştığı için [ClipRect] veya
/// [Clip.hardEdge] kullanılmaz; ikon tam olarak görüntülenir.
class EnergyIcon extends StatelessWidget {
  /// İkonun genişlik ve yükseklik boyutu.
  final double size;

  /// Erişilebilirlik için anlamsal etiket (varsayılan: "Enerji").
  final String? semanticLabel;

  /// İsteğe bağlı opaklık (ör. boş/tükenmiş enerji yuvaları için).
  final double opacity;

  const EnergyIcon({
    super.key,
    this.size = 24.0,
    this.semanticLabel = 'Enerji',
    this.opacity = 1.0,
  });

  static const String assetPath = 'assets/icons/energy_badge.svg';

  @override
  Widget build(BuildContext context) {
    Widget svg = SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      clipBehavior: Clip.none,
      semanticsLabel: semanticLabel,
    );

    if (opacity < 1.0) {
      svg = Opacity(
        opacity: opacity,
        child: svg,
      );
    }

    return svg;
  }
}
