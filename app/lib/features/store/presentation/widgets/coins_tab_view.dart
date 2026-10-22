import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';

/// DESIGN.md 9a: Jeton Sekmesi Görünümü
/// 1. Sürümde "Jeton Paketleri Çok Yakında" bilgi kartı gösterilir.
class CoinsTabView extends StatelessWidget {
  const CoinsTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space24,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThin,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Jeton Simgesi Dairesi
              Container(
                width: 64,
                height: 64,
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
                    fontSize: 32,
                    color: AppColors.ink,
                    height: 1.0,
                  ),
                ),
              ),

              const SizedBox(height: AppDimens.space16),

              const Text(
                AppStrings.coinsTabTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFredoka,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: AppColors.ink,
                ),
              ),

              const SizedBox(height: AppDimens.space8),

              const Text(
                AppStrings.coinsTabDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
