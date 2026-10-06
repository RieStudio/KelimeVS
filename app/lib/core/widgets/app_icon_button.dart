import 'package:flutter/material.dart';
import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// DESIGN.md Bölüm 6: İkon Buton
/// Görsel: 44x44 (dokunma alanı en az 48x48), card zemin, 2 px ink kenarlık, köşe 14.
class AppIconButton extends StatelessWidget {
  final AppIconData icon;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color iconColor;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.semanticLabel,
    this.iconColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppDimens.minTouchTarget,
            minHeight: AppDimens.minTouchTarget,
          ),
          child: Center(
            child: Container(
              width: AppDimens.iconButtonSize,
              height: AppDimens.iconButtonSize,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusIconBtn,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              alignment: Alignment.center,
              child: AppIcon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

