import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/match_request_models.dart';

/// DESIGN.md ile uyumlu giden maç isteği kompakt bilgi çipi.
///
/// Üstte kompakt hap/çip:
/// - `<Ad>` yanıtı bekleniyor · NN sn
/// - "İptal" butonu
class OutgoingMatchRequestChip extends StatefulWidget {
  final OutgoingMatchRequest request;
  final VoidCallback onCancel;

  const OutgoingMatchRequestChip({
    super.key,
    required this.request,
    required this.onCancel,
  });

  @override
  State<OutgoingMatchRequestChip> createState() =>
      _OutgoingMatchRequestChipState();
}

class _OutgoingMatchRequestChipState extends State<OutgoingMatchRequestChip> {
  Timer? _ticker;
  late int _remainingSec;

  @override
  void initState() {
    super.initState();
    _remainingSec = widget.request.calculateRemainingSeconds();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        final sec = widget.request.calculateRemainingSeconds();
        if (sec != _remainingSec) {
          setState(() {
            _remainingSec = sec;
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant OutgoingMatchRequestChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id) {
      _remainingSec = widget.request.calculateRemainingSeconds();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings.matchRequestOutgoingChip(
      widget.request.toNickname,
      _remainingSec,
    );

    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.ink,
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
            const Icon(
              Icons.hourglass_top_rounded,
              size: 16,
              color: AppColors.ink,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  decoration: TextDecoration.none,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: AppStrings.matchRequestCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.danger,
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    AppStrings.matchRequestCancel,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dangerText,
                      decoration: TextDecoration.none,
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
