import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../application/leaderboard_providers.dart';
import '../domain/models/leaderboard_models.dart';

/// DESIGN.md Bölüm 7 & GDD 5.4: Haftalık Liderlik Tablosu
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardNotifierProvider);

    return Scaffold(
      key: const Key('leaderboard_screen'),
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppDimens.space12),

            // 1. Üst Çubuk: Geri butonu, Başlık ve Kalan Süre Rozeti
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
              ),
              child: Row(
                children: [
                  AppIconButton(
                    key: const Key('leaderboard_back_button'),
                    icon: AppIcons.back,
                    semanticLabel: AppStrings.back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  const Expanded(
                    child: Text(
                      AppStrings.leaderboardTitle,
                      style: AppTextStyles.screenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Kalan Süre Rozeti (Pazartesi 00:00'a kadar)
                  leaderboardAsync.maybeWhen(
                    data: (data) => _CountdownPill(data: data),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimens.space16),

            // 2. Ana Gövde (Durumlara göre)
            Expanded(
              child: leaderboardAsync.when(
                loading: () => const Center(
                  key: Key('leaderboard_loading'),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, _) => _ErrorView(
                  onRetry: () => ref
                      .read(leaderboardNotifierProvider.notifier)
                      .refresh(),
                ),
                data: (data) {
                  if (data.top.isEmpty) {
                    return _EmptyView(
                      onPlay: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const MatchmakingScreen(),
                          ),
                        );
                      },
                    );
                  }

                  final isMeInTop = data.top.any((entry) => entry.isMe);
                  final showStickyMe = data.me != null && !isMeInTop;

                  return Stack(
                    children: [
                      // Kaydırılabilir Sıralama Listesi
                      RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: () => ref
                            .read(leaderboardNotifierProvider.notifier)
                            .refresh(),
                        child: ListView.separated(
                          key: const Key('leaderboard_list'),
                          padding: EdgeInsets.only(
                            left: AppDimens.screenPaddingHorizontal,
                            right: AppDimens.screenPaddingHorizontal,
                            top: AppDimens.space8,
                            bottom: showStickyMe
                                ? 88.0
                                : AppDimens.screenPaddingHorizontal,
                          ),
                          itemCount: data.top.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppDimens.space10),
                          itemBuilder: (context, index) {
                            final entry = data.top[index];
                            return _LeaderboardItemCard(
                              key: Key('leaderboard_item_${entry.rank}'),
                              entry: entry,
                            );
                          },
                        ),
                      ),

                      // İlk 50 dışındaki oyuncu için alt yapışkan "Senin Sıran" çubuğu
                      if (showStickyMe)
                        Positioned(
                          left: AppDimens.screenPaddingHorizontal,
                          right: AppDimens.screenPaddingHorizontal,
                          bottom: AppDimens.space12,
                          child: _StickyMeBar(me: data.me!),
                        ),
                    ],
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

/// Kalan süreyi gösteren rozet (Pazartesi 00:00 Europe/Istanbul)
class _CountdownPill extends StatelessWidget {
  final LeaderboardData data;

  const _CountdownPill({required this.data});

  @override
  Widget build(BuildContext context) {
    final remainingText = data.formatRemainingTime();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.radiusNavPill),
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(
            AppIcons.leaderboard,
            size: 16,
            color: AppColors.muted,
          ),
          const SizedBox(width: AppDimens.space4),
          Text(
            remainingText,
            style: AppTextStyles.secondaryText.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Liderlik tablosundaki her bir oyuncu kartı
class _LeaderboardItemCard extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderboardItemCard({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = entry.isMe;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space12,
      ),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFE8F5E9) : AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: isMe ? AppColors.primary : AppColors.mint,
          width: isMe ? AppDimens.borderThick : AppDimens.borderThin,
        ),
        boxShadow: AppDimens.shadowQuestionCard,
      ),
      child: Row(
        children: [
          // Sıra Rozeti (İlk 3 özel rozetli)
          _RankBadge(rank: entry.rank),

          const SizedBox(width: AppDimens.space12),

          // Oyuncu Avatarı
          isMe
              ? PlayerAvatar.selfHome(
                  name: entry.nickname,
                  frame: entry.frame,
                  size: AppDimens.avatarMatch,
                  borderWidth: AppDimens.borderThin,
                )
              : PlayerAvatar.opponent(
                  name: entry.nickname,
                  frame: entry.frame,
                  size: AppDimens.avatarMatch,
                  borderWidth: AppDimens.borderThin,
                ),

          const SizedBox(width: AppDimens.space12),

          // Takma Ad
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.nickname,
                    style: AppTextStyles.playerName.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isMe ? AppColors.primary : AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: AppDimens.space6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space6,
                      vertical: 2.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: AppDimens.borderRadiusBadge,
                    ),
                    child: Text(
                      AppStrings.you,
                      style: AppTextStyles.resultBadge.copyWith(
                        color: AppColors.card,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: AppDimens.space8),

          // Galibiyet Sayısı
          Text(
            '${entry.wins}${AppStrings.winsSuffix}',
            style: AppTextStyles.bodyText.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 1., 2., 3. ve diğer sıralar için rozet
class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor = AppColors.ink;

    switch (rank) {
      case 1:
        bgColor = AppColors.coin;
        break;
      case 2:
        bgColor = AppColors.bright;
        break;
      case 3:
        bgColor = AppColors.mint;
        break;
      default:
        bgColor = Colors.transparent;
    }

    if (rank <= 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$rank',
          style: AppTextStyles.playerName.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      );
    }

    return SizedBox(
      width: 32,
      child: Text(
        '#$rank',
        textAlign: TextAlign.center,
        style: AppTextStyles.secondaryText.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// İlk 50 dışındaki oyuncunun sırasını gösteren yapışkan çubuk
class _StickyMeBar extends StatelessWidget {
  final LeaderboardMe me;

  const _StickyMeBar({required this.me});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('leaderboard_sticky_me'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space14,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThick,
        ),
        boxShadow: AppDimens.shadowSecondaryButton,
      ),
      child: Row(
        children: [
          const AppIcon(
            AppIcons.trophy,
            size: 24,
            color: AppColors.coin,
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: Text(
              AppStrings.yourRank(me.rank, me.wins),
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş liste görünümü ("Bu hafta henüz maç yok")
class _EmptyView extends StatelessWidget {
  final VoidCallback onPlay;

  const _EmptyView({required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('leaderboard_empty'),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.mint,
              width: AppDimens.borderThin,
            ),
            boxShadow: AppDimens.shadowQuestionCard,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(
                AppIcons.trophy,
                size: 64,
                color: AppColors.coin,
              ),
              const SizedBox(height: AppDimens.space16),
              const Text(
                AppStrings.emptyLeaderboard,
                style: AppTextStyles.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space8),
              const Text(
                AppStrings.emptyLeaderboardSubtitle,
                style: AppTextStyles.bodyText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space20),
              PrimaryButton(
                text: AppStrings.quickMatch,
                onPressed: onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hata durumu görünümü
class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('leaderboard_error'),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.dangerSoft,
              width: AppDimens.borderThin,
            ),
            boxShadow: AppDimens.shadowQuestionCard,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStrings.leaderboardError,
                style: AppTextStyles.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space8),
              const Text(
                AppStrings.networkError,
                style: AppTextStyles.bodyText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space20),
              SecondaryButton(
                text: AppStrings.retry,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
