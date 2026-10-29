import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import 'section_label.dart';

/// DESIGN.md Bölüm 7: Maç Öncesi İpucu Kartı
///
/// Eşleşme ekranında (MatchmakingScreen) ve arkadaş düellosu bekleme ekranında (FriendHostScreen)
/// maç öncesi yönlendirici ve eğitici ipuçlarını gösteren kart bileşeni.
class MatchTipCard extends StatelessWidget {
  final String tip;

  const MatchTipCard({
    super.key,
    required this.tip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionLabel(AppStrings.searchTipTitle),
          const SizedBox(height: AppDimens.space6),
          Text(
            tip,
            style: AppTextStyles.bodyText.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

