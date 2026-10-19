import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Kelimeta Logo
/// "Kelime" (Fredoka 700, ink) + "ta" (Fredoka 700, primary).
/// "ta" arkasında mint renkli, yuvarlatılmış, sağa bakan oynat (play) üçgeni.
/// Üçgenin kenarlığı ve gölgesi yoktur. Logo eğik ya da döndürülmüş olmaz.
class KelimetaLogo extends StatelessWidget {
  final double fontSize;

  const KelimetaLogo({
    super.key,
    this.fontSize = 64.0,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kelimeta',
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
            SizedBox(width: fontSize * 0.02),
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
                    left: fontSize * 0.16,
                    right: fontSize * 0.32,
                    top: fontSize * 0.04,
                    bottom: fontSize * 0.04,
                  ),
                  child: Text(
                    'ta',
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
    final p1 = const Offset(0, 0); // Üst-sol
    final p2 = Offset(0, size.height); // Alt-sol
    final p3 = Offset(size.width, size.height / 2); // Sağ uç

    final path = _getRoundedTrianglePath([p1, p2, p3], 14.0);
    canvas.drawPath(path, paint);
  }

  Path _getRoundedTrianglePath(List<Offset> points, double radius) {
    final path = Path();
    final count = points.length;

    for (int i = 0; i < count; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % count];
      final p3 = points[(i + 2) % count];

      final v1 = Offset(p1.dx - p2.dx, p1.dy - p2.dy);
      final v2 = Offset(p3.dx - p2.dx, p3.dy - p2.dy);

      final d1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy);
      final d2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);

      final u1 = Offset(v1.dx / d1, v1.dy / d1);
      final u2 = Offset(v2.dx / d2, v2.dy / d2);

      final dot = u1.dx * u2.dx + u1.dy * u2.dy;
      final angle = math.acos(dot.clamp(-1.0, 1.0));

      final dist = radius / math.tan(angle / 2);

      final startPt = Offset(p2.dx + u1.dx * dist, p2.dy + u1.dy * dist);
      final endPt = Offset(p2.dx + u2.dx * dist, p2.dy + u2.dy * dist);

      if (i == 0) {
        path.moveTo(startPt.dx, startPt.dy);
      } else {
        path.lineTo(startPt.dx, startPt.dy);
      }

      path.quadraticBezierTo(p2.dx, p2.dy, endPt.dx, endPt.dy);
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}

