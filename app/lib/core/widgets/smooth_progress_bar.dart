import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// DESIGN.md Bölüm 6 ve Faz 5 uyumlu pürüzsüz süre çubuğu bileşeni.
///
/// 200 ms'lik controller / sunucu durumu güncellemeleri arasında
/// donanım ekran tazeleme oranında (60/120 Hz) Ticker ile pürüzsüz
/// akış sağlar.
///
/// - [RepaintBoundary] ile yalnızca çubuk katmanını izole eder; ana ekran yeniden build olmaz.
/// - Bot maçında duraklatma ([isPaused]) durumunda Ticker donar.
/// - Ek süre (+5 sn) basıldığında sert sıçramayı önlemek için 250 ms'lik yumuşak sönümleme (lerp) uygular.
/// - Süre dolduğunda veya pasif duruma geçtiğinde Ticker durur (pumpAndSettle zaman aşımını önler).
/// - [MediaQueryData.disableAnimations] açıkken Ticker çalıştırmaz, doğrudan statik değeri çizer.
class SmoothProgressBar extends StatefulWidget {
  final int totalDurationMs;
  final int remainingMs;
  final bool isActive;
  final bool isPaused;
  final Color fillColor;
  final BoxDecoration? decoration;
  final Widget? child;

  const SmoothProgressBar({
    super.key,
    required this.totalDurationMs,
    required this.remainingMs,
    this.isActive = true,
    this.isPaused = false,
    required this.fillColor,
    this.decoration,
    this.child,
  });

  @override
  State<SmoothProgressBar> createState() => _SmoothProgressBarState();
}

class _SmoothProgressBarState extends State<SmoothProgressBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _currentProgress = 1.0;

  // Çapa (Anchor) değerleri
  int _anchorRemainingMs = 0;
  Duration _anchorTickerElapsed = Duration.zero;

  // Son bilinen widget girdileri
  int _lastKnownRemainingMs = -1;
  int _lastKnownTotalMs = -1;

  // Ek süre (+5 sn) yumuşak geçişi için
  double? _lerpStartProgress;
  double? _lerpTargetProgress;
  Duration? _lerpStartElapsed;
  static const int _lerpDurationMs = 250;

  Duration _currentTickerElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.totalDurationMs > 0
        ? (widget.remainingMs / widget.totalDurationMs).clamp(0.0, 1.0)
        : 0.0;
    _anchorRemainingMs = widget.remainingMs;
    _lastKnownRemainingMs = widget.remainingMs;
    _lastKnownTotalMs = widget.totalDurationMs;

    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerState();
  }

  @override
  void didUpdateWidget(SmoothProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final totalChanged = widget.totalDurationMs != _lastKnownTotalMs;
    final remainingChanged = widget.remainingMs != _lastKnownRemainingMs;
    final pausedChanged = widget.isPaused != oldWidget.isPaused;
    final activeChanged = widget.isActive != oldWidget.isActive;

    if (activeChanged || pausedChanged) {
      if (!widget.isActive || widget.isPaused) {
        _stopTicker();
      } else {
        // Yeniden aktifleşti veya devam etti
        _anchorRemainingMs = widget.remainingMs;
        _anchorTickerElapsed = Duration.zero;
        _startTickerIfNeeded();
      }
    }

    if (totalChanged || remainingChanged) {
      // 1. Ek süre durumu kontrolü: süre belirgin biçimde (1000 ms'den fazla) arttıysa
      if (_lastKnownRemainingMs > 0 &&
          (widget.remainingMs - _lastKnownRemainingMs > 1000)) {
        final newTarget = widget.totalDurationMs > 0
            ? (widget.remainingMs / widget.totalDurationMs).clamp(0.0, 1.0)
            : 0.0;
        _lerpStartProgress = _currentProgress;
        _lerpTargetProgress = newTarget;
        _lerpStartElapsed = _ticker.isTicking ? _currentTickerElapsed : Duration.zero;
        _anchorRemainingMs = widget.remainingMs;
        _anchorTickerElapsed = (_lerpStartElapsed ?? Duration.zero) +
            const Duration(milliseconds: _lerpDurationMs);
        _startTickerIfNeeded();
      } else {
        // 2. Normal periyodik güncelleme (200 ms tick veya yeni tur)
        final nominal = widget.totalDurationMs > 0
            ? (widget.remainingMs / widget.totalDurationMs).clamp(0.0, 1.0)
            : 0.0;

        if (_lastKnownRemainingMs == -1 || (!oldWidget.isActive && widget.isActive)) {
          _currentProgress = nominal;
        } else if (_lerpStartElapsed == null) {
          // Monotonik koruma: normal akışta ağ dalgalanması nedeniyle geriye zıplamayı önle
          _currentProgress = math.min(_currentProgress, nominal);
        }

        _anchorRemainingMs = widget.remainingMs;
        _anchorTickerElapsed = _ticker.isTicking ? _currentTickerElapsed : Duration.zero;
      }

      _lastKnownRemainingMs = widget.remainingMs;
      _lastKnownTotalMs = widget.totalDurationMs;
    }

    _syncTickerState();
  }

  void _syncTickerState() {
    if (!mounted) return;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (disableAnimations ||
        !widget.isActive ||
        widget.isPaused ||
        widget.remainingMs <= 0) {
      _stopTicker();
      if (disableAnimations || widget.remainingMs <= 0) {
        _currentProgress = widget.totalDurationMs > 0
            ? (widget.remainingMs / widget.totalDurationMs).clamp(0.0, 1.0)
            : 0.0;
      }
    } else {
      _startTickerIfNeeded();
    }
  }

  void _startTickerIfNeeded() {
    if (_ticker.isTicking) return;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return;
    if (!widget.isActive || widget.isPaused || widget.remainingMs <= 0) return;

    _anchorTickerElapsed = Duration.zero;
    _currentTickerElapsed = Duration.zero;
    _ticker.start();
  }

  void _stopTicker() {
    if (_ticker.isTicking) {
      _ticker.stop();
    }
    _lerpStartElapsed = null;
    _lerpStartProgress = null;
    _lerpTargetProgress = null;
  }

  void _onTick(Duration elapsed) {
    _currentTickerElapsed = elapsed;
    if (!mounted) return;
    if (!widget.isActive || widget.isPaused) {
      _stopTicker();
      return;
    }

    // 1. Ek süre için yumuşak lerp uygulanıyorsa
    if (_lerpStartElapsed != null &&
        _lerpStartProgress != null &&
        _lerpTargetProgress != null) {
      final lerpDt = (elapsed - _lerpStartElapsed!).inMilliseconds;
      if (lerpDt >= _lerpDurationMs) {
        _currentProgress = _lerpTargetProgress!;
        _lerpStartElapsed = null;
        _lerpStartProgress = null;
        _lerpTargetProgress = null;
      } else {
        final t = Curves.easeOut.transform(
          (lerpDt / _lerpDurationMs).clamp(0.0, 1.0),
        );
        _currentProgress = _lerpStartProgress! +
            (_lerpTargetProgress! - _lerpStartProgress!) * t;
        setState(() {});
        return;
      }
    }

    // 2. Normal sürekli geri sayım hesabı
    if (widget.totalDurationMs <= 0) return;

    final dtMs = (elapsed - _anchorTickerElapsed).inMilliseconds;
    final estimatedRemainingMs = math.max(0, _anchorRemainingMs - dtMs);
    final targetProgress =
        (estimatedRemainingMs / widget.totalDurationMs).clamp(0.0, 1.0);

    // Monotonik azalış
    final nextProgress = math.min(_currentProgress, targetProgress);

    if ((nextProgress - _currentProgress).abs() > 0.0001) {
      setState(() {
        _currentProgress = nextProgress;
      });
    }

    // Süre bittiğinde Ticker'ı durdur (sonsuz çalışmayı ve pumpAndSettle askıda kalmasını önler)
    if (_currentProgress <= 0.0) {
      _currentProgress = 0.0;
      _stopTicker();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentProgress.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: widget.child ??
            (widget.decoration != null
                ? Container(decoration: widget.decoration)
                : Container(color: widget.fillColor)),
      ),
    );
  }
}
