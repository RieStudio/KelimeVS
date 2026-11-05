import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// Eşleşme (Rakip Bulundu) ve Tur Sonu (RoundEndView) ekranlarında
/// sıradaki sorunun kategori metnini gösteren ortak kart bileşeni.
///
/// Herhangi bir rozet/etiket içermez; yalnızca kategori metnini gösterir.
class QuestionPreviewCard extends StatelessWidget {
  final String categoryText;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const QuestionPreviewCard({
    super.key,
    required this.categoryText,
    this.margin = const EdgeInsets.symmetric(horizontal: AppDimens.space8),
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppDimens.space24,
      vertical: AppDimens.space16,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.ink,
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        categoryText,
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFredoka,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          height: 1.25,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

