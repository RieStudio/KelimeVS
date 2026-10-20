import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../application/blocked_users_notifier.dart';
import '../domain/blocked_user_model.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  String _formatDate(int timestampMs) {
    if (timestampMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day.$month.$year';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Üst Başlık Çubuğu
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
                vertical: AppDimens.space12,
              ),
              child: Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.back,
                    semanticLabel: AppStrings.back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  const Text(
                    AppStrings.blockedUsersTitle,
                    style: AppTextStyles.screenTitle,
                  ),
                ],
              ),
            ),

            // Liste Alanı
            Expanded(
              child: state.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
                error: (_, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.space24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          AppStrings.blockedUsersError,
                          style: AppTextStyles.cardTitle,
                        ),
                        const SizedBox(height: AppDimens.space12),
                        SecondaryButton(
                          text: AppStrings.retry,
                          onPressed: () =>
                              ref.read(blockedUsersProvider.notifier).refresh(),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimens.space24),
                        child: Container(
                          padding: const EdgeInsets.all(AppDimens.space24),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppDimens.borderRadiusListCard,
                            border: Border.all(
                              color: AppColors.mint,
                              width: AppDimens.borderThin,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppStrings.emptyBlockedUsers,
                                style: AppTextStyles.cardTitle.copyWith(
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: AppDimens.space8),
                              const Text(
                                AppStrings.emptyBlockedUsersSubtitle,
                                style: AppTextStyles.bodyText,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                      vertical: AppDimens.space12,
                    ),
                    itemCount: users.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppDimens.space12),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return _BlockedUserTile(
                        user: user,
                        formattedDate: _formatDate(user.blockedAt),
                        onUnblock: () async {
                          final success = await ref
                              .read(blockedUsersProvider.notifier)
                              .unblock(user.id);
                          if (!context.mounted) return;
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  AppStrings.unblockSuccess,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontNunito,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                backgroundColor: AppColors.ink,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  AppStrings.unblockGenericError,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontNunito,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                backgroundColor: AppColors.ink,
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final BlockedUser user;
  final String formattedDate;
  final VoidCallback onUnblock;

  const _BlockedUserTile({
    required this.user,
    required this.formattedDate,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final firstChar = user.nickname.isNotEmpty
        ? user.nickname.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space12,
      ),
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
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.mint,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              firstChar,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFredoka,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space12),

          // Takma ad ve tarih
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.nickname,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
                if (formattedDate.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    formattedDate,
                    style: AppTextStyles.bodyText.copyWith(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: AppDimens.space12),

          // "Kaldır" Butonu
          SecondaryButton(
            text: AppStrings.unblockAction,
            height: 42,
            width: 84,
            onPressed: onUnblock,
          ),
        ],
      ),
    );
  }
}
