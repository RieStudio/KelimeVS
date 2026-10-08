import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppDimens {
  // Spacing (Bölüm 4: 4 / 6 / 8 / 10 / 12 / 14 / 16 / 20 / 24)
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space14 = 14.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;

  // Semantic Spacing
  static const double screenPaddingHorizontal = 20.0;
  static const double screenPaddingTop = 24.0;
  static const double blockSpacing = 16.0;
  static const double listSpacing = 10.0;
  static const double bubbleSpacing = 8.0;

  // Corner Radii (Bölüm 4)
  static const double radiusBadge = 12.0;
  static const double radiusIconBtn = 14.0;
  static const double radiusBubble = 14.0;
  static const double radiusNavPill = 16.0;
  static const double radiusAlertBox = 16.0;
  static const double radiusQuestionCard = 18.0;
  static const double radiusInput = 18.0;
  static const double radiusButton = 20.0;
  static const double radiusButtonLarge = 22.0;
  static const double radiusListCard = 20.0;
  static const double radiusCardLarge = 24.0;
  static const double radiusFull = 999.0;

  // BorderRadius helpers
  static final BorderRadius borderRadiusBadge = BorderRadius.circular(radiusBadge);
  static final BorderRadius borderRadiusIconBtn = BorderRadius.circular(radiusIconBtn);
  static final BorderRadius borderRadiusBubble = BorderRadius.circular(radiusBubble);
  static final BorderRadius borderRadiusNavPill = BorderRadius.circular(radiusNavPill);
  static final BorderRadius borderRadiusAlertBox = BorderRadius.circular(radiusAlertBox);
  static final BorderRadius borderRadiusQuestionCard = BorderRadius.circular(radiusQuestionCard);
  static final BorderRadius borderRadiusInput = BorderRadius.circular(radiusInput);
  static final BorderRadius borderRadiusButton = BorderRadius.circular(radiusButton);
  static final BorderRadius borderRadiusButtonLarge = BorderRadius.circular(radiusButtonLarge);
  static final BorderRadius borderRadiusListCard = BorderRadius.circular(radiusListCard);
  static final BorderRadius borderRadiusCardLarge = BorderRadius.circular(radiusCardLarge);
  static final BorderRadius borderRadiusDialog = BorderRadius.circular(radiusQuestionCard);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // Border Widths (Bölüm 4: 2–3 px)
  static const double borderThin = 2.0;
  static const double borderThick = 3.0;

  // Sizes & Touch Target (Bölüm 4 & 6)
  static const double minTouchTarget = 48.0;
  static const double resultBadgeWidth = 88.0;
  static const double scoreWidth = 56.0;
  static const double bottomNavHeight = 76.0;

  static const double primaryButtonHeight = 60.0;
  static const double primaryButtonLargeHeight = 76.0;
  static const double secondaryButtonHeight = 54.0;
  static const double iconButtonSize = 44.0;
  static const double inputHeight = 54.0;

  static const double avatarHome = 44.0;
  static const double avatarList = 40.0;
  static const double avatarMatch = 36.0;
  static const double avatarSearch = 92.0;
  static const double avatarEnd = 104.0;

  // Press offsets
  static const double primaryButtonPressOffset = 4.0;
  static const double secondaryButtonPressOffset = 3.0;

  // Sert Gölgeler (Bölüm 4 & 6: Sadece dikey ofset, sıfır bulanıklık)
  static const List<BoxShadow> shadowPrimaryButton = [
    BoxShadow(
      color: AppColors.ink,
      offset: Offset(0, 5),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowSecondaryButton = [
    BoxShadow(
      color: AppColors.ink,
      offset: Offset(0, 4),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowSendButton = [
    BoxShadow(
      color: AppColors.ink,
      offset: Offset(0, 4),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowQuestionCard = [
    BoxShadow(
      color: AppColors.ink,
      offset: Offset(0, 3),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  static const double borderResultCircle = 4.0;

  static const List<BoxShadow> shadowResultCircleWin = [
    BoxShadow(
      color: AppColors.ink,
      offset: Offset(0, 4),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> shadowResultCircleLose = [
    BoxShadow(
      color: AppColors.dangerDark,
      offset: Offset(0, 4),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];
}

