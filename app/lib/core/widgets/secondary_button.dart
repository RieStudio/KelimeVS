import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import 'app_pressable.dart';

/// DESIGN.md Bölüm 6: SecondaryButton
/// Standart: Zemin: card, Yazı: ink, Kenarlık: 3 ink, Yükseklik: 54-60, Gölge: 0 4px 0 ink.
/// Tehlike (danger): Zemin: card (beyaz), Yazı: dangerText, Kenarlık: danger, Gölge: 0 4px 0 dangerDark.
/// Dokunma alanı en az 48x48.
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final double? horizontalPadding;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.width,
    this.height = AppDimens.secondaryButtonHeight,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.boxShadow,
    this.horizontalPadding,
  });

  const SecondaryButton.danger({
    super.key,
    required this.text,
    this.onPressed,
    this.width,
    this.height = AppDimens.secondaryButtonHeight,
    this.horizontalPadding,
  })  : backgroundColor = AppColors.card,
        textColor = AppColors.dangerText,
        borderColor = AppColors.danger,
        boxShadow = const [
          BoxShadow(
            color: AppColors.dangerDark,
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ];

  @override
  Widget build(BuildContext context) {
    const pressOffset = AppDimens.secondaryButtonPressOffset;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: text,
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
                        color: backgroundColor ?? AppColors.card,
                        borderRadius: AppDimens.borderRadiusButton,
                        border: Border.all(
                          color: borderColor ?? AppColors.ink,
                          width: AppDimens.borderThick,
                        ),
                        boxShadow: isPressed
                            ? const []
                            : (boxShadow ?? AppDimens.shadowSecondaryButton),
                      ),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding ??
                                (width != null && width! < 100
                                    ? AppDimens.space6
                                    : AppDimens.space16),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              text,
                              style: AppTextStyles.secondaryButton.copyWith(
                                color: textColor ?? AppColors.ink,
                              ),
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

