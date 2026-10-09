import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../../features/game/domain/history/match_history_entry.dart';
import 'player_avatar.dart';
import 'result_badge.dart';

/// DESIGN.md Bölüm 6: Maç Kartı (Ana ekran listesi)
/// Tüm kart tek dokunma alanı. Soldan sağa:
/// avatar 40 · ad (Nunito 16/800, tek satır, dikey ortalı) ·
/// skor (Fredoka 22, sabit 56 genişlik, ortalı) · sonuç etiketi (88) · sağ ok 16.
/// Kenarlık: kazanılan maç mint, kaybedilen maç dangerSoft.
class MatchCard extends StatelessWidget {
  final MatchHistoryEntry entry;
  final VoidCallback? onTap;

  const MatchCard({
    super.key,
    required this.entry,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWon = entry.result == MatchResult.win;
    final borderColor = isWon ? AppColors.mint : AppColors.dangerSoft;

    return Semantics(
      button: true,
      label: '${entry.opponentName}, ${entry.myScore} – ${entry.opponentScore}, '
          '${isWon ? AppStrings.won : AppStrings.lost}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space12,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: borderColor,
              width: AppDimens.borderThin,
            ),
          ),
          child: Row(
            children: [
              // 1. Rakip Avatarı (40 px)
              PlayerAvatar.opponent(
                name: entry.opponentName,
                size: AppDimens.avatarList,
                borderWidth: AppDimens.borderThin,
              ),

              const SizedBox(width: AppDimens.space12),

              // 2. Rakip Adı (Nunito 16/800, tek satır, dikey ortalı, uzunsa kısalt)
              Expanded(
                child: Text(
                  entry.opponentName,
                  style: AppTextStyles.playerName.copyWith(
                    color: AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 3. Skor (Fredoka 22, sabit 56 genişlik, ortalı)
              SizedBox(
                width: 56,
                child: Text(
                  '${entry.myScore}${AppStrings.scoreDash}${entry.opponentScore}',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(width: AppDimens.space10),

              // 4. Sonuç Etiketi (ResultBadge, sabit 88 genişlik)
              isWon ? const ResultBadge.won() : const ResultBadge.lost(),

              const SizedBox(width: AppDimens.space8),

              // 5. Sağ Ok (16 px)
              const AppIcon(
                AppIcons.arrowList,
                size: 16,
                color: AppColors.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
