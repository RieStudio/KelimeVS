import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AvatarFrameType {
  classic,
  vine,
  silverEngraved,
  bronzeEngraved,
  goldLeaf,
  emerald,
  sakura,
  ice,
  gear,
  nazar;

  bool get isVisual => this != AvatarFrameType.classic;
  bool get isProcedural => this == AvatarFrameType.classic;

  static AvatarFrameType fromId(String? id) {
    if (id == null) return AvatarFrameType.classic;
    switch (id.trim().toLowerCase()) {
      case 'vine':
        return AvatarFrameType.vine;
      case 'silver_engraved':
        return AvatarFrameType.silverEngraved;
      case 'bronze_engraved':
        return AvatarFrameType.bronzeEngraved;
      case 'gold_leaf':
        return AvatarFrameType.goldLeaf;
      case 'emerald':
        return AvatarFrameType.emerald;
      case 'sakura':
        return AvatarFrameType.sakura;
      case 'ice':
        return AvatarFrameType.ice;
      case 'gear':
        return AvatarFrameType.gear;
      case 'nazar':
        return AvatarFrameType.nazar;
      case 'classic':
      default:
        return AvatarFrameType.classic;
    }
  }
}

/// Avatar etrafındaki neo-brutalist dekoratif çerçeveyi çizen CustomPainter.
/// Klasik çerçeve için sağlam 2.0-3.0 px Ink (#14532D) kenarlık çizer.
/// Görsel çerçevelerde resim yüklenene kadar veya resim yüklenemezse fallback olarak çalışır.
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

    final paint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(center, outerRadius - borderWidth / 2, paint);
  }

  @override
  bool shouldRepaint(covariant AvatarFramePainter oldDelegate) {
    return oldDelegate.frameType != frameType ||
        oldDelegate.borderWidth != borderWidth;
  }
}
