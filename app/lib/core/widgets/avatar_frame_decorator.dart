import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AvatarFrameType {
  classic,
  mint,
  sunset,
  ocean,
  gold,
  neon,
  rainbow,
  diamond,
  vine,
  silverEngraved,
  bronzeEngraved,
  goldLeaf;

  bool get isVisual =>
      this == AvatarFrameType.vine ||
      this == AvatarFrameType.silverEngraved ||
      this == AvatarFrameType.bronzeEngraved ||
      this == AvatarFrameType.goldLeaf;

  bool get isProcedural => !isVisual;

  static AvatarFrameType fromId(String? id) {
    if (id == null) return AvatarFrameType.classic;
    switch (id.trim().toLowerCase()) {
      case 'mint':
        return AvatarFrameType.mint;
      case 'sunset':
        return AvatarFrameType.sunset;
      case 'ocean':
        return AvatarFrameType.ocean;
      case 'gold':
        return AvatarFrameType.gold;
      case 'neon':
        return AvatarFrameType.neon;
      case 'rainbow':
        return AvatarFrameType.rainbow;
      case 'diamond':
        return AvatarFrameType.diamond;
      case 'vine':
        return AvatarFrameType.vine;
      case 'silver_engraved':
        return AvatarFrameType.silverEngraved;
      case 'bronze_engraved':
        return AvatarFrameType.bronzeEngraved;
      case 'gold_leaf':
        return AvatarFrameType.goldLeaf;
      case 'classic':
      default:
        return AvatarFrameType.classic;
    }
  }
}

/// Avatar etrafındaki neo-brutalist dekoratif çerçeveyi çizen CustomPainter.
/// Harf kontrastını ve iç avatar boyutunu bozmaz.
/// Elmas, Neon ve diğer tüm çerçeveler açık zeminlerde kaybolmamak için
/// 1.5 px dış Ink (#14532D) kenarlıkla sınırlandırılmıştır.
class AvatarFramePainter extends CustomPainter {
  final AvatarFrameType frameType;
  final double borderWidth;

  const AvatarFramePainter({
    required this.frameType,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    switch (frameType) {
      case AvatarFrameType.classic:
      case AvatarFrameType.vine:
      case AvatarFrameType.silverEngraved:
      case AvatarFrameType.bronzeEngraved:
      case AvatarFrameType.goldLeaf:
        // Klasik (veya görsel çerçeve fallback'i): Tek katmanlı sağlam Ink kenarlık
        final paint = Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;
        canvas.drawCircle(center, outerRadius - borderWidth / 2, paint);
        break;

      case AvatarFrameType.mint:
        // Nane: 1.5 px dış Ink + iç parlak Nane şeridi
        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: Paint()
            ..color = AppColors.mint
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth,
        );
        break;

      case AvatarFrameType.sunset:
        // Gün Batımı: 1.5 px dış Ink + sıcak turuncu-mercan gradyan
        final gradientPaint = Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFFF97316),
              Color(0xFFEC4899),
              Color(0xFFF43F5E),
              Color(0xFFF97316),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: gradientPaint,
        );
        break;

      case AvatarFrameType.ocean:
        // Okyanus: 1.5 px dış Ink + turkuaz-mavi gradyan
        final gradientPaint = Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFF06B6D4),
              Color(0xFF2563EB),
              Color(0xFF0284C7),
              Color(0xFF06B6D4),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: gradientPaint,
        );
        break;

      case AvatarFrameType.gold:
        // Altın: 1.5 px dış Ink + şampiyon altın ışıltısı
        final goldPaint = Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFFFACC15),
              Color(0xFFD97706),
              Color(0xFFFDE047),
              Color(0xFFFACC15),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: goldPaint,
        );
        break;

      case AvatarFrameType.neon:
        // Neon: Açık zemin kontrastı için 1.5 px dış Ink + 3.5 px elektrik neon yeşili
        final neonPaint = Paint()
          ..color = const Color(0xFFA3E635)
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: neonPaint,
        );
        break;

      case AvatarFrameType.rainbow:
        // Gökkuşağı: 1.5 px dış Ink + 360° kesintisiz renk spektrumu
        final rainbowPaint = Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFFEF4444),
              Color(0xFFF97316),
              Color(0xFFFACC15),
              Color(0xFF22C55E),
              Color(0xFF3B82F6),
              Color(0xFFA855F7),
              Color(0xFFEF4444),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: rainbowPaint,
        );
        break;

      case AvatarFrameType.diamond:
        // Elmas: Beyaz kart zemininde kaybolmaması için 1.5 px dış Ink + kristal elmas buz mavisi
        final diamondPaint = Paint()
          ..shader = const SweepGradient(
            colors: [
              Color(0xFFE0F2FE),
              Color(0xFF38BDF8),
              Color(0xFFFFFFFF),
              Color(0xFF0284C7),
              Color(0xFFE0F2FE),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth;

        _drawDualRing(
          canvas,
          center,
          outerRadius,
          inkWidth: 1.5,
          colorWidth: borderWidth,
          innerPaint: diamondPaint,
        );
        break;
    }
  }

  void _drawDualRing(
    Canvas canvas,
    Offset center,
    double outerRadius, {
    required double inkWidth,
    required double colorWidth,
    required Paint innerPaint,
  }) {
    // 1. Dış Ink kontur
    final outerInkPaint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = inkWidth;
    canvas.drawCircle(center, outerRadius - inkWidth / 2, outerInkPaint);

    // 2. Renkli / gradyanlı iç halka
    final colorRadius = outerRadius - inkWidth - (colorWidth / 2);
    if (colorRadius > 0) {
      canvas.drawCircle(center, colorRadius, innerPaint);
    }

    // 3. İç ayrım çizgisi (1 px ince Ink sınır ile avatar zeminiyle kusursuz kontrast)
    final innerInkPaint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final innerInkRadius = outerRadius - inkWidth - colorWidth - 0.5;
    if (innerInkRadius > 0) {
      canvas.drawCircle(center, innerInkRadius, innerInkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AvatarFramePainter oldDelegate) {
    return oldDelegate.frameType != frameType ||
        oldDelegate.borderWidth != borderWidth;
  }
}

