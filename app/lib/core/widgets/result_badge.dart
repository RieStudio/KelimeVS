import 'package:flutter/material.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

enum ResultBadgeVariant { won, lost, draw, incomplete }

/// DESIGN.md Bölüm 6: Sonuç Etiketi (ResultBadge)
/// Genişlik: 88 (sabit), Yazı ortalı, Nunito 12/800, Köşe 12, 2 px kenarlık.
/// Kazandın: primary zemin + beyaz yazı + ink kenarlık.
/// Kaybettin: danger zemin + beyaz yazı + dangerDark kenarlık.
/// Berabere: card zemin + ink yazı + ink kenarlık (nötr etiket).
/// Yarım kaldı: card zemin + ink yazı + ink kenarlık (nötr etiket).
class ResultBadge extends StatelessWidget {
  final ResultBadgeVariant variant;
  final double? width;
  final EdgeInsetsGeometry padding;

  const ResultBadge({
    super.key,
    required this.variant,
    this.width = AppDimens.resultBadgeWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.space10),
  });

  const ResultBadge.won({
    super.key,
    this.width = AppDimens.resultBadgeWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.space10),
  }) : variant = ResultBadgeVariant.won;

  const ResultBadge.lost({
    super.key,
    this.width = AppDimens.resultBadgeWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.space10),
  }) : variant = ResultBadgeVariant.lost;

  const ResultBadge.draw({
    super.key,
    this.width = AppDimens.resultBadgeWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.space10),
  }) : variant = ResultBadgeVariant.draw;

  const ResultBadge.incomplete({
    super.key,
    this.width = AppDimens.resultBadgeWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.space10),
  }) : variant = ResultBadgeVariant.incomplete;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String text;

    switch (variant) {
      case ResultBadgeVariant.won:
        bgColor = AppColors.primary;
        borderColor = AppColors.ink;
        textColor = AppColors.card;
        text = AppStrings.won;
        break;
      case ResultBadgeVariant.lost:
        bgColor = AppColors.danger;
        borderColor = AppColors.dangerDark;
        textColor = AppColors.card;
        text = AppStrings.lost;
        break;
      case ResultBadgeVariant.draw:
        bgColor = AppColors.card;
        borderColor = AppColors.ink;
        textColor = AppColors.ink;
        text = AppStrings.draw;
        break;
      case ResultBadgeVariant.incomplete:
        bgColor = AppColors.card;
        borderColor = AppColors.ink;
        textColor = AppColors.ink;
        text = AppStrings.incomplete;
        break;
    }

    return Semantics(
      label: text,
      child: Container(
        width: width,
        height: 28,
        padding: padding,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppDimens.borderRadiusBadge,
          border: Border.all(
            color: borderColor,
            width: AppDimens.borderThin,
          ),
        ),
        child: Center(
          widthFactor: 1.0,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: AppTextStyles.resultBadge.copyWith(color: textColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

