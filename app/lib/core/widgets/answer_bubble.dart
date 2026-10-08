import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: Cevap Balonu
///
/// Nunito 15/800, dolgu: kendi cevabın bright, rakip cevabı card;
/// 2 px ink kenarlık, köşe 14, iç boşluk 7x14, en geniş %78.
/// Kendi cevabın sağa, rakibinki sola hizalanır.
/// Uzun cevap alt satıra sarar. Reddedilen cevabın kenarlığı danger, yazısı dangerText.
class AnswerBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isRejected;

  const AnswerBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isRejected = false,
  });

  const AnswerBubble.rejected({
    super.key,
    required this.text,
    required this.isMe,
  }) : isRejected = true;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth > 0 ? screenWidth * 0.78 : 300.0;

    final bgColor = isRejected
        ? AppColors.card
        : (isMe ? AppColors.bright : AppColors.card);
    final borderColor = isRejected ? AppColors.danger : AppColors.ink;
    final textStyle = isRejected
        ? AppTextStyles.answerBubbleRejected
        : AppTextStyles.answerBubble;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14.0,
            vertical: 7.0,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppDimens.borderRadiusBubble,
            border: Border.all(
              color: borderColor,
              width: AppDimens.borderThin,
            ),
          ),
          child: Text(
            text,
            style: textStyle,
            softWrap: true,
          ),
        ),
      ),
    );
  }
}

