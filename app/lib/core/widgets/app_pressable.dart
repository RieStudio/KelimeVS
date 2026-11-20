import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';

/// DESIGN.md Bölüm 6: Ortak neo-brutalist basma efekti (press effect) widget'ı.
///
/// PrimaryButton ve SecondaryButton'daki görsel davranışla birebir uyumludur:
/// - Basılınca buton aşağı kayar ([pressOffset], 90 ms, [Curves.easeOut]).
/// - Sert gölge küçülür/kaybolur ([builder] içine iletilen `isPressed` ile yönetilir).
/// - Bırakılınca (tapUp) veya kaydırma başlayınca/parmak çıkınca (tapCancel) eski haline döner.
/// - Minimum 48×48 dokunma alanını ([ensureMinTouchTarget] ile) güvenceye alır.
/// - [enablePressAnimation] `false` ise basma animasyonu çalışmaz; fakat [onTap]
///   sağlanmışsa dokunma eylemi tetiklenmeye devam eder (örn. yetersiz jetonda
///   uyarı SnackBar'ı gösterme davranışı).
class AppPressable extends StatefulWidget {
  final Widget Function(BuildContext context, bool isPressed) builder;
  final VoidCallback? onTap;
  final bool enablePressAnimation;
  final double pressOffset;
  final Duration duration;
  final Curve curve;
  final HitTestBehavior behavior;
  final bool ensureMinTouchTarget;

  const AppPressable({
    super.key,
    required this.builder,
    this.onTap,
    this.enablePressAnimation = true,
    this.pressOffset = AppDimens.secondaryButtonPressOffset,
    this.duration = const Duration(milliseconds: 90),
    this.curve = Curves.easeOut,
    this.behavior = HitTestBehavior.opaque,
    this.ensureMinTouchTarget = true,
  });

  @override
  State<AppPressable> createState() => AppPressableState();
}

class AppPressableState extends State<AppPressable> {
  bool _isPressed = false;

  /// Testlerde ve dışarıdan durum denetiminde kullanılabilen getter.
  bool get isPressed => _isPressed;

  void _handleTapDown(TapDownDetails _) {
    if (widget.enablePressAnimation && widget.onTap != null) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enablePressAnimation && widget.onTap != null) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (widget.enablePressAnimation && widget.onTap != null) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEffectivePressed =
        _isPressed && widget.enablePressAnimation && widget.onTap != null;

    Widget content = TweenAnimationBuilder<double>(
      duration: widget.duration,
      curve: widget.curve,
      tween: Tween<double>(
        begin: 0.0,
        end: isEffectivePressed ? widget.pressOffset : 0.0,
      ),
      builder: (context, offset, child) {
        return Transform.translate(
          offset: Offset(0, offset),
          child: child,
        );
      },
      child: widget.builder(context, isEffectivePressed),
    );

    if (widget.ensureMinTouchTarget) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppDimens.minTouchTarget,
          minHeight: AppDimens.minTouchTarget,
        ),
        child: Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: content,
        ),
      );
    }

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: content,
    );
  }
}
