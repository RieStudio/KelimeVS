import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../strings/app_strings.dart';
import '../theme/app_dimens.dart';

/// Maç sonu sonuç ikonunun varyantları.
enum MatchResultVariant {
  win,
  lose,
}

/// DESIGN.md / Maç sonu ekranı SVG sonuç ikonu (kazandın, kaybettin).
///
/// `assets/icons/match_win.svg`, `match_lose.svg` dosyalarını çizer.
/// SVG'de kupa tutacakları ve ok ucu kenara yakın olduğu için [Clip.none]
/// kullanılır ve [ClipRect] ile kırpılmaz.
///
/// Girişte 350 ms'lik belirme animasyonu (ölçek Curves.easeOutBack + opaklık Curves.easeOut)
/// çalışır. Sistem hareket azaltma ayarı açıksa animasyonsuz doğrudan çizilir.
class MatchResultIcon extends StatefulWidget {
  final MatchResultVariant variant;
  final double size;
  final EdgeInsetsGeometry padding;

  const MatchResultIcon({
    super.key,
    required this.variant,
    this.size = AppDimens.matchEndIcon,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  });

  const MatchResultIcon.win({
    super.key,
    this.size = AppDimens.matchEndIcon,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  }) : variant = MatchResultVariant.win;

  const MatchResultIcon.lose({
    super.key,
    this.size = AppDimens.matchEndIcon,
    this.padding = const EdgeInsets.all(AppDimens.space4),
  }) : variant = MatchResultVariant.lose;

  static const String winAsset = 'assets/icons/match_win.svg';
  static const String loseAsset = 'assets/icons/match_lose.svg';

  String get assetPath {
    switch (variant) {
      case MatchResultVariant.win:
        return winAsset;
      case MatchResultVariant.lose:
        return loseAsset;
    }
  }

  String get semanticLabel {
    switch (variant) {
      case MatchResultVariant.win:
        return AppStrings.wonExclamation;
      case MatchResultVariant.lose:
        return AppStrings.lost;
    }
  }

  @override
  State<MatchResultIcon> createState() => _MatchResultIconState();
}

class _MatchResultIconState extends State<MatchResultIcon>
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

