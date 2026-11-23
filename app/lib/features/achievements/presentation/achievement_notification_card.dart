import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/achievement_ui_manifest.dart';

/// DESIGN.md ve kural sözleşmesiyle tam uyumlu başarım bildirim kartı.
///
/// Özellikler:
/// - Beyaz kart yüzeyi (AppColors.card).
/// - 3 px kalınlığında koyu yeşil çerçeve (AppColors.ink).
/// - Alt tarafa 4 px ofsetli sert neo-brutalist gölge (AppColors.ink).
/// - Köşe yarıçapı 20 px.
/// - Kartın sol kenarından dışarı taşan (ikon bazında veya varsayılan -12 px),
///   -6 derece (veya ikon bazında ayarlı) eğimli,
///   altında yumuşak gölgesi olan 68 px SVG başarım görseli (ColorFilter UYGULANMAZ).
/// - İkon taşması nedeniyle sol iç boşluk 58 px (metinler ikona çarpmaz).
/// - Kalın koyu yeşil başlık (Fredoka 16 w700, AppColors.ink),
///   daha küçük ve mat yeşil açıklama (Nunito 12 w600, AppColors.muted).
/// - "BAŞARIM AÇILDI" rozeti YOK, süre/timer çubuğu YOK.
/// - Dokunulduğunda veya yukarı kaydırıldığında [onDismiss] tetiklenir.
class AchievementNotificationCard extends StatelessWidget {
  final AchievementUiItem item;
  final VoidCallback? onDismiss;
  final double? badgeDx;
  final double? badgeRotationDeg;

  const AchievementNotificationCard({
    super.key,
    required this.item,
    this.onDismiss,
    this.badgeDx,
    this.badgeRotationDeg,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBadgeDx = badgeDx ?? item.badgeDx;
    final effectiveRotationDeg = badgeRotationDeg ?? item.badgeRotationDeg;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Başarım: ${item.title}, ${item.description}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
            onDismiss?.call();
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Beyaz Kart Gövdesi
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                left: 58,
                right: 16,
                top: 12,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.ink,
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.ink,
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.2,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                      height: 1.2,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Dışarı Taşan Rozet (68x68, konumu ve eğim açısı ayarlanabilir, yumuşak gölgeli)
            Positioned(
              left: effectiveBadgeDx,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.rotate(
                  angle: effectiveRotationDeg * math.pi / 180,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.16),
                          offset: const Offset(0, 4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: SvgPicture.asset(
                      item.iconAsset,
                      width: 68,
                      height: 68,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
