import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// KelimeVS Logo
/// "Kelime" (Fredoka 700, ink) + "VS" (Fredoka 700, primary).
/// "VS" arkasında mint renkli, yuvarlatılmış, sağa bakan oynat (play) üçgeni.
/// Üçgenin kenarlığı ve gölgesi yoktur. Logo eğik ya da döndürülmüş olmaz.
class KelimeVSLogo extends StatelessWidget {
  final double fontSize;

  const KelimeVSLogo({
    super.key,
    this.fontSize = 64.0,
  });

  @override
  Widget build(BuildContext context) {
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
                    right: fontSize * 0.30,
                    top: fontSize * 0.04,
                    bottom: fontSize * 0.04,
                  ),
                  child: Text(
                    'VS',
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

    for (var i = 0; i < count; i++) {
      final pPrev = points[(i - 1 + count) % count];
      final pCurr = points[i];
      final pNext = points[(i + 1) % count];

      final vPrev = (pPrev - pCurr);
      final vNext = (pNext - pCurr);

      final lenPrev = vPrev.distance;
      final lenNext = vNext.distance;

      final actualRadius = math.min(radius, math.min(lenPrev, lenNext) / 2);

      final startPoint = pCurr + (vPrev / lenPrev) * actualRadius;
      final endPoint = pCurr + (vNext / lenNext) * actualRadius;

      if (i == 0) {
        path.moveTo(startPoint.dx, startPoint.dy);
      } else {
        path.lineTo(startPoint.dx, startPoint.dy);
      }

      path.quadraticBezierTo(pCurr.dx, pCurr.dy, endPoint.dx, endPoint.dy);
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}

