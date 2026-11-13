import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import 'friend_host_screen.dart';
import 'friend_join_screen.dart';

/// "Arkadaşla Düello" modunda "Oda Kur" veya "Koda Katıl" seçimi sunan alt sayfa modalı.
class FriendDuelBottomSheet extends ConsumerWidget {
  const FriendDuelBottomSheet({super.key});

  /// "Oda Kur" kartı için çok renkli SVG ikonu.
  static const String createRoomAsset = 'assets/icons/friend_create_room.svg';

  /// "Koda Katıl" kartı için çok renkli SVG ikonu.
  static const String joinRoomAsset = 'assets/icons/friend_join_code.svg';

  /// Kart içi SVG ikon boyutu (dp).
  static const double iconSize = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusCardLarge),
        ),
      ),
      padding: EdgeInsets.only(
        left: AppDimens.screenPaddingHorizontal,
        right: AppDimens.screenPaddingHorizontal,
        top: AppDimens.space20,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.space32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sürükleme Tutamacı
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space16),

          // Başlık
          const Text(
            AppStrings.friendDuel,
            style: AppTextStyles.screenTitle,
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            AppStrings.friendDuelSubtitle,
            style: AppTextStyles.bodyText.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppDimens.space20),

          // 1. "Oda Kur" Seçim Kartı
          _buildActionCard(
            context: context,
            svgAsset: createRoomAsset,
            title: AppStrings.createRoom,
            subtitle: AppStrings.createRoomSubtitle,
            onTap: () {
              if (!ensureNetworkConnected(context, ref)) return;
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FriendHostScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: AppDimens.space12),

          // 2. "Koda Katıl" Seçim Kartı
          _buildActionCard(
            context: context,
            svgAsset: joinRoomAsset,
            title: AppStrings.joinRoom,
            subtitle: AppStrings.joinRoomSubtitle,
            onTap: () {
              if (!ensureNetworkConnected(context, ref)) return;
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FriendJoinScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String svgAsset,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimens.space16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppDimens.borderRadiusListCard,
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.ink,
              offset: Offset(0, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SvgPicture.asset(
                svgAsset,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: AppDimens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodyText.copyWith(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
