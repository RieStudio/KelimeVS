import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import 'avatar_frame_decorator.dart';
import 'avatar_frame_registry.dart';

enum PlayerAvatarVariant {
  selfHome, // bright zemin + ink harf
  selfMatch, // primary zemin + beyaz (card) harf
  opponent, // coin zemin + ink harf
  unknown, // beyaz (card) zemin + kesik çizgili kenarlık + "?"
}

/// DESIGN.md Bölüm 6: Avatar
/// Tam yuvarlak, 3 px (liste için 2 px) kenarlık,
/// seçili avatar çerçevesi ve ortada oyuncu adının baş harfi (Fredoka 700).
class PlayerAvatar extends StatelessWidget {
  final PlayerAvatarVariant variant;
  final String? name;
  final String? frame;
  final double size;
  final double? borderWidth;

  const PlayerAvatar({
    super.key,
    required this.variant,
    this.name,
    this.frame = 'classic',
    this.size = AppDimens.avatarHome,
    this.borderWidth,
  });

  const PlayerAvatar.selfHome({
    super.key,
    this.name,
    this.frame = 'classic',
    this.size = AppDimens.avatarHome,
    this.borderWidth,
  }) : variant = PlayerAvatarVariant.selfHome;

  const PlayerAvatar.selfMatch({
    super.key,
    this.name,
    this.frame = 'classic',
    this.size = AppDimens.avatarMatch,
    this.borderWidth,
  }) : variant = PlayerAvatarVariant.selfMatch;

  const PlayerAvatar.opponent({
    super.key,
    this.name,
    this.frame = 'classic',
    this.size = AppDimens.avatarHome,
    this.borderWidth,
  }) : variant = PlayerAvatarVariant.opponent;

  const PlayerAvatar.unknown({
    super.key,
    this.size = AppDimens.avatarSearch,
    this.borderWidth,
  })  : variant = PlayerAvatarVariant.unknown,
        name = null,
        frame = null;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderWidth = borderWidth ?? AppDimens.borderThick;

    final Color bgColor;
    final Color textColor;

    switch (variant) {
      case PlayerAvatarVariant.selfHome:
        bgColor = AppColors.bright;
        textColor = AppColors.ink;
        break;
      case PlayerAvatarVariant.selfMatch:
        bgColor = AppColors.primary;
        textColor = AppColors.card;
        break;
      case PlayerAvatarVariant.opponent:
        bgColor = AppColors.coin;
        textColor = AppColors.ink;
        break;
      case PlayerAvatarVariant.unknown:
        bgColor = AppColors.card;
        textColor = AppColors.ink;
        break;
    }

    final String displayChar;
    if (variant == PlayerAvatarVariant.unknown || name == null || name!.trim().isEmpty) {
      displayChar = AppStrings.questionMark;
    } else {
      final firstRune = name!.trim().runes.first;
      final rawChar = String.fromCharCode(firstRune);
      displayChar = rawChar == 'i'
          ? 'İ'
          : rawChar == 'ı'
              ? 'I'
              : rawChar.toUpperCase();
    }

    final isUnknown = variant == PlayerAvatarVariant.unknown;
    final visualDef = isUnknown ? null : VisualFrameRegistry.getDefinition(frame);

    final Widget avatarContent;

    if (isUnknown) {
      avatarContent = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DashedCirclePainter(
                  color: AppColors.ink,
                  strokeWidth: effectiveBorderWidth,
                  dashCount: (size / 3.2).clamp(12, 36).round(),
                ),
              ),
            ),
            Center(
              child: Text(
                displayChar,
                style: AppTextStyles.avatarInitial.copyWith(
                  fontSize: size * 0.46,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    } else if (visualDef != null) {
      final dims = VisualFrameRegistry.calculateDimensions(
        baseAvatarSize: size,
        innerRatio: visualDef.innerRatio,
      );

      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final cacheW = (dims.frameSize * dpr).round().clamp(1, 1024);

      avatarContent = SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 1. Merkezdeki Avatar Dairesi
            Container(
              width: dims.avatarSize,
              height: dims.avatarSize,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  displayChar,
                  style: AppTextStyles.avatarInitial.copyWith(
                    fontSize: dims.avatarSize * 0.46,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // 2. Dışa Büyüyen Görsel Çerçeve Katmanı (Dokunmaları engellemez)
            IgnorePointer(
              child: Image.asset(
                visualDef.assetPath,
                width: dims.frameSize,
                height: dims.frameSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                cacheWidth: cacheW,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  // Varlık yüklenemezse güvenli geri dönüş: Klasik çerçeve painter
                  return SizedBox(
                    width: dims.avatarSize,
                    height: dims.avatarSize,
                    child: CustomPaint(
                      painter: AvatarFramePainter(
                        frameType: AvatarFrameType.classic,
                        borderWidth: effectiveBorderWidth,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    } else {
      // Prosedürel çerçeveler (classic, mint, sunset, ocean, gold, neon, rainbow, diamond veya bilinmeyen)
      avatarContent = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: AvatarFramePainter(
                  frameType: AvatarFrameType.fromId(frame),
                  borderWidth: effectiveBorderWidth,
                ),
              ),
            ),
            Center(
              child: Text(
                displayChar,
                style: AppTextStyles.avatarInitial.copyWith(
                  fontSize: size * 0.46,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: isUnknown
          ? AppStrings.opponent
          : AppStrings.avatarSemantics(name: name, frameId: frame),
      child: avatarContent,
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;

  const _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * math.pi * radius;
    final dashLength = circumference / (dashCount * 2);
    final dashAngle = dashLength / radius;
    final gapAngle = dashAngle;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * (dashAngle + gapAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashCount != dashCount;
  }
}

