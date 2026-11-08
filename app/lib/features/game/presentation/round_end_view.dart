import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/opponent_name_sanitizer.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/question_preview_card.dart';
import '../../../core/widgets/round_result_icon.dart';
import '../application/match_providers.dart';
import '../domain/match/match_events.dart';

/// DESIGN.md Bölüm 7: 4) Tur Sonu Ekranı
///
/// Üstte "Tur N" hapı.
/// Ortada 104 px RoundResultIcon, başlık, neden ve skor kartı (Fredoka 52).
/// Altta "Tur N+1 birazdan başlıyor" (beraberlikte "Yeni tur birazdan başlıyor",
/// son turda "Maç sonucu birazdan") ve geri sayım çubuğu.
class RoundEndView extends ConsumerStatefulWidget {
  const RoundEndView({super.key});

  @override
  ConsumerState<RoundEndView> createState() => _RoundEndViewState();
}

class _RoundEndViewState extends ConsumerState<RoundEndView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scorePulseAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _scorePulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_animController);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(activeMatchUiStateProvider);
    final matchState = uiState.matchState;

    final roundHistory = matchState?.roundHistory ?? const [];
    final lastRound = roundHistory.isNotEmpty ? roundHistory.last : null;

    final isWinner = lastRound?.winnerId == 'me';
    final isLoser = lastRound?.winnerId != null && lastRound?.winnerId != 'me';
    final isDraw = lastRound?.winnerId == null;

    final RoundResultVariant resultVariant;
    final String title;
    final TextStyle titleStyle;
    final String reasonText;

    if (isWinner) {
      resultVariant = RoundResultVariant.win;
      title = AppStrings.roundWonTitle;
      titleStyle = AppTextStyles.roundResultTitle;
      reasonText = lastRound?.reason == RoundEndReason.timeout
          ? AppStrings.reasonOpponentTimeout
          : AppStrings.reasonExhausted;
    } else if (isLoser) {
      resultVariant = RoundResultVariant.lose;
      title = AppStrings.roundLostTitle;
      titleStyle = AppTextStyles.roundResultTitleDanger;
      reasonText = lastRound?.reason == RoundEndReason.timeout
          ? AppStrings.reasonMyTimeout
          : AppStrings.reasonExhausted;
    } else {
      resultVariant = RoundResultVariant.draw;
      title = AppStrings.roundDrawTitle;
      titleStyle = AppTextStyles.roundResultTitle;
      reasonText = AppStrings.reasonExhausted;
    }

    // Tur numarası: sonuçlanan tur için sonuçlanan tur sayısı; beraberlikte sonuçlanan tur sayısı + 1
    final decisiveRounds = matchState?.decisiveRounds ?? 0;
    final roundNumber = isDraw ? decisiveRounds + 1 : math.max(1, decisiveRounds);
    final cappedRoundNumber = math.min(3, roundNumber);

    // Alt metin
    final String nextRoundSubtitle;
    if (uiState.isFinalReveal) {
      nextRoundSubtitle = AppStrings.matchResultStartingSoon;
    } else if (isDraw) {
      nextRoundSubtitle = AppStrings.newRoundStartingSoon;
    } else {
      final nextNum = math.min(3, cappedRoundNumber + 1);
      nextRoundSubtitle =
          '${AppStrings.roundPrefix}$nextNum${AppStrings.nextRoundStartingSoonSuffix}';
    }

    // Geri sayım çubuğu süresi
    final totalMs = uiState.roundTransitionTotalMs;
    final remainingMs = uiState.roundTransitionRemainingMs;

    final myScore = matchState?.scores['me'] ?? 0;
    final opponentScore = matchState?.scores['bot'] ?? 0;

    final rawOpponentName = (uiState.lastSavedMatch?.opponentName.trim().isNotEmpty ?? false)
        ? uiState.lastSavedMatch!.opponentName
        : uiState.opponentName;
    final opponentDisplayName = OpponentNameSanitizer.sanitize(rawOpponentName);

    final Widget content = Container(
      color: AppColors.surface,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.space12,
          ),
          child: Column(
            children: [
              // 1. Üst "Tur N" Hapı
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppDimens.borderRadiusFull,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: Text(
                    AppStrings.round(cappedRoundNumber),
                    style: AppTextStyles.questionText.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // 2. Tur Sonu SVG İkonu (104 px)
              RoundResultIcon(
                variant: resultVariant,
              ),

              const SizedBox(height: AppDimens.space20),

              // 3. Başlık
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: AppDimens.space8),

              // 4. Neden Metni
              Text(
                reasonText,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppDimens.space24),

              // 5. Skor Kartı ("Sen  –  Rakip" / "Sen  –  <RakipAdı>", Fredoka 52)
              Semantics(
                label: 'Skor: Sen $myScore, $opponentDisplayName $opponentScore',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimens.space20,
                    horizontal: AppDimens.space24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppDimens.borderRadiusListCard,
                    border: Border.all(
                      color: AppColors.mint,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Sen
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppStrings.you,
                              style: AppTextStyles.playerName.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppDimens.space4),
                            ScaleTransition(
                              scale: isWinner
                                  ? _scorePulseAnim
                                  : const AlwaysStoppedAnimation(1.0),
                              child: Text(
                                '$myScore',
                                style: AppTextStyles.scoreLarge,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Ayırıcı Tire
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space12,
                        ),
                        child: Text(
                          '–',
                          style: AppTextStyles.scoreLarge,
                        ),
                      ),

                      // Rakip
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Visibility(
                                  visible: false,
                                  maintainSize: true,
                                  maintainAnimation: true,
                                  maintainState: true,
                                  child: Text(
                                    ' ',
                                    style: AppTextStyles.playerName.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    opponentDisplayName,
                                    maxLines: 1,
                                    style: AppTextStyles.playerName.copyWith(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimens.space4),
                            ScaleTransition(
                              scale: isLoser
                                  ? _scorePulseAnim
                                  : const AlwaysStoppedAnimation(1.0),
                              child: Text(
                                '$opponentScore',
                                style: AppTextStyles.scoreLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (uiState.nextQuestionText != null && !uiState.isFinalReveal) ...[
                const Spacer(flex: 1),
                Text(
                  AppStrings.nextQuestionLabel,
                  key: const ValueKey('round_end_next_question_label'),
                  style: AppTextStyles.questionPreviewLabel,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space6),
                QuestionPreviewCard(
                  key: const ValueKey('round_end_next_question_card'),
                  categoryText: uiState.nextQuestionText!,
                ),
                const Spacer(flex: 1),
              ] else ...[
                const Spacer(flex: 4),
              ],

              // 6. Alttaki Subtitle Metni
              Text(
                nextRoundSubtitle,
                style: AppTextStyles.secondaryText.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppDimens.space10),

              // 7. Geri Sayım Çubuğu (controller'dan gelen kalan süreye bağlı)
              Semantics(
                label: AppStrings.timeLeftLabel,
                value: '$remainingMs ms',
                child: AppProgressBar.countdown(
                  key: const ValueKey('round_end_progress_bar'),
                  totalDurationMs: totalMs,
                  remainingMs: remainingMs,
                  isActive: true,
                  isPaused: uiState.isPaused,
                ),
              ),

              const SizedBox(height: AppDimens.space8),
            ],
          ),
        ),
      ),
    );

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      return content;
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: content,
    );
  }
}

