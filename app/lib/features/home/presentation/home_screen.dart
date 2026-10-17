import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/coin_pill.dart';
import '../../../core/widgets/kelime_go_logo.dart';
import '../../../core/widgets/match_card.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../../gallery/component_gallery.dart';
import '../../game/application/match_history_provider.dart';
import '../../match_detail/presentation/match_detail_screen.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../../profile/presentation/profile_screen.dart';

/// DESIGN.md Bölüm 7: 1) Ana Ekran
///
/// Üstte: avatar (44) + oyuncu adı + jeton hapı + ayarlar ikon butonu.
/// Logo ortalı, altında "Hızlı düşün, doğru yaz!" sloganı.
/// Butonlar: "Hızlı Maç" (ana, alt yazılı) ve "Arkadaşınla Oyna" (ikincil).
/// Altında "SON MAÇLARIM" etiketi ve son 10 maçın kaydırılabilir listesi.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _showComingSoonDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: AppDimens.borderRadiusDialog,
            side: const BorderSide(
              color: AppColors.ink,
              width: AppDimens.borderThick,
            ),
          ),
          title: const Text(
            AppStrings.comingSoon,
            style: AppTextStyles.cardTitle,
          ),
          content: const Text(
            AppStrings.playWithFriendComingSoon,
            style: AppTextStyles.bodyText,
          ),
          actions: [
            PrimaryButton(
              text: AppStrings.ok,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(matchHistoryProvider);
    final profile = ref.watch(profileProvider);
    final nickname = (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
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
                  // Oyuncu Avatarı (44 px, selfHome) ve Adı - Dokunulduğunda Profil ekranını açar
                  GestureDetector(
                    key: const Key('profile_avatar_button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlayerAvatar.selfHome(
                          name: nickname,
                          size: AppDimens.avatarHome,
                        ),
                        const SizedBox(width: AppDimens.space8),
                        Text(
                          nickname,
                          style: AppTextStyles.playerName.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Jeton Hapı
                  CoinPill(amount: profile.coins),

                  const SizedBox(width: AppDimens.space8),

                  // Ayarlar İkon Butonu (kDebugMode'da ComponentGallery, release'te boş)
                  AppIconButton(
                    icon: AppIcons.settings,
                    semanticLabel: AppStrings.settings,
                    onTap: () {
                      if (kDebugMode) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ComponentGallery(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: AppDimens.space20),

              // 2. Logo ve Slogan
              const Center(
                child: KelimeGoLogo(),
              ),
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
                onPressed: () => _showComingSoonDialog(context),
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
                  error: (err, stack) => _buildEmptyState(),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return _buildEmptyState();
                    }

                    // Sıralama: finishedAtMs azalan; eşitlikte sonradan eklenen üstte (gelen listedeki index küçük olan üstte)
                    final indexedEntries = entries.asMap().entries.toList();
                    indexedEntries.sort((a, b) {
                      final cmp = b.value.finishedAtMs.compareTo(a.value.finishedAtMs);
                      if (cmp != 0) return cmp;
                      return a.key.compareTo(b.key);
                    });
                    final sortedEntries = indexedEntries.map((e) => e.value).toList();

                    final count = math.min(10, sortedEntries.length);

                    return ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(scrollbars: false),
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
                                    builder: (_) => MatchDetailScreen(match: entry),
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

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space20,
        vertical: AppDimens.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Text(
        AppStrings.noMatchesYet,
        style: AppTextStyles.bodyText.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
