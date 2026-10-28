import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/result_circle.dart';
import '../../../core/widgets/smooth_progress_bar.dart';
import '../application/match_providers.dart';
import '../domain/match/match_events.dart';

/// DESIGN.md Bölüm 7: 4) Tur Sonu Ekranı
///
/// Üstte "Tur N" hapı.
/// Ortada 104 px ResultCircle, başlık, neden ve skor kartı (Fredoka 52).
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

    final ResultCircleVariant circleVariant;
    final AppIconData icon;
    final String title;
    final TextStyle titleStyle;
    final String reasonText;

    if (isWinner) {
      circleVariant = ResultCircleVariant.win;
      icon = AppIcons.check;
      title = AppStrings.roundWonTitle;
      titleStyle = AppTextStyles.roundResultTitle;
      reasonText = lastRound?.reason == RoundEndReason.timeout
          ? AppStrings.reasonOpponentTimeout
          : AppStrings.reasonExhausted;
    } else if (isLoser) {
      circleVariant = ResultCircleVariant.lose;
      icon = AppIcons.close;
      title = AppStrings.roundLostTitle;
      titleStyle = AppTextStyles.roundResultTitleDanger;
      reasonText = lastRound?.reason == RoundEndReason.timeout
          ? AppStrings.reasonMyTimeout
          : AppStrings.reasonExhausted;
    } else {
      circleVariant = ResultCircleVariant.draw;
      icon = AppIcons.equal;
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

              // 2. ResultCircle (104 px)
              ResultCircle(
                variant: circleVariant,
                icon: icon,
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

              // 5. Skor Kartı ("Sen  –  Rakip", Fredoka 52)
              Semantics(
                label: 'Skor: Sen $myScore, Rakip $opponentScore',
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
                            Text(
                              '$myScore',
                              style: AppTextStyles.scoreLarge,
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
                            Text(
                              AppStrings.opponent,
                              style: AppTextStyles.playerName.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppDimens.space4),
                            Text(
                              '$opponentScore',
                              style: AppTextStyles.scoreLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 4),

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
                child: Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    borderRadius: AppDimens.borderRadiusFull,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: AppDimens.borderRadiusFull,
                    child: SmoothProgressBar(
                      totalDurationMs: totalMs,
                      remainingMs: remainingMs,
                      isActive: true,
                      isPaused: uiState.isPaused,
                      fillColor: AppColors.primary,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: AppDimens.borderRadiusFull,
                      ),
                    ),
                  ),
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

