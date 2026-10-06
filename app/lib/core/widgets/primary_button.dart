import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: PrimaryButton
/// Zemin: primary, Yazı: beyaz, Fredoka 22 (Büyük varyantta 28 ve alt yazı 13).
/// Köşe: 20-22, Gölge: 0 5px 0 ink.
/// Basılınca gölge kaybolup buton 4-5 px aşağı iner (80-100 ms).
class PrimaryButton extends StatefulWidget {
  final String text;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool isLarge;
  final double? width;

  const PrimaryButton({
    super.key,
    required this.text,
    this.subtitle,
    this.onPressed,
    this.isLarge = false,
    this.width,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
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
    final height = widget.isLarge
        ? AppDimens.primaryButtonLargeHeight
        : AppDimens.primaryButtonHeight;

    final double pressOffset = AppDimens.primaryButtonPressOffset;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.subtitle != null
          ? '${widget.text}, ${widget.subtitle}'
          : widget.text,
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
            height: height + pressOffset,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  top: _isPressed ? pressOffset : 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: widget.isLarge
                          ? AppDimens.borderRadiusButtonLarge
                          : AppDimens.borderRadiusButton,
                      boxShadow: _isPressed
                          ? const []
                          : AppDimens.shadowPrimaryButton,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space16,
                        ),
                        child: widget.subtitle != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.text,
                                    style: widget.isLarge
                                        ? AppTextStyles.primaryButtonLarge
                                        : AppTextStyles.primaryButton,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: AppDimens.space4),
                                  Text(
                                    widget.subtitle!,
                                    style: AppTextStyles.primaryButtonSubtitle,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : Text(
                                widget.text,
                                style: widget.isLarge
                                    ? AppTextStyles.primaryButtonLarge
                                    : AppTextStyles.primaryButton,
                                textAlign: TextAlign.center,
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

