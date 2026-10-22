import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 7: 9b) Enerji Hapı (EnergyPill)
/// Beyaz hap (`card`), 2 px `ink` kenarlık, tam yuvarlak köşeler.
/// İçinde `coin` renkli yıldırım simgesi ve güncel enerji sayısı.
class EnergyPill extends StatelessWidget {
  final int current;
  final int max;
  final VoidCallback? onTap;

  const EnergyPill({
    super.key,
    required this.current,
    this.max = 5,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: '$current / $max Enerji',
      button: onTap != null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space10,
          vertical: AppDimens.space6,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppDimens.borderRadiusFull,
          border: Border.all(color: AppColors.ink, width: AppDimens.borderThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Yıldırım Simgesi
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
              child: const AppIcon(
                AppIcons.bolt,
                size: 13,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: AppDimens.space6),
            // Sayı
            Text(
              '$current',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.ink,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        key: const Key('energy_pill_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
