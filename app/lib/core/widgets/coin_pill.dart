import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 7: Jeton ve Enerji Rozeti (CoinPill)
/// Beyaz hap (`card`), 2 px `ink` kenarlık, tam yuvarlak köşeler.
/// Tek kapsül içinde jeton bölümü; enerji aktifse ince dikey ayırıcı (`mint`)
/// ve enerji bölümü (`coin` zeminli yıldırım ikonu + sayı).
/// Enerji bölümüne dokunulduğunda [onEnergyTap] tetiklenir.
class CoinPill extends StatelessWidget {
  final int amount;
  final int? energyCurrent;
  final int? energyMax;
  final VoidCallback? onEnergyTap;
  final VoidCallback? onCoinTap;

  const CoinPill({
    super.key,
    required this.amount,
    this.energyCurrent,
    this.energyMax = 5,
    this.onEnergyTap,
    this.onCoinTap,
  });

  bool get _isCombined => energyCurrent != null;

  Widget _buildCoinIcon() {
    return Container(
      width: 22,
      height: 22,
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
          fontSize: 12,
          color: AppColors.ink,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildEnergyIcon() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: AppColors.coin,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
      ),
      alignment: Alignment.center,
      child: const AppIcon(
        AppIcons.bolt,
        size: 13,
        color: AppColors.ink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Enerji sistemi kapalı / enerji yok: Eski tekil rozetle birebir aynı yapı
    if (!_isCombined) {
      final singleContent = Semantics(
        label: '$amount${AppStrings.coinSuffix}',
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 110.0,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space12,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCoinIcon(),
              const SizedBox(width: AppDimens.space8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$amount',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: AppColors.ink,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      if (onCoinTap != null) {
        return GestureDetector(
          key: const Key('coin_pill_button'),
          behavior: HitTestBehavior.opaque,
          onTap: onCoinTap,
          child: singleContent,
        );
      }
      return singleContent;
    }

    // 2. Birleşik rozet (Jeton | İnce Dikey Ayırıcı | Enerji)
    // Doğal içeriği kadar genişler, Flexible ile yapay esnemez; takma ada maksimum alan bırakır.
    final coinContent = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildCoinIcon(),
        const SizedBox(width: AppDimens.space6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 48.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$amount',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.ink,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );

    final coinWidget = Semantics(
      label: '$amount${AppStrings.coinSuffix}',
      child: onCoinTap != null
          ? GestureDetector(
              key: const Key('coin_pill_button'),
              behavior: HitTestBehavior.opaque,
              onTap: onCoinTap,
              child: coinContent,
            )
          : coinContent,
    );

    final energyContent = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildEnergyIcon(),
        const SizedBox(width: AppDimens.space6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 20.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$energyCurrent',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.ink,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );

    final energyWidget = Semantics(
      label: '$energyCurrent / $energyMax Enerji',
      button: onEnergyTap != null,
      child: onEnergyTap != null
          ? GestureDetector(
              key: const Key('energy_pill_button'),
              behavior: HitTestBehavior.opaque,
              onTap: onEnergyTap,
              child: energyContent,
            )
          : energyContent,
    );

    return Container(
      constraints: const BoxConstraints(
        maxWidth: 160.0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          coinWidget,

          // İnce Dikey Ayırıcı
          Container(
            width: 1.5,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: AppDimens.space6),
            color: AppColors.mint,
          ),

          energyWidget,
        ],
      ),
    );
  }
}
