import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'smooth_progress_bar.dart';

/// Eşleşme ekranı (rakip bulundu dolum çubuğu) ve tur geçişi (RoundEndView geri sayım çubuğu)
/// için ortak, standart 14 dp yükseklikte ilerleme çubuğu.
///
/// Her iki ekranda da mint zemin, ink kenarlık, tam yuvarlak köşeler ve primary dolgu kullanılır.
class AppProgressBar extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const AppProgressBar._({
    super.key,
    required this.child,
    this.maxWidth,
  });

  /// Geri sayım (tur sonu ekranı vb.) için SmoothProgressBar kullanan yapıcı.
  factory AppProgressBar.countdown({
    Key? key,
    required int totalDurationMs,
    required int remainingMs,
    bool isActive = true,
    bool isPaused = false,
    double? maxWidth,
  }) {
    return AppProgressBar._(
      key: key,
      maxWidth: maxWidth,
      child: SmoothProgressBar(
        totalDurationMs: totalDurationMs,
        remainingMs: remainingMs,
        isActive: isActive,
        isPaused: isPaused,
        fillColor: AppColors.primary,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: AppDimens.borderRadiusFull,
        ),
      ),
    );
  }

  /// Soldan sağa 0.0'dan 1.0'a dolan (eşleşme rakip tanıtımı vb.) çubuk için yapıcı.
  factory AppProgressBar.filling({
    Key? key,
    required Duration fillDuration,
    double? maxWidth,
  }) {
    return AppProgressBar._(
      key: key,
      maxWidth: maxWidth,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: fillDuration,
        curve: Curves.linear,
        builder: (context, value, _) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              color: AppColors.primary,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget bar = Container(
      width: double.infinity,
      height: 14.0,
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: AppDimens.borderRadiusFull,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
      ),
      child: ClipRRect(
        borderRadius: AppDimens.borderRadiusFull,
        child: child,
      ),
    );

    if (maxWidth != null) {
      bar = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: bar,
      );
    }

    return bar;
  }
}

