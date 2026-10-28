import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/coin_pill.dart';
import '../../../core/widgets/energy_pill.dart';
import '../../../core/widgets/kelime_vs_logo.dart';
import '../../../core/widgets/match_card.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../../main.dart';
import '../../friend_match/presentation/friend_duel_bottom_sheet.dart';
import '../../game/application/match_history_provider.dart';
import '../../match_detail/presentation/match_detail_screen.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../../store/application/store_notifier.dart';
import '../../store/domain/models/store_item.dart';
import '../../store/presentation/widgets/energy_depleted_bottom_sheet.dart';

/// DESIGN.md Bölüm 7: 1) Ana Ekran
///
/// Üstte: avatar (44) + oyuncu adı + jeton hapı + ayarlar ikon butonu.
/// Logo ortalı, altında "Hızlı düşün, doğru yaz!" sloganı.
/// Butonlar: "Hızlı Maç" (ana, alt yazılı) ve "Arkadaşınla Oyna" (ikincil).
/// Altında "SON MAÇLARIM" etiketi ve son 10 maçın kaydırılabilir listesi.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(networkStatusProvider);
    final historyAsync = ref.watch(matchHistoryProvider);
    final profile = ref.watch(profileProvider);
    final nickname =
        (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : AppStrings.defaultPlayerName;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppDimens.space12),

              // 1. Üst Çubuk
              Row(
                children: [
                  // Oyuncu Avatarı (44 px, selfHome) ve Adı - Dokunulduğunda Profil sekmesine geçer
                  Flexible(
                    child: GestureDetector(
                      key: const Key('profile_avatar_button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ref.read(bottomNavIndexProvider.notifier).setIndex(3);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayerAvatar.selfHome(
                            name: nickname,
                            frame: profile.equippedFrame,
                            size: AppDimens.avatarHome,
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Flexible(
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.playerName.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: AppDimens.space8),

                  // Jeton Hapı
                  CoinPill(amount: profile.coins),

                  if (profile.energy != null && profile.energy!.enabled) ...[
                    const SizedBox(width: AppDimens.space8),
                    EnergyPill(
                      current: profile.energy!.current,
                      max: profile.energy!.max,
                      onTap: () {
                        ref.read(bottomNavIndexProvider.notifier).setIndex(2);
                        ref
                            .read(storeNotifierProvider.notifier)
                            .setTab(StoreTab.energy);
                      },
                    ),
                  ],

                  const SizedBox(width: AppDimens.space8),

                  // Sıralama (Kupa) İkon Butonu: Sekme 1'e geçiş
                  AppIconButton(
                    key: const Key('leaderboard_button'),
                    icon: AppIcons.trophy,
                    semanticLabel: AppStrings.leaderboard,
                    onTap: () {
                      ref.read(bottomNavIndexProvider.notifier).setIndex(1);
                    },
                  ),

                  const SizedBox(width: AppDimens.space8),

                  // Ayarlar İkon Butonu: Ayarlar ekranına geçiş
                  AppIconButton(
                    key: const Key('settings_button'),
                    icon: AppIcons.settings,
                    semanticLabel: AppStrings.settings,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppDimens.space20),

              // 2. Logo ve Slogan
              const Center(child: KelimeVSLogo()),
              const SizedBox(height: AppDimens.space8),
              Center(
                child: Text(
                  AppStrings.slogan,
                  style: AppTextStyles.bodyText.copyWith(
                    color: AppColors.muted,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: AppDimens.space20),

              // 3. "Hızlı Maç" Ana Butonu
              PrimaryButton(
                text: AppStrings.quickMatch,
                subtitle: AppStrings.quickMatchSubtitle,
                isLarge: true,
                onPressed: () {
                  if (!ensureNetworkConnected(context, ref)) return;

                  final energy = profile.energy;
                  if (energy != null && energy.enabled && energy.current <= 0) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => EnergyDepletedBottomSheet(
                        energy: energy,
                        userCoins: profile.coins,
                        serverNowMs: profile.serverNowMs,
                        onPlayWithBot: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MatchmakingScreen(
                                forceBotFallback: true,
                              ),
                            ),
                          );
                        },
                        onEnergyPurchased: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MatchmakingScreen(),
                            ),
                          );
                        },
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MatchmakingScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: AppDimens.space10),

              // 4. "Arkadaşınla Oyna" İkincil Butonu
              SecondaryButton(
                text: AppStrings.playWithFriend,
                onPressed: () {
                  if (!ensureNetworkConnected(context, ref)) return;

                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const FriendDuelBottomSheet(),
                  );
                },
              ),

              const SizedBox(height: AppDimens.space20),

              // 5. "SON MAÇLARIM" Bölüm Etiketi
              const SectionLabel(AppStrings.recentMatches),

              const SizedBox(height: AppDimens.space10),

              // 6. Maç Kartları Listesi (Kaydırma çubuğu gizli)
              Expanded(
                child: historyAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (err, stack) => _buildEmptyState(profile),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return _buildEmptyState(profile);
                    }

                    // Sıralama: finishedAtMs azalan; eşitlikte sonradan eklenen üstte (gelen listedeki index küçük olan üstte)
                    final indexedEntries = entries.asMap().entries.toList();
                    indexedEntries.sort((a, b) {
                      final cmp = b.value.finishedAtMs.compareTo(
                        a.value.finishedAtMs,
                      );
                      if (cmp != 0) return cmp;
                      return a.key.compareTo(b.key);
                    });
                    final sortedEntries = indexedEntries
                        .map((e) => e.value)
                        .toList();

                    final count = math.min(10, sortedEntries.length);

                    return ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(
                        scrollbars: false,
                      ),
                      child: ListView.builder(
                        itemCount: count,
                        itemBuilder: (context, index) {
                          final entry = sortedEntries[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppDimens.space10,
                            ),
                            child: MatchCard(
                              entry: entry,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MatchDetailScreen(match: entry),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ProfileState profile) {
    final hasRemoteMatches = profile.isLoaded &&
        profile.syncError == null &&
        profile.stats.played > 0;
    final message = hasRemoteMatches
        ? AppStrings.noMatchesHistoryReset
        : AppStrings.noMatchesYet;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space20,
        vertical: AppDimens.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(color: AppColors.mint, width: AppDimens.borderThin),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodyText.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
