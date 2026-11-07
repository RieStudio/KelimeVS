import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../strings/app_strings.dart';
import '../theme/app_dimens.dart';

/// Tur sonu sonuç ikonunun varyantları.
enum RoundResultVariant {
  win,
  lose,
  draw,
}

/// DESIGN.md / Tur sonu ekranı SVG sonuç ikonu (kazandın, kaybettin, berabere).
///
/// `assets/icons/round_win.svg`, `round_lose.svg`, `round_draw.svg` dosyalarını çizer.
/// SVG'de işaret daireden hafifçe taştığı için [Clip.none] kullanılır ve [ClipRect]
/// ile kırpılmaz.
///
/// Girişte 350 ms'lik belirme animasyonu (ölçek Curves.easeOutBack + opaklık Curves.easeOut)
/// çalışır. Sistem hareket azaltma ayarı açıksa animasyonsuz doğrudan çizilir.
class RoundResultIcon extends StatefulWidget {
  final RoundResultVariant variant;
  final double size;
  final EdgeInsetsGeometry padding;

  const RoundResultIcon({
    super.key,
    required this.variant,
    this.size = AppDimens.avatarEnd,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  });

  const RoundResultIcon.win({
    super.key,
    this.size = AppDimens.avatarEnd,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  }) : variant = RoundResultVariant.win;

  const RoundResultIcon.lose({
    super.key,
    this.size = AppDimens.avatarEnd,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  }) : variant = RoundResultVariant.lose;

  const RoundResultIcon.draw({
    super.key,
    this.size = AppDimens.avatarEnd,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  }) : variant = RoundResultVariant.draw;

  static const String winAsset = 'assets/icons/round_win.svg';
  static const String loseAsset = 'assets/icons/round_lose.svg';
  static const String drawAsset = 'assets/icons/round_draw.svg';

  String get assetPath {
    switch (variant) {
      case RoundResultVariant.win:
        return winAsset;
      case RoundResultVariant.lose:
        return loseAsset;
      case RoundResultVariant.draw:
        return drawAsset;
    }
  }

  String get semanticLabel {
    switch (variant) {
      case RoundResultVariant.win:
        return AppStrings.roundWonTitle;
      case RoundResultVariant.lose:
        return AppStrings.roundLostTitle;
      case RoundResultVariant.draw:
        return AppStrings.roundDrawTitle;
    }
  }

  @override
  State<RoundResultIcon> createState() => _RoundResultIconState();
}

class _RoundResultIconState extends State<RoundResultIcon>
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
    final Widget svg = Padding(
      padding: widget.padding,
      child: SvgPicture.asset(
        widget.assetPath,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        clipBehavior: Clip.none,
        semanticsLabel: widget.semanticLabel,
      ),
    );

    final Widget content = ExcludeSemantics(child: svg);

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      return content;
    }

    return FadeTransition(
      opacity: _opacityAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: content,
      ),
    );
  }
}

