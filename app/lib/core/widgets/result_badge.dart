import 'package:flutter/material.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

enum ResultBadgeVariant { won, lost }

/// DESIGN.md Bölüm 6: Sonuç Etiketi (ResultBadge)
/// Genişlik: 88 (sabit), Yazı ortalı, Nunito 12/800, Köşe 12, 2 px kenarlık.
/// Kazandın: primary zemin + beyaz yazı + ink kenarlık.
/// Kaybettin: danger zemin + beyaz yazı + dangerDark kenarlık.
class ResultBadge extends StatelessWidget {
  final ResultBadgeVariant variant;

  const ResultBadge({
    super.key,
    required this.variant,
  });

  const ResultBadge.won({super.key}) : variant = ResultBadgeVariant.won;

  const ResultBadge.lost({super.key}) : variant = ResultBadgeVariant.lost;

  @override
  Widget build(BuildContext context) {
    final isWon = variant == ResultBadgeVariant.won;

    final bgColor = isWon ? AppColors.primary : AppColors.danger;
    final borderColor = isWon ? AppColors.ink : AppColors.dangerDark;
    final text = isWon ? AppStrings.won : AppStrings.lost;

    return Semantics(
      label: text,
      child: Container(
        width: AppDimens.resultBadgeWidth,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppDimens.borderRadiusBadge,
          border: Border.all(
            color: borderColor,
            width: AppDimens.borderThin,
          ),
        ),
        child: Text(
          text,
          style: AppTextStyles.resultBadge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

