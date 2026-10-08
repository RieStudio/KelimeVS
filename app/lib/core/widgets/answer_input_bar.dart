import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../features/game/application/match_ui_state.dart';
import '../icons/app_icons.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../../features/game/domain/attempt_text_sanitizer.dart';

/// DESIGN.md Bölüm 6 & 8: Giriş Alanı + Gönder Butonu
///
/// Giriş alanı: yükseklik 54, 3 px ink kenarlık, köşe 18, Nunito 16/700,
/// ipucu: "Cevabını yaz…". Yanında 54x54 gönder butonu (primary, beyaz ok, gölge 0 4px 0 ink).
/// Otomatik düzeltme ve öneri kapalı; klavye "gönder" eylemiyle de gönderilir.
/// Sıra bende değilken alan salt okunur ve soluk görünür (klavye kapanmaz).
/// Boş metin gönderilmez. Gönderince alan temizlenir ve odak korunur.
///
/// Geri bildirim:
/// - wrong veya alreadySaid: alan 250 ms sallanır, kenarlık kısa süre danger olur,
///   alanın üstünde 1.5 sn kalan küçük metin ("Yanlış cevap" / "Bu cevap söylendi", Nunito 12/800, dangerText).
/// - nearMiss: aynı yerde "Çok yakın!" (bright zeminli küçük hap, ink yazı, 1.5 sn).
/// - Canlı bölge (liveRegion) ile erişilebilirlik sağlanır.
class AnswerInputBar extends StatefulWidget {
  final bool isMyTurn;
  final ValueChanged<String> onSubmitted;
  final MatchFeedbackType? feedback;
  final int feedbackCounter;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const AnswerInputBar({
    super.key,
    required this.isMyTurn,
    required this.onSubmitted,
    this.feedback,
    this.feedbackCounter = 0,
    this.controller,
    this.focusNode,
  });

  @override
  State<AnswerInputBar> createState() => _AnswerInputBarState();
}

class _AnswerInputBarState extends State<AnswerInputBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _shakeController;

  MatchFeedbackType? _activeFeedback;
  Timer? _feedbackTimer;
  bool _showDangerBorder = false;

  bool get _isExternalController => widget.controller != null;
  bool get _isExternalFocusNode => widget.focusNode != null;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    if (widget.feedback != null && widget.feedbackCounter > 0) {
      _activeFeedback = widget.feedback;
      if (widget.feedback == MatchFeedbackType.wrong ||
          widget.feedback == MatchFeedbackType.alreadySaid) {
        _showDangerBorder = true;
        _shakeController.forward(from: 0.0);
      }
      _feedbackTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _activeFeedback = null;
            _showDangerBorder = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(AnswerInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.feedbackCounter != oldWidget.feedbackCounter &&
        widget.feedback != null) {
      _triggerFeedback(widget.feedback!);
    }
  }

  void _triggerFeedback(MatchFeedbackType feedback) {
    _feedbackTimer?.cancel();
    _activeFeedback = feedback;

    if (feedback == MatchFeedbackType.wrong ||
        feedback == MatchFeedbackType.alreadySaid) {
      _showDangerBorder = true;
      _shakeController.forward(from: 0.0);
    } else {
      _showDangerBorder = false;
    }

    _feedbackTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _activeFeedback = null;
          _showDangerBorder = false;
        });
      }
    });

    setState(() {});
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _shakeController.dispose();
    if (!_isExternalController) {
      _controller.dispose();
    }
    if (!_isExternalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleSend() {
    final text = AttemptTextSanitizer.sanitize(_controller.text);
    if (text.isEmpty || !widget.isMyTurn) return;

    _controller.clear();
    widget.onSubmitted(text);
    _focusNode.requestFocus();
  }

  Widget _buildFeedbackBanner() {
    final feedback = _activeFeedback;
    Widget content;

    if (feedback == MatchFeedbackType.wrong) {
      content = Text(
        AppStrings.wrongAnswer,
        style: AppTextStyles.secondaryText.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.dangerText,
        ),
      );
    } else if (feedback == MatchFeedbackType.alreadySaid) {
      content = Text(
        AppStrings.alreadySaid,
        style: AppTextStyles.secondaryText.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.dangerText,
        ),
      );
    } else if (feedback == MatchFeedbackType.nearMiss) {
      content = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space12,
          vertical: AppDimens.space4,
        ),
        decoration: BoxDecoration(
          color: AppColors.bright,
          borderRadius: AppDimens.borderRadiusBadge,
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
        ),
        child: Text(
          AppStrings.nearMiss,
          style: AppTextStyles.secondaryText.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _showDangerBorder ? AppColors.danger : AppColors.ink;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Geri bildirim alanı (Canlı Bölge)
        _buildFeedbackBanner(),

        // Giriş alanı ve Gönder butonu
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final offset = math.sin(_shakeController.value * math.pi * 6) * 6.0;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: Row(
            children: [
              // Metin giriş kutusu
              Expanded(
                child: Opacity(
                  opacity: widget.isMyTurn ? 1.0 : 0.6,
                  child: Container(
                    height: AppDimens.inputHeight,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusInput,
                      border: Border.all(
                        color: borderColor,
                        width: AppDimens.borderThick,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      readOnly: !widget.isMyTurn,
                      maxLength: AttemptTextSanitizer.maxLength,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      style: AppTextStyles.inputField,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: widget.isMyTurn
                            ? AppStrings.inputPlaceholder
                            : AppStrings.turnOpponentHint,
                        hintStyle: AppTextStyles.inputField.copyWith(
                          color: AppColors.muted.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.space10),

              // Gönder Butonu (54x54, primary zemin, 18 köşe, 0 4px 0 ink gölge)
              Semantics(
                button: true,
                label: AppStrings.send,
                child: GestureDetector(
                  onTap: _handleSend,
                  child: Container(
                    width: AppDimens.inputHeight,
                    height: AppDimens.inputHeight,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppDimens.borderRadiusInput,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThick,
                      ),
                      boxShadow: AppDimens.shadowSendButton,
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(
                      AppIcons.arrowSend,
                      color: AppColors.card,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

