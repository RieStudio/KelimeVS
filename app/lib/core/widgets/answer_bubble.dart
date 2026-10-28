import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: Cevap Balonu
///
/// Nunito 15/800, dolgu: kendi cevabın bright, rakip cevabı card;
/// 2 px ink kenarlık, köşe 14, iç boşluk 7x14, en geniş %78.
/// Kendi cevabın sağa, rakibinki sola hizalanır.
///
/// WhatsApp tarzı konuşma çentiği (kuyruk):
/// - Kendi balonun (isMe=true): kuyruk sağ üst köşede dışa doğru.
/// - Rakip balonu (isMe=false): kuyruk sol üst köşede dışa doğru.
/// - Çentik, art arda gelen aynı göndericinin yalnızca İLK balonunda gösterilir (showTail=true).
/// - Devam eden balonlarda (showTail=false) çentik çizilmez; ancak dış boşluk (margin)
///   sayesinde balon gövdesi ve metin ilk balonla piksel piksel dikeyde aynı hizada kalır.
/// - Dolgu, kenarlık ve seçim gölgesi BubblePainter ile tek bir sürekli Path olarak çizilir.
class AnswerBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isRejected;
  final bool isSelected;
  final bool showTail;
  final VoidCallback? onTap;

  const AnswerBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isRejected = false,
    this.isSelected = false,
    this.showTail = true,
    this.onTap,
  });

  const AnswerBubble.rejected({
    super.key,
    required this.text,
    required this.isMe,
    this.isSelected = false,
    this.showTail = true,
    this.onTap,
  }) : isRejected = true;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth > 0 ? screenWidth * 0.78 : 300.0;

    final bgColor = isRejected
        ? AppColors.card
        : (isMe ? AppColors.bright : AppColors.card);
    final borderColor = isRejected ? AppColors.danger : AppColors.ink;
    final textStyle = isRejected
        ? AppTextStyles.answerBubbleRejected
        : AppTextStyles.answerBubble;
    final borderWidth = isSelected ? AppDimens.borderThick : AppDimens.borderThin;

    const nipWidth = BubblePainter.nipWidth;

    final EdgeInsets innerPadding;
    final EdgeInsets outerMargin;

    if (showTail) {
      outerMargin = EdgeInsets.zero;
      if (isMe) {
        innerPadding = const EdgeInsets.only(
          left: 14.0,
          right: 14.0 + nipWidth,
          top: 7.0,
          bottom: 7.0,
        );
      } else {
        innerPadding = const EdgeInsets.only(
          left: 14.0 + nipWidth,
          right: 14.0,
          top: 7.0,
          bottom: 7.0,
        );
      }
    } else {
      outerMargin = EdgeInsets.only(
        left: !isMe ? nipWidth : 0.0,
        right: isMe ? nipWidth : 0.0,
      );
      innerPadding = const EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 7.0,
      );
    }

    // Çok uzun kelimelerin (örn. 10+ harf) dar ekranlarda taşmasını önlemek için
    // kelime içine görünmez kesme noktası (zero-width space) eklenir.
    final wrapSafeText = text.replaceAllMapped(
      RegExp(r'\S{10,}'),
      (match) => match.group(0)!.split('').join('\u200B'),
    );

    final bubbleContent = CustomPaint(
      painter: BubblePainter(
        color: bgColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        isMe: isMe,
        showTail: showTail,
        isSelected: isSelected,
        isRejected: isRejected,
      ),
      child: Padding(
        padding: innerPadding,
        child: Text(
          wrapSafeText,
          style: textStyle,
          softWrap: true,
        ),
      ),
    );

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: Padding(
        padding: outerMargin,
        child: bubbleContent,
      ),
    );

    final clickableBubble = onTap != null
        ? GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: bubble,
          )
        : bubble;

    return RepaintBoundary(
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: clickableBubble,
      ),
    );
  }
}

/// WhatsApp tarzı çentikli/yuvarlak köşeli balon çizici
class BubblePainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool isMe;
  final bool showTail;
  final bool isSelected;
  final bool isRejected;

  static const double nipWidth = 6.0;
  static const double nipHeight = 11.0;
  static const double cornerRadius = 14.0;

  const BubblePainter({
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.isMe,
    required this.showTail,
    required this.isSelected,
    required this.isRejected,
  });

  Path _buildPath(Size size) {
    final halfStroke = borderWidth / 2.0;
    final left = halfStroke;
    final top = halfStroke;
    final right = size.width - halfStroke;
    final bottom = size.height - halfStroke;

    final width = right - left;
    final height = bottom - top;

    final r = math.min(
      cornerRadius - halfStroke,
      math.min(width / 2.0, height / 2.0),
    );
    final path = Path();

    if (!showTail) {
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, bottom),
        Radius.circular(r),
      ));
      return path;
    }

    final effectiveNipW = math.min(nipWidth, width / 3.0);
    final effectiveNipH = math.min(nipHeight, math.max(0.0, height - r));

    if (isMe) {
      // Kendi balonumuz: Kuyruk sağ üst köşede dışa doğru
      final bodyRight = right - effectiveNipW;

      // Sol üst köşeden başla
      path.moveTo(left + r, top);
      // Üst kenar gövdeden kuyruk ucuna uzanır
      path.lineTo(right - 1.5, top);
      // Kuyruk ucu yumuşak kavis
      path.quadraticBezierTo(right, top, right, top + 1.5);
      // WhatsApp tarzı içe kıvrılan kavis (gövde dikey duvarına teğet varış)
      path.cubicTo(
        right - 1.0,
        top + (effectiveNipH * 0.4),
        bodyRight,
        top + (effectiveNipH * 0.7),
        bodyRight,
        top + effectiveNipH,
      );
      // Sağ dikey duvar
      path.lineTo(bodyRight, bottom - r);
      // Sağ alt köşe
      path.arcToPoint(
        Offset(bodyRight - r, bottom),
        radius: Radius.circular(r),
        clockwise: true,
      );
      // Alt kenar
      path.lineTo(left + r, bottom);
      // Sol alt köşe
      path.arcToPoint(
        Offset(left, bottom - r),
        radius: Radius.circular(r),
        clockwise: true,
      );
      // Sol dikey duvar
      path.lineTo(left, top + r);
      // Sol üst köşe
      path.arcToPoint(
        Offset(left + r, top),
        radius: Radius.circular(r),
        clockwise: true,
      );
      path.close();
    } else {
      // Rakip balonu: Kuyruk sol üst köşede dışa doğru
      final bodyLeft = left + effectiveNipW;

      // Sol üst duvardan kuyruk ucuna kavisle başla
      path.moveTo(bodyLeft, top + effectiveNipH);
      // WhatsApp tarzı dışa kıvrılan kavis
      path.cubicTo(
        bodyLeft,
        top + (effectiveNipH * 0.7),
        left + 1.0,
        top + (effectiveNipH * 0.4),
        left,
        top + 1.5,
      );
      // Kuyruk ucu yumuşak kavis
      path.quadraticBezierTo(left, top, left + 1.5, top);
      // Üst kenar sağa uzanır
      path.lineTo(right - r, top);
      // Sağ üst köşe
      path.arcToPoint(
        Offset(right, top + r),
        radius: Radius.circular(r),
        clockwise: true,
      );
      // Sağ dikey duvar
      path.lineTo(right, bottom - r);
      // Sağ alt köşe
      path.arcToPoint(
        Offset(right - r, bottom),
        radius: Radius.circular(r),
        clockwise: true,
      );
      // Alt kenar
      path.lineTo(bodyLeft + r, bottom);
      // Sol alt köşe
      path.arcToPoint(
        Offset(bodyLeft, bottom - r),
        radius: Radius.circular(r),
        clockwise: true,
      );
      // Sol dikey duvar (kuyruk birleşimine kadar)
      path.lineTo(bodyLeft, top + effectiveNipH);
      path.close();
    }

    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    if (isSelected) {
      final shadow = BoxShadow(
        color: (isRejected ? AppColors.danger : AppColors.ink).withAlpha(51),
        blurRadius: 4,
        offset: const Offset(0, 2),
      );
      canvas.drawPath(path.shift(shadow.offset), shadow.toPaint());
    }

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant BubblePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.isMe != isMe ||
        oldDelegate.showTail != showTail ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isRejected != isRejected;
  }
}
