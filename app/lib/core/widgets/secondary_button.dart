import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: SecondaryButton
/// Zemin: card, Yazı: ink, Kenarlık: 3 ink, Yükseklik: 54-60, Gölge: 0 4px 0 ink.
/// Dokunma alanı en az 48x48.
class SecondaryButton extends StatefulWidget {
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
  })  : backgroundColor = AppColors.dangerSoft,
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
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (widget.onPressed != null) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pressOffset = AppDimens.secondaryButtonPressOffset;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppDimens.minTouchTarget,
            minHeight: AppDimens.minTouchTarget,
          ),
          child: SizedBox(
            width: widget.width ?? double.infinity,
            height: widget.height + pressOffset,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  top: _isPressed ? pressOffset : 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: widget.backgroundColor ?? AppColors.card,
                      borderRadius: AppDimens.borderRadiusButton,
                      border: Border.all(
                        color: widget.borderColor ?? AppColors.ink,
                        width: AppDimens.borderThick,
                      ),
                      boxShadow: _isPressed
                          ? const []
                          : (widget.boxShadow ?? AppDimens.shadowSecondaryButton),
                    ),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.horizontalPadding ??
                              (widget.width != null && widget.width! < 100
                                  ? AppDimens.space6
                                  : AppDimens.space16),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                          widget.text,
                          style: AppTextStyles.secondaryButton.copyWith(
                            color: widget.textColor ?? AppColors.ink,
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
        ),
      ),
    );
  }
}

