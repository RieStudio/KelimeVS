import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// DESIGN.md ile tam uyumlu maç isteği geri bildirim tostu (toast).
class MatchRequestToastWidget extends StatelessWidget {
  final String message;
  final bool isDanger;
  final VoidCallback? onDismiss;

  const MatchRequestToastWidget({
    super.key,
    required this.message,
    this.isDanger = false,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.card;
    final borderColor = isDanger ? AppColors.danger : AppColors.ink;
    final textColor = isDanger ? AppColors.dangerText : AppColors.ink;
    final iconColor = isDanger ? AppColors.dangerText : AppColors.ink;

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
              Icon(
                isDanger
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 18,
                color: iconColor,
              ),
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
