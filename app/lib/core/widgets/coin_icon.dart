import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// KelimeGo Jeton İkon Widget'ı.
///
/// `assets/icons/coin.svg` dosyasını çizer (üç jetonluk yığın, viewBox kare,
/// içerik ortalanmış).
///
/// SVG'nin kutu boyutunu içeriğe göre kesmemek için [Clip.none] ve [BoxFit.contain] kullanılır.
class CoinIcon extends StatelessWidget {
  /// İkonun genişlik ve yükseklik boyutu.
  final double size;

  /// Erişilebilirlik için anlamsal etiket (varsayılan: "Jeton").
  final String? semanticLabel;

  /// İsteğe bağlı opaklık (ör. devre dışı/soluk durumlar için).
  final double opacity;

  const CoinIcon({
    super.key,
    this.size = 24.0,
    this.semanticLabel = 'Jeton',
    this.opacity = 1.0,
  });

  static const String assetPath = 'assets/icons/coin.svg';

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

