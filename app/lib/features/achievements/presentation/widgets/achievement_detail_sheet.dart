import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../domain/achievement_ui_manifest.dart';
import '../../domain/user_achievement.dart';

/// Başarım rozetine dokunulduğunda detaylarını gösteren alt sayfa (bottom sheet).
Future<void> showAchievementDetailSheet(
  BuildContext context, {
  required UserAchievement achievement,
  required AchievementUiItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AchievementDetailSheet(
      achievement: achievement,
      item: item,
    ),
  );
}

class AchievementDetailSheet extends StatelessWidget {
  final UserAchievement achievement;
  final AchievementUiItem item;

  const AchievementDetailSheet({
    super.key,
    required this.achievement,
    required this.item,
  });

  static const List<String> _turkishMonths = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  /// Epoch milisaniye değerini bağımlılıksız Türkçe takvim tarihine çevirir (ör. "25 Kasım 2026").
  static String formatTurkishDate(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final monthName = _turkishMonths[dt.month - 1];
    return '${dt.day} $monthName ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasValidDate = achievement.unlockedAt > 0;
    final dateText = hasValidDate
        ? AppStrings.achievementFirstUnlocked(
            formatTurkishDate(achievement.unlockedAt),
          )
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Üst Çubuk: Başlık ve Kapat Butonu
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.title,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 20),
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  semanticLabel: AppStrings.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),

            // Büyük Başarım SVG Görseli (ColorFilter yok)
            SvgPicture.asset(
              item.iconAsset,
              width: 84,
              height: 84,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AppDimens.space16),

            // Açıklama
            Text(
              item.description,
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),

            if (achievement.count >= 2) ...[
              const SizedBox(height: AppDimens.space12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.coin,
                  borderRadius: AppDimens.borderRadiusFull,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Text(
                  AppStrings.achievementRepeatCount(achievement.count),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],

            if (dateText != null) ...[
              const SizedBox(height: AppDimens.space10),
              Text(
                dateText,
                style: AppTextStyles.secondaryText,
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: AppDimens.space8),
          ],
        ),
      ),
    );
  }
}
