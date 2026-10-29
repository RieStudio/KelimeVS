import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'answer_bubble.dart';

/// KelimeVS Logo
/// "Kelime" (Fredoka 700, ink) + "VS" (Fredoka 700, card rengi, canlı yeşil konuşma balonu).
/// Konuşma balonunun çentiği sol altta yer alır ve "Kelime" metnine doğru yönelir.
class KelimeVSLogo extends StatelessWidget {
  final double fontSize;

  /// Balonun "Kelime" metnine göre dikey aşağı kaydırma oranı (fontSize çarpanı).
  /// Başlangıç değeri: 0.06.
  /// Balonun alt kenarı "Kelime" taban çizgisiyle (baseline) hizalanır veya
  /// hafif altına inen çentik hariç aynı hizada durur; balon "Kelime"nin üst
  /// çizgisinden belirgin aşağıda konumlanır.
  static const double bubbleOffsetFactor = 0.06;

  /// Varsayılan KelimeVSLogo (Varyant A konuşma balonlu logo)
  const KelimeVSLogo({
    super.key,
    this.fontSize = 64.0,
  });

  /// Geriye dönük uyumluluk için Varyant A adlandırması
  const KelimeVSLogo.bubbleVariantA({
    super.key,
    this.fontSize = 64.0,
  });

  @override
  Widget build(BuildContext context) {
    const bubbleColor = AppColors.primary;
    const vsColor = AppColors.card;
    final spacing = fontSize * 0.04;

    final vsFontSize = fontSize * 0.48;
    final customRadius = fontSize * 0.18;
    final customNipWidth = fontSize * 0.10;
    final customNipHeight = fontSize * 0.17;

    final baseHPadding = fontSize * 0.14;
    final vPadding = fontSize * 0.08;

    final innerPadding = EdgeInsets.only(
      left: baseHPadding + customNipWidth,
      right: baseHPadding,
      top: vPadding,
      bottom: vPadding,
    );

    final bubbleWidget = CustomPaint(
      painter: BubblePainter(
        color: bubbleColor,
        nipPosition: BubbleNipPosition.bottomLeft,
        customNipWidth: customNipWidth,
        customNipHeight: customNipHeight,
        customRadius: customRadius,
      ),
      child: Padding(
        padding: innerPadding,
        child: Text(
          'VS',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFredoka,
            fontSize: vsFontSize,
            fontWeight: FontWeight.w700,
            color: vsColor,
            letterSpacing: -0.8,
            height: 1.05,
          ),
        ),
      ),
    );

    return Semantics(
      label: 'KelimeVS',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Kelime',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: -1.2,
                height: 1.05,
              ),
            ),
            SizedBox(width: spacing),
            Padding(
              padding: EdgeInsets.only(
                top: fontSize * bubbleOffsetFactor,
                bottom: fontSize * bubbleOffsetFactor,
              ),
              child: Transform.translate(
                offset: Offset(0, fontSize * bubbleOffsetFactor),
                child: bubbleWidget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
