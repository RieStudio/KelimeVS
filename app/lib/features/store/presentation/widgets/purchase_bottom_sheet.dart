import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/avatar_frame_registry.dart';
import '../../../../core/widgets/player_avatar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/secondary_button.dart';
import '../../domain/models/store_item.dart';

/// Mağazada bir çerçeveye dokunulduğunda açılan detay ve satın alma modalı.
class PurchaseBottomSheet extends StatefulWidget {
  final StoreItem item;
  final int userCoins;
  final String playerName;
  final Future<void> Function()? onBuy;
  final Future<void> Function()? onEquip;

  const PurchaseBottomSheet({
    super.key,
    required this.item,
    required this.userCoins,
    required this.playerName,
    this.onBuy,
    this.onEquip,
  });

  @override
  State<PurchaseBottomSheet> createState() => _PurchaseBottomSheetState();
}

class _PurchaseBottomSheetState extends State<PurchaseBottomSheet> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canAfford = widget.userCoins >= item.price;
    final displayName = AppStrings.frameDisplayName(item.id);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Üst Çubuk: Başlık ve Kapat Butonu
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      displayName,
                      style: AppTextStyles.cardTitle.copyWith(fontSize: 20),
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  semanticLabel: AppStrings.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space20),

            // Büyük Avatar Önizleme (104 px, kullanılabilir genişliğin %90'ını aşmayacak şekilde sınırlı)
            LayoutBuilder(
              builder: (context, constraints) {
                double targetAvatarSize = 104.0;
                if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
                  final maxAllowedFrame = constraints.maxWidth * 0.90;
                  final def = VisualFrameRegistry.getDefinition(item.id);
                  if (def != null) {
                    final idealFrame = targetAvatarSize / def.innerRatio;
                    if (idealFrame > maxAllowedFrame) {
                      final clampedFrame = maxAllowedFrame;
                      targetAvatarSize = clampedFrame * def.innerRatio;
                    }
                  }
                }
                return PlayerAvatar.selfMatch(
                  name: widget.playerName,
                  frame: item.id,
                  size: targetAvatarSize,
                );
              },
            ),
            const SizedBox(height: AppDimens.space16),

            // Fiyat Rozeti veya Durum
            if (!item.owned) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space16,
                  vertical: AppDimens.space8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppDimens.borderRadiusFull,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.coin,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.ink,
                            width: 1,
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
                      ),
                      const SizedBox(width: AppDimens.space8),
                      Text(
                        '${item.price} Jeton',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                item.isEquipped
                    ? AppStrings.equippedStatus
                    : 'Koleksiyonunda Mevcut',
                style: AppTextStyles.bodyText.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.space24),

            // Aksiyon Butonu
            if (item.isEquipped)
              const PrimaryButton(
                text: AppStrings.equippedStatus,
                onPressed: null, // Deaktif
              )
            else if (item.owned)
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : PrimaryButton(
                      text: AppStrings.equipAction,
                      onPressed: () async {
                        if (_isSubmitting) return;
                        final nav = Navigator.of(context);
                        setState(() => _isSubmitting = true);
                        try {
                          await widget.onEquip?.call();
                          if (mounted) nav.pop();
                        } finally {
                          if (mounted) setState(() => _isSubmitting = false);
                        }
                      },
                    )
            else if (canAfford)
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : PrimaryButton(
                      text: '${AppStrings.buyAction} (${item.price} Jeton)',
                      onPressed: () async {
                        if (_isSubmitting) return;
                        final nav = Navigator.of(context);
                        setState(() => _isSubmitting = true);
                        try {
                          await widget.onBuy?.call();
                          if (mounted) nav.pop();
                        } finally {
                          if (mounted) setState(() => _isSubmitting = false);
                        }
                      },
                    )
            else
              const SecondaryButton(
                text: AppStrings.insufficientCoins,
                onPressed: null, // Yetersiz bakiye
              ),
            const SizedBox(height: AppDimens.space8),
          ],
        ),
      ),
    );
  }
}

