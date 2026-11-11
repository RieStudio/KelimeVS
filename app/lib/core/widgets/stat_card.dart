import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// Profil ve Herkese Açık Profil ekranlarında kullanılan standart istatistik kartı.
class StatCard extends StatelessWidget {
  final String label;
  final String value;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
        vertical: AppDimens.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(color: AppColors.mint, width: AppDimens.borderThin),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.1,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            label,
            style: AppTextStyles.secondaryText,
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
