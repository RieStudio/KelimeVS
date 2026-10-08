import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// DESIGN.md Bölüm 7 (Tur sonu & Maç sonucu) ortak sonuç dairesi varyantları
enum ResultCircleVariant {
  win,
  lose,
  draw,
}

/// DESIGN.md Bölüm 7: 104 px Sonuç İkon Dairesi (ResultCircle)
///
/// - win: bright zemin, 4 px ink kenarlık ve sert gölge
/// - lose: dangerSoft zemin, 4 px dangerDark kenarlık ve sert gölge
/// - draw: mint zemin, 4 px ink kenarlık ve sert gölge
///
/// Girişte 350 ms'lik belirme animasyonu (ölçek + opaklık) çalışır.
/// Sistem hareket azaltma ayarı açıksa animasyonsuz doğrudan çizilir.
/// Ekran okuyucularda semantik dışı (dekoratif) olarak işaretlenir.
class ResultCircle extends StatefulWidget {
  final ResultCircleVariant variant;
  final AppIconData icon;
  final double size;
  final double iconSize;

  const ResultCircle({
    super.key,
    required this.variant,
    required this.icon,
    this.size = AppDimens.avatarEnd,
    this.iconSize = 48.0,
  });

  const ResultCircle.win({
    super.key,
    required this.icon,
    this.size = AppDimens.avatarEnd,
    this.iconSize = 48.0,
  }) : variant = ResultCircleVariant.win;

  const ResultCircle.lose({
    super.key,
    required this.icon,
    this.size = AppDimens.avatarEnd,
    this.iconSize = 48.0,
  }) : variant = ResultCircleVariant.lose;

  const ResultCircle.draw({
    super.key,
    required this.icon,
    this.size = AppDimens.avatarEnd,
    this.iconSize = 48.0,
  }) : variant = ResultCircleVariant.draw;

  @override
  State<ResultCircle> createState() => _ResultCircleState();
}

class _ResultCircleState extends State<ResultCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final List<BoxShadow> shadow;

    switch (widget.variant) {
      case ResultCircleVariant.win:
        bgColor = AppColors.bright;
        borderColor = AppColors.ink;
        iconColor = AppColors.ink;
        shadow = AppDimens.shadowResultCircleWin;
      case ResultCircleVariant.lose:
        bgColor = AppColors.dangerSoft;
        borderColor = AppColors.dangerDark;
        iconColor = AppColors.dangerText;
        shadow = AppDimens.shadowResultCircleLose;
      case ResultCircleVariant.draw:
        bgColor = AppColors.mint;
        borderColor = AppColors.ink;
        iconColor = AppColors.ink;
        shadow = AppDimens.shadowResultCircleWin;
    }

    final Widget circleWidget = ExcludeSemantics(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor,
            width: AppDimens.borderResultCircle,
          ),
          boxShadow: shadow,
        ),
        alignment: Alignment.center,
        child: AppIcon(
          widget.icon,
          color: iconColor,
          size: widget.iconSize,
        ),
      ),
    );

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      return circleWidget;
    }

    return FadeTransition(
      opacity: _opacityAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: circleWidget,
      ),
    );
  }
}

