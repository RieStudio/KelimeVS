import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 1 ve 3: Logo
/// "Kelime" (64, Fredoka 700, ink) + "Go" (64, Fredoka 700, primary).
/// "Go" arkasında mint renkli, yuvarlatılmış, sağa bakan oynat (play) üçgeni.
/// Üçgenin kenarlığı ve gölgesi yoktur. Logo eğik ya da döndürülmüş olmaz.
class KelimeGoLogo extends StatelessWidget {
  final double fontSize;

  const KelimeGoLogo({
    super.key,
    this.fontSize = 64.0,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kelime Go',
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
          SizedBox(width: fontSize * 0.08),
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PlayTrianglePainter(color: AppColors.mint),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: fontSize * 0.22,
                  right: fontSize * 0.38,
                  top: fontSize * 0.04,
                  bottom: fontSize * 0.04,
                ),
                child: Text(
                  'Go',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: -1.2,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}

class _PlayTrianglePainter extends CustomPainter {
  final Color color;

  const _PlayTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Sağa bakan, köşeleri yuvarlatılmış oynat üçgeni
    final p1 = Offset(0, 0); // Üst-sol
    final p2 = Offset(0, size.height); // Alt-sol
    final p3 = Offset(size.width, size.height / 2); // Sağ uç

    final path = _getRoundedTrianglePath([p1, p2, p3], 14.0);
    canvas.drawPath(path, paint);
  }

  Path _getRoundedTrianglePath(List<Offset> points, double radius) {
    final path = Path();
    final count = points.length;

    for (int i = 0; i < count; i++) {
      final prev = points[(i - 1 + count) % count];
      final curr = points[i];
      final next = points[(i + 1) % count];

      final v1 = prev - curr;
      final v2 = next - curr;

      final len1 = v1.distance;
      final len2 = v2.distance;

      final effectiveRadius = math.min(radius, math.min(len1 / 2, len2 / 2));

      final pStart = curr + Offset(v1.dx / len1 * effectiveRadius, v1.dy / len1 * effectiveRadius);
      final pEnd = curr + Offset(v2.dx / len2 * effectiveRadius, v2.dy / len2 * effectiveRadius);

      if (i == 0) {
        path.moveTo(pStart.dx, pStart.dy);
      } else {
        path.lineTo(pStart.dx, pStart.dy);
      }

      path.quadraticBezierTo(curr.dx, curr.dy, pEnd.dx, pEnd.dy);
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

