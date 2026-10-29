import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 7: Jeton Hapı (CoinPill)
/// Beyaz hap (`card`), 2 px `ink` kenarlık, tam yuvarlak köşeler.
/// İçinde `coin` zeminli daire içinde "G" ve Fredoka 18/600 sayı.
class CoinPill extends StatelessWidget {
  final int amount;

  const CoinPill({
    super.key,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$amount${AppStrings.coinSuffix}',
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 110.0,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space6,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppDimens.borderRadiusFull,
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Jeton Dairesi ("G")
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.coin,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFredoka,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.ink,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.space8),
            // Sayı
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$amount',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: AppColors.ink,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
