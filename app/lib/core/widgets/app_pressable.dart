import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';

/// DESIGN.md Bölüm 6: Ortak neo-brutalist basma efekti (press effect) widget'ı.
///
/// PrimaryButton ve SecondaryButton'daki görsel davranışla birebir uyumludur:
/// - Basılınca buton aşağı kayar ([pressOffset], 90 ms, [Curves.easeOut]).
/// - Sert gölge küçülür/kaybolur ([builder] içine iletilen `isPressed` ile yönetilir).
/// - Hızlı dokunuşta (bas-çek / tap) basılı görünüm en az [minPressedDuration] (~100-120 ms)
///   boyunca ekranda tutulur; böylece basma animasyonu kaybolmaz ve tam görünür.
/// - İşaretçi olayları ([Listener]) kullanılarak kaydırılabilir ata (ListView/bottom sheet)
///   içindeki gecikme engellenir; parmak değer değmez ilk karede basma durumu başlar.
/// - Sürükleme/kaydırma başladığında (`onTapCancel`) buton anında eski haline döner.
/// - Tıklama eylemi ([onTap]), basılı animasyonun kullanıcı tarafından algılanabilmesi için
///   [actionDelay] (~60-100 ms) sonrasında tetiklenir (sayfa geçişi efekti kesmez).
/// - Minimum 48×48 dokunma alanını ([ensureMinTouchTarget] ile) güvenceye alır.
/// - [enablePressAnimation] `false` ise basma animasyonu çalışmaz; fakat [onTap]
///   sağlanmışsa dokunma eylemi gecikmesiz tetiklenmeye devam eder (örn. yetersiz
///   jetonda uyarı SnackBar'ı gösterme davranışı).
class AppPressable extends StatefulWidget {
  /// Basılı durumun görsel olarak ekranda kalacağı minimum süre (~100-120 ms).
  static const Duration defaultMinPressedDuration = Duration(milliseconds: 110);

  /// Hızlı dokunuşta basma görselinin rota değişimiyle kesilmesini önleyen kısa erteleme süresi (~60-100 ms).
  static const Duration defaultActionDelay = Duration(milliseconds: 70);

  final Widget Function(BuildContext context, bool isPressed) builder;
  final VoidCallback? onTap;
  final bool enablePressAnimation;
  final double pressOffset;
  final Duration duration;
  final Curve curve;
  final HitTestBehavior behavior;
  final bool ensureMinTouchTarget;
  final Duration minPressedDuration;
  final Duration actionDelay;

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
    this.minPressedDuration = defaultMinPressedDuration,
    this.actionDelay = defaultActionDelay,
  });

  @override
  State<AppPressable> createState() => AppPressableState();
}

class AppPressableState extends State<AppPressable> {
  bool _isPressed = false;
  bool _isPointerDown = false;
  bool _canRelease = true;
  Timer? _minHoldTimer;
  Timer? _actionTimer;

  /// Testlerde ve dışarıdan durum denetiminde kullanılabilen getter.
  bool get isPressed => _isPressed;

  @override
  void didUpdateWidget(covariant AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.onTap == null || !widget.enablePressAnimation) && _isPressed) {
      _cancelTimers();
      _isPressed = false;
      _isPointerDown = false;
      _canRelease = true;
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _minHoldTimer?.cancel();
    _minHoldTimer = null;
    _actionTimer?.cancel();
    _actionTimer = null;
  }

  void _startPress() {
    if (!widget.enablePressAnimation || widget.onTap == null) return;
    _isPointerDown = true;
    _canRelease = false;

    _minHoldTimer?.cancel();
    _minHoldTimer = Timer(widget.minPressedDuration, () {
      _canRelease = true;
      if (!_isPointerDown && mounted && _isPressed) {
        setState(() => _isPressed = false);
      }
    });

    if (!_isPressed) {
      setState(() => _isPressed = true);
    }
  }

  void _endPress() {
    _isPointerDown = false;
    if (_canRelease) {
      _minHoldTimer?.cancel();
      _minHoldTimer = null;
      if (mounted && _isPressed) {
        setState(() => _isPressed = false);
      }
    }
    // _canRelease false ise _minHoldTimer süresi dolduğunda otomatik olarak bırakacaktır.
  }

  void _handlePointerDown(PointerDownEvent event) {
    _startPress();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _endPress();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _handleTapCancel();
  }

  void _handleTapDown(TapDownDetails _) {
    _startPress();
  }

  void _handleTapUp(TapUpDetails _) {
    _endPress();
  }

  void _handleTapCancel() {
    _isPointerDown = false;
    _canRelease = true;
    _cancelTimers();
    if (mounted && _isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTap() {
    if (widget.onTap == null) return;

    if (!widget.enablePressAnimation || widget.actionDelay == Duration.zero) {
      widget.onTap?.call();
      return;
    }

    _actionTimer?.cancel();
    _actionTimer = Timer(widget.actionDelay, () {
      if (mounted) {
        widget.onTap?.call();
      }
    });
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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: _handleTap,
        child: content,
      ),
    );
  }
}
