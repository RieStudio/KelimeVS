import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../strings/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_pressable.dart';
import '../ad_service.dart';

/// Ödüllü reklam butonunun tüm durumlarını (hazır, yükleniyor, hak bitti,
/// bekleme geri sayımı, çevrimdışı, hazır değil) tek bileşende yönetir.
class RewardedAdActionButton extends StatefulWidget {
  final String label;
  final int remaining;
  final int cap;
  final int? nextClaimAtMs;
  final int? serverNowMs;
  final bool isOnline;
  final AdRewardedLoadStatus loadStatus;
  final bool isClaiming;
  final VoidCallback? onPressed;
  final VoidCallback? onNotReadyTap;
  final Key? buttonKey;
  final bool enableCooldownTicker;

  const RewardedAdActionButton({
    super.key,
    required this.label,
    required this.remaining,
    required this.cap,
    this.nextClaimAtMs,
    this.serverNowMs,
    required this.isOnline,
    required this.loadStatus,
    this.isClaiming = false,
    this.onPressed,
    this.onNotReadyTap,
    this.buttonKey,
    this.enableCooldownTicker = true,
  });

  @override
  State<RewardedAdActionButton> createState() => _RewardedAdActionButtonState();
}

class _RewardedAdActionButtonState extends State<RewardedAdActionButton> {
  Timer? _ticker;
  late int _clockOffsetMs;

  @override
  void initState() {
    super.initState();
    _syncClockOffset();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant RewardedAdActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.serverNowMs != oldWidget.serverNowMs) {
      _syncClockOffset();
    }
    if (widget.nextClaimAtMs != oldWidget.nextClaimAtMs) {
      _syncTicker();
    }
  }

  void _syncClockOffset() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clockOffsetMs = (widget.serverNowMs ?? now) - now;
  }

  int _cooldownSeconds() {
    final next = widget.nextClaimAtMs;
    if (next == null) return 0;
    final estNow = DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
    final diffMs = math.max(0, next - estNow);
    return (diffMs / 1000).ceil();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.enableCooldownTicker && _cooldownSeconds() > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_cooldownSeconds() <= 0) {
          _ticker?.cancel();
          _ticker = null;
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final limitReached = widget.remaining <= 0;
    final cooldownSec = _cooldownSeconds();
    final inCooldown = cooldownSec > 0;
    final isLoading =
        widget.isClaiming || widget.loadStatus == AdRewardedLoadStatus.loading;
    final isReady = widget.loadStatus == AdRewardedLoadStatus.ready;
    final isInteractive =
        widget.isOnline && !limitReached && !inCooldown && !isLoading;

    String displayText;
    if (limitReached) {
      displayText = AppStrings.adRewardLimitReached;
    } else if (inCooldown) {
      displayText = AppStrings.adRewardCooldown(cooldownSec);
    } else if (isLoading) {
      displayText = AppStrings.adRewardLoading;
    } else {
      displayText = widget.label;
    }

    final bgColor = isInteractive && isReady ? AppColors.mint : AppColors.card;
    final fgColor = isInteractive ? AppColors.ink : AppColors.muted;
    final borderColor = isInteractive ? AppColors.ink : AppColors.muted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPressable(
          key: widget.buttonKey,
          onTap: isInteractive
              ? (isReady ? widget.onPressed : widget.onNotReadyTap)
              : null,
          builder: (context, isPressed) => Container(
            height: AppDimens.secondaryButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.space16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: AppDimens.borderRadiusButton,
              border: Border.all(
                color: borderColor,
                width: AppDimens.borderThin,
              ),
              boxShadow: isInteractive && isReady && !isPressed
                  ? AppDimens.shadowSecondaryButton
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isLoading
                      ? Icons.hourglass_top_rounded
                      : Icons.play_circle_outline_rounded,
                  size: 20,
                  color: fgColor,
                ),
                const SizedBox(width: AppDimens.space8),
                Flexible(
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: fgColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.space6),
        Text(
          AppStrings.adRemainingToday(
            math.max(0, widget.remaining),
            math.max(0, widget.cap),
          ),
          textAlign: TextAlign.center,
          style: AppTextStyles.secondaryText.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}
