import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/match_request_models.dart';

/// Toast içinde gösterilecek SVG ikon yapılandırması.
class MatchRequestToastIconConfig {
  final String assetPath;
  final Color color;

  const MatchRequestToastIconConfig({
    required this.assetPath,
    required this.color,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRequestToastIconConfig &&
          runtimeType == other.runtimeType &&
          assetPath == other.assetPath &&
          color == other.color;

  @override
  int get hashCode => assetPath.hashCode ^ color.hashCode;
}

/// Hata kodu veya durum anahtarına göre toast ikonu ve rengini döndüren saf fonksiyon.
///
/// Eşlemesi olmayan durumlar için `null` döner; bu durumda widget varsayılan
/// Material simgesine geri düşer.
MatchRequestToastIconConfig? matchRequestToastIconForCode(String code) {
  switch (code) {
    case 'declined':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_declined.svg',
        color: AppColors.danger,
      );
    case 'cooldown_active':
    case 'cooldownActive':
    case 'rate_limited':
    case 'rateLimited':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_cooldown.svg',
        color: AppColors.ink,
      );
    case 'offline':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_offline.svg',
        color: AppColors.danger,
      );
    case 'requests_disabled':
    case 'requestsDisabled':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_disabled.svg',
        color: AppColors.danger,
      );
    case 'unavailable':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_busy.svg',
        color: AppColors.ink,
      );
    case 'no_energy':
    case 'noEnergy':
    case 'opponent_no_energy':
    case 'opponentNoEnergy':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_no_energy.svg',
        color: AppColors.danger,
      );
    case 'accepted':
    case 'match_accepted':
    case 'match_started':
      return const MatchRequestToastIconConfig(
        assetPath: 'assets/icons/match_request_accepted.svg',
        color: AppColors.bright,
      );
    default:
      return null;
  }
}

/// [MatchRequestErrorCode] için ikon yapılandırması.
MatchRequestToastIconConfig? matchRequestToastIconForError(
  MatchRequestErrorCode code,
) {
  return matchRequestToastIconForCode(code.toWireString());
}

/// [MatchRequestEndStatus] için ikon yapılandırması.
MatchRequestToastIconConfig? matchRequestToastIconForEndStatus(
  MatchRequestEndStatus status,
) {
  return matchRequestToastIconForCode(status.name);
}

/// DESIGN.md ile tam uyumlu maç isteği geri bildirim tostu (toast).
class MatchRequestToastWidget extends StatelessWidget {
  final String message;
  final bool isDanger;
  final VoidCallback? onDismiss;
  final String? iconAsset;
  final Color? iconColor;

  const MatchRequestToastWidget({
    super.key,
    required this.message,
    this.isDanger = false,
    this.onDismiss,
    this.iconAsset,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.card;
    final borderColor = isDanger ? AppColors.danger : AppColors.ink;
    final textColor = isDanger ? AppColors.dangerText : AppColors.ink;
    final defaultIconColor = isDanger ? AppColors.dangerText : AppColors.ink;
    final resolvedIconColor = iconColor ?? defaultIconColor;

    final Widget iconWidget = iconAsset != null
        ? SvgPicture.asset(
            iconAsset!,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              resolvedIconColor,
              BlendMode.srcIn,
            ),
          )
        : Icon(
            isDanger
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: resolvedIconColor,
          );

    return Semantics(
      liveRegion: true,
      label: message,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(0, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontSize: 13,
                    fontWeight: isDanger ? FontWeight.w800 : FontWeight.w700,
                    color: textColor,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
