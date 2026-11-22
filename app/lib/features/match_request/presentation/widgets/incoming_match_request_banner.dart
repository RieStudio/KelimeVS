import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/player_avatar.dart';
import '../../domain/match_request_models.dart';

/// DESIGN.md ile tam uyumlu gelen maç isteği bildirim bandı.
///
/// Üstten açılan kart:
/// - Avatar (çerçevesiyle) + İsim + Başlık (`<Ad>` seninle rövanş/maç istiyor)
/// - Alt başlık: "Dostluk maçı" veya "Dereceli maç · 1 enerji"
/// - Monotonik 45 sn sayaç çubuğu (progress bar)
/// - "Reddet" ve "Kabul Et" eylemleri ("Kabul Et" tıklandığında yükleme çarkı gösterir).
class IncomingMatchRequestBanner extends StatefulWidget {
  final IncomingMatchRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool isAccepting;

  const IncomingMatchRequestBanner({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
    this.isAccepting = false,
  });

  @override
  State<IncomingMatchRequestBanner> createState() =>
      _IncomingMatchRequestBannerState();
}

class _IncomingMatchRequestBannerState
    extends State<IncomingMatchRequestBanner>
    with SingleTickerProviderStateMixin {
  static const double progressWarningThresholdSec = 15.0;
  static const double progressDangerThresholdSec = 5.0;

  Ticker? _ticker;
  Timer? _steppedTimer;
  double _progress = 1.0;
  Color _barColor = AppColors.primary;
  bool _animationsDisabled = false;

  /// Kalan süreye göre çubuk rengini hesaplar.
  /// 15 sn'ye kadar yeşil (primary), 15 sn - 5 sn arası kırmızıya yumuşak lerp, son 5 sn tam kırmızı (danger).
  /// [disableAnimations] true ise lerp yerine tek adımda eşik geçişi yapılır.
  static Color calculateBarColor(double remainingSeconds, {bool disableAnimations = false}) {
    if (disableAnimations) {
      return remainingSeconds <= progressDangerThresholdSec
          ? AppColors.danger
          : AppColors.primary;
    }
    if (remainingSeconds >= progressWarningThresholdSec) {
      return AppColors.primary;
    }
    if (remainingSeconds <= progressDangerThresholdSec) {
      return AppColors.danger;
    }
    final t = (progressWarningThresholdSec - remainingSeconds) /
        (progressWarningThresholdSec - progressDangerThresholdSec);
    return Color.lerp(AppColors.primary, AppColors.danger, t.clamp(0.0, 1.0)) ??
        AppColors.danger;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_ticker == null && _steppedTimer == null) {
      _animationsDisabled = disableAnimations;
      _setupTimerOrTicker();
    } else if (_animationsDisabled != disableAnimations) {
      _animationsDisabled = disableAnimations;
      _setupTimerOrTicker();
    }
  }

  void _setupTimerOrTicker() {
    _ticker?.dispose();
    _ticker = null;
    _steppedTimer?.cancel();
    _steppedTimer = null;

    _updateProgress(disableAnimations: _animationsDisabled);

    if (_animationsDisabled) {
      _steppedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _updateProgress(disableAnimations: true);
        }
      });
    } else {
      _ticker = createTicker((_) {
        if (mounted) {
          _updateProgress(disableAnimations: false);
        }
      });
      _ticker?.start();
    }
  }

  void _updateProgress({bool disableAnimations = false}) {
    final remainingMs = widget.request.calculateRemainingMs();
    final remainingSec = remainingMs / 1000.0;
    final double fraction;
    if (disableAnimations) {
      final sec = widget.request.calculateRemainingSeconds();
      fraction = (sec / 45.0).clamp(0.0, 1.0);
    } else {
      fraction = widget.request.calculateRemainingFraction();
    }

    final color = calculateBarColor(remainingSec, disableAnimations: disableAnimations);

    if (fraction != _progress || color != _barColor) {
      setState(() {
        _progress = fraction;
        _barColor = color;
      });
    }

    if (remainingMs <= 0) {
      _ticker?.stop();
      _steppedTimer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant IncomingMatchRequestBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id) {
      _setupTimerOrTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    _steppedTimer?.cancel();
    _steppedTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.request.origin == MatchRequestOrigin.rematch
        ? AppStrings.matchRequestTitleRematch(widget.request.fromNickname)
        : AppStrings.matchRequestTitleProfile(widget.request.fromNickname);

    final subtitle = widget.request.type == MatchRequestType.ranked
        ? AppStrings.matchRequestSubtitleRanked
        : AppStrings.matchRequestSubtitleFriendly;

    final semanticText = '$title, $subtitle';

    return Semantics(
      liveRegion: true,
      label: semanticText,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThick,
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(0, 3),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppDimens.space12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst Satır: Avatar + Başlık & Alt Başlık
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PlayerAvatar.opponent(
                      name: widget.request.fromNickname,
                      frame: widget.request.fromFrame,
                      size: 40,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.ink,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/icons/match_request_incoming.svg',
                          width: 12,
                          height: 12,
                          colorFilter: const ColorFilter.mode(
                            AppColors.ink,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFredoka,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          decoration: TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontNunito,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space10),

            // Monotonik İlerleme Çubuğu (45 sn)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation<Color>(_barColor),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.space12),

            // Butonlar: Reddet & Kabul Et
            Row(
              children: [
                Expanded(
                  child: _BannerButton(
                    text: AppStrings.matchRequestDecline,
                    isPrimary: false,
                    onPressed: widget.isAccepting ? null : widget.onDecline,
                  ),
                ),
                const SizedBox(width: AppDimens.space10),
                Expanded(
                  child: _BannerButton(
                    text: AppStrings.matchRequestAccept,
                    isPrimary: true,
                    isLoading: widget.isAccepting,
                    onPressed: widget.isAccepting ? null : widget.onAccept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerButton extends StatefulWidget {
  final String text;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _BannerButton({
    required this.text,
    required this.isPrimary,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  State<_BannerButton> createState() => _BannerButtonState();
}

class _BannerButtonState extends State<_BannerButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final bgColor = widget.isPrimary
        ? (isEnabled ? AppColors.primary : AppColors.muted)
        : (isEnabled ? AppColors.card : AppColors.surface);
    final textColor = widget.isPrimary ? Colors.white : AppColors.ink;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
        onTap: isEnabled ? widget.onPressed : null,
        child: SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 70),
                top: _isPressed ? 2 : 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.ink,
                      width: 2,
                    ),
                    boxShadow: _isPressed
                        ? null
                        : const [
                            BoxShadow(
                              color: AppColors.ink,
                              offset: Offset(0, 2),
                              blurRadius: 0,
                            ),
                          ],
                  ),
                  child: Center(
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            widget.text,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontNunito,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                              decoration: TextDecoration.none,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
