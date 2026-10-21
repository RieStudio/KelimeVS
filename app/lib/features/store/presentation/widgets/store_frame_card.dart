import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/player_avatar.dart';
import '../../domain/models/store_item.dart';

/// Mağaza ekranında bir avatar çerçevesini gösteren Neo-brutalist kart.
class StoreFrameCard extends StatelessWidget {
  final StoreItem item;
  final int userCoins;
  final String playerName;
  final bool isLoading;
  final VoidCallback? onEquip;
  final VoidCallback? onBuy;
  final VoidCallback? onPreview;

  const StoreFrameCard({
    super.key,
    required this.item,
    required this.userCoins,
    required this.playerName,
    this.isLoading = false,
    this.onEquip,
    this.onBuy,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final canAfford = userCoins >= item.price;
    final displayName = AppStrings.frameDisplayName(item.id);

    return Semantics(
      container: true,
      button: true,
      label: '$displayName çerçevesi, ${item.owned ? (item.isEquipped ? AppStrings.equippedStatus : AppStrings.equipAction) : '${item.price} jeton'}',
      child: GestureDetector(
        onTap: onPreview,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThick,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(0, 2),
                blurRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppDimens.space12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Avatar Önizleme (72 px)
              PlayerAvatar.selfMatch(
                name: playerName,
                frame: item.id,
                size: 72,
              ),
              const SizedBox(height: AppDimens.space10),

              // 2. Çerçeve Adı
              Text(
                displayName,
                style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppDimens.space10),

              // 3. Durum / Aksiyon Butonu
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildActionButton(context, canAfford),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool canAfford) {
    if (isLoading) {
      return Container(
        key: const ValueKey('loading'),
        height: 36,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.ink),
          ),
        ),
      );
    }

    if (item.isEquipped) {
      // 1. Kuşanıldı (mint zemin, tik ikonu)
      return Container(
        key: const ValueKey('equipped'),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space10),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: AppDimens.borderRadiusFull,
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.ink,
            ),
            SizedBox(width: 4),
            Text(
              AppStrings.equippedStatus,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      );
    }

    if (item.owned) {
      // 2. Sahipsin -> Kuşan butonu
      return SizedBox(
        key: const ValueKey('equip'),
        height: 36,
        width: double.infinity,
        child: Material(
          color: AppColors.mint,
          borderRadius: AppDimens.borderRadiusFull,
          child: InkWell(
            onTap: onEquip,
            borderRadius: AppDimens.borderRadiusFull,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppDimens.borderRadiusFull,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                AppStrings.equipAction,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFredoka,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 3 & 4. Satın Al (Jetonlu Buton)
    final buttonColor = canAfford ? AppColors.coin : AppColors.surface;
    final textColor = canAfford ? AppColors.ink : AppColors.muted;

    return SizedBox(
      key: ValueKey('buy_${item.id}'),
      height: 36,
      width: double.infinity,
      child: Material(
        color: buttonColor,
        borderRadius: AppDimens.borderRadiusFull,
        child: InkWell(
          onTap: onBuy,
          borderRadius: AppDimens.borderRadiusFull,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppDimens.borderRadiusFull,
              border: Border.all(
                color: canAfford ? AppColors.ink : AppColors.muted,
                width: AppDimens.borderThin,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: canAfford ? AppColors.card : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: canAfford ? AppColors.ink : AppColors.muted,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'G',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item.price}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

