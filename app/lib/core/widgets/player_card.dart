import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: Oyuncu Kartı (Maç Ekranı)
///
/// Zemin card, 3 px ink kenarlık, köşe 20. Avatar 36, ad, skor (Fredoka 34).
/// Sırası olan oyuncunun kartı süre göstergesidir:
/// Kartın içinde bright bir dolgu soldan sağa kalan süre oranında uzanır ve sağdan sola azalır;
/// ad altında "N sn" yazar. Sırası olmayan kartta dolgu ve süre yazısı yoktur.
/// Kalan süre 5 saniyeye inince dolgu dangerSoft (açık kırmızı) tonuna 200 ms'de geçer.
/// Dolgu semantik olarak "Kalan süre" progressbar olarak etiketlenir.
class PlayerCard extends StatelessWidget {
  final String name;
  final int score;
  final Widget avatar;
  final bool isActive;
  final int? remainingSeconds;
  final double? timeProgress;
  final String? statusNote;

  const PlayerCard({
    super.key,
    required this.name,
    required this.score,
    required this.avatar,
    this.isActive = false,
    this.remainingSeconds,
    this.timeProgress,
    this.statusNote,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (timeProgress ?? 0.0).clamp(0.0, 1.0);
    final isDanger = remainingSeconds != null && remainingSeconds! <= 5;
    final fillColor = isDanger ? AppColors.dangerSoft : AppColors.bright;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
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
            offset: Offset(0, 3),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusListCard - AppDimens.borderThick),
        child: Stack(
          children: [
            // Kalan süre ilerleme dolgusu (sadece aktif oyuncuda)
            if (isActive)
              Positioned.fill(
                child: Semantics(
                  label: AppStrings.timeLeftLabel,
                  value: remainingSeconds != null
                      ? '$remainingSeconds${AppStrings.secondsSuffix}'
                      : null,
                  container: true,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: fillColor,
                    ),
                  ),
                ),
              ),

            // İçerik: Avatar, Ad (+ opsiyonel Durum Notu / Kalan Süre) ve Skor
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space10,
                vertical: AppDimens.space8,
              ),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: AppDimens.space8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.playerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (statusNote != null)
                          Text(
                            statusNote!,
                            style: AppTextStyles.opponentConnectionNote,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (isActive && remainingSeconds != null)
                          Text(
                            '$remainingSeconds${AppStrings.secondsSuffix}',
                            style: AppTextStyles.secondaryText,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Text(
                    '$score',
                    style: AppTextStyles.scoreSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

