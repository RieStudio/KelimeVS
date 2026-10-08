import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: Soru Kartı
///
/// card zemin, 3 px ink kenarlık, köşe 18, gölge 0 3px 0 ink, ortalı Fredoka 18/600.
/// İçerik tek satır olmak zorunda değildir; çok satıra uzar.
class QuestionCard extends StatelessWidget {
  final String text;

  const QuestionCard({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusQuestionCard,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThick,
        ),
        boxShadow: AppDimens.shadowQuestionCard,
      ),
      child: Text(
        text,
        style: AppTextStyles.questionText,
        textAlign: TextAlign.center,
      ),
    );
  }
}

