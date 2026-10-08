import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/result_circle.dart';
import '../application/match_providers.dart';

/// DESIGN.md Bölüm 7: 5) Maç Sonucu Ekranı
///
/// Sol üstte kapat (ana ekrana; şimdilik galeriye döner).
/// Ortada ResultCircle (kazandın: kupa, kaybettin: tekrar oku), başlık,
/// terk notu (varsa), skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı.
/// Altta "Tekrar Oyna" (ana buton).
/// // TODO: Sonraki adımda "Maç Detayı" butonu eklenecek.
class MatchEndView extends ConsumerStatefulWidget {
  const MatchEndView({super.key});

  @override
  ConsumerState<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends ConsumerState<MatchEndView>
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
    final uiState = ref.watch(matchControllerProvider);
    final matchState = uiState.matchState;

    final isWinner = matchState?.winnerId == 'me';
    final isForfeit = matchState?.endedBy == 'forfeit';

    final myScore = matchState?.scores['me'] ?? 0;
    final opponentScore = matchState?.scores['bot'] ?? 0;

    final ResultCircleVariant circleVariant;
    final AppIconData icon;
    final String title;
    final TextStyle titleStyle;

    if (isWinner) {
      circleVariant = ResultCircleVariant.win;
      icon = AppIcons.trophy;
      title = AppStrings.wonExclamation;
      titleStyle = AppTextStyles.largeResult;
    } else {
      circleVariant = ResultCircleVariant.lose;
      icon = AppIcons.refresh;
      title = AppStrings.lost;
      titleStyle = AppTextStyles.largeResultDanger;
    }

    final int coinReward = isWinner
        ? AppConfig.matchWinCoinReward
        : AppConfig.matchLoseCoinReward;

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
              // 1. Üst Çubuk (Sol üstte Kapat ikonu)
              Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.close,
                    semanticLabel: AppStrings.close,
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                ],
              ),

              const Spacer(flex: 3),

              // 2. ResultCircle (104 px)
              ResultCircle(
                variant: circleVariant,
                icon: icon,
              ),

              const SizedBox(height: AppDimens.space20),

              // 3. Başlık ("Kazandın!" / "Kaybettin")
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),

              // 4. Terk Notu (varsa)
              if (isForfeit) ...[
                const SizedBox(height: AppDimens.space6),
                Text(
                  isWinner ? AppStrings.opponentLeftMatch : AppStrings.youLeftMatch,
                  style: AppTextStyles.secondaryText.copyWith(
                    color: isWinner ? AppColors.muted : AppColors.dangerText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: AppDimens.space16),

              // 5. Skor ("Sen 2 – 1 Rakip")
              Semantics(
                label: 'Skor: Sen $myScore, Rakip $opponentScore',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      AppStrings.you,
                      style: AppTextStyles.questionText.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      '$myScore${AppStrings.scoreDash}$opponentScore',
                      style: AppTextStyles.scoreSmall.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      AppStrings.opponent,
                      style: AppTextStyles.questionText.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimens.space20),

              // 6. Jeton Ödülü Kartı
              Semantics(
                label: 'Jeton ödülü: $coinReward',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space20,
                    vertical: AppDimens.space8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppDimens.borderRadiusFull,
                    border: Border.all(
                      color: AppColors.mint,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Jeton Dairesi ("G")
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.coin,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.ink,
                            width: AppDimens.borderThin,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'G',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFredoka,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.ink,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Text(
                        '+$coinReward${AppStrings.coinSuffix}',
                        style: AppTextStyles.questionText.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 4),

              // 7. Butonlar ("Tekrar Oyna")
              PrimaryButton(
                text: AppStrings.playAgain,
                onPressed: () {
                  ref.read(matchControllerProvider.notifier).startMatch();
                },
              ),

              // TODO: Sonraki adımda "Maç Detayı" butonu eklenecek.
              const SizedBox(height: AppDimens.space12),
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

