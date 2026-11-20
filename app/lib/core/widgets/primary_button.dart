import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import 'app_pressable.dart';

/// DESIGN.md Bölüm 6: PrimaryButton
/// Zemin: primary, Yazı: beyaz, Fredoka 22 (Büyük varyantta 28 ve alt yazı 13).
/// Köşe: 20-22, Gölge: 0 5px 0 ink.
/// Basılınca gölge kaybolup buton 4-5 px aşağı iner (80-100 ms).
class PrimaryButton extends StatelessWidget {
  final String text;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool isLarge;
  final double? width;
  final Color? backgroundColor;
  final Color? shadowColor;

  const PrimaryButton({
    super.key,
    required this.text,
    this.subtitle,
    this.onPressed,
    this.isLarge = false,
    this.width,
    this.backgroundColor,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final height = isLarge
        ? AppDimens.primaryButtonLargeHeight
        : AppDimens.primaryButtonHeight;

    final double pressOffset = AppDimens.primaryButtonPressOffset;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: subtitle != null
          ? '$text, $subtitle'
          : text,
      child: AppPressable(
        onTap: onPressed,
        actionDelay: Duration.zero,
        pressOffset: 0,
        ensureMinTouchTarget: false,
        builder: (context, isPressed) {
          return ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppDimens.minTouchTarget,
              minHeight: AppDimens.minTouchTarget,
            ),
            child: SizedBox(
              width: width ?? double.infinity,
              height: height + pressOffset,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    top: isPressed ? pressOffset : 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: backgroundColor ?? AppColors.primary,
                        borderRadius: isLarge
                            ? AppDimens.borderRadiusButtonLarge
                            : AppDimens.borderRadiusButton,
                        boxShadow: isPressed
                            ? const []
                            : (shadowColor != null
                                ? [
                                    BoxShadow(
                                      color: shadowColor!,
                                      offset: const Offset(0, 5),
                                      blurRadius: 0,
                                    ),
                                  ]
                                : AppDimens.shadowPrimaryButton),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.space16,
                          ),
                          child: subtitle != null
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        text,
                                        style: isLarge
                                            ? AppTextStyles.primaryButtonLarge
                                            : AppTextStyles.primaryButton,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: AppDimens.space4),
                                      Text(
                                        subtitle!,
                                        style:
                                            AppTextStyles.primaryButtonSubtitle,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    text,
                                    style: isLarge
                                        ? AppTextStyles.primaryButtonLarge
                                        : AppTextStyles.primaryButton,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

