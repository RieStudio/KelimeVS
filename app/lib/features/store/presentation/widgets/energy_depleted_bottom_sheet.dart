import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/secondary_button.dart';
import '../../../profile/domain/energy_state.dart';
import '../../application/store_notifier.dart';
import '../../data/store_api_client.dart';

/// DESIGN.md 9b: Enerjin Bitti Sayfası (BottomSheet)
/// Enerji 0 iken "Hızlı Maç"a basıldığında veya maç kuyruğunda enerji bittiğinde açılır.
/// - Başlık: "Enerjin bitti" (Fredoka 24/700)
/// - Canlı geri sayım: "Sonraki enerji: mm:ss"
/// - 3 buton:
///   1. "1 Enerji · 20" (ana)
///   2. "Botla Oyna" (ikincil)
///   3. "Vazgeç" (metin butonu)
class EnergyDepletedBottomSheet extends ConsumerStatefulWidget {
  final EnergyState energy;
  final int userCoins;
  final int? serverNowMs;
  final VoidCallback? onPlayWithBot;
  final VoidCallback? onEnergyPurchased;

  const EnergyDepletedBottomSheet({
    super.key,
    required this.energy,
    required this.userCoins,
    this.serverNowMs,
    this.onPlayWithBot,
    this.onEnergyPurchased,
  });

  @override
  ConsumerState<EnergyDepletedBottomSheet> createState() =>
      _EnergyDepletedBottomSheetState();
}

class _EnergyDepletedBottomSheetState
    extends ConsumerState<EnergyDepletedBottomSheet> {
  Timer? _ticker;
  late int _serverClockOffset;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _initClockOffset();
    _startTimer();
  }

  void _initClockOffset() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _serverClockOffset = (widget.serverNowMs ?? nowMs) - nowMs;
  }

  void _startTimer() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatRemainingCountdown(int? nextEnergyAtMs) {
    if (nextEnergyAtMs == null) return '';
    final estimatedServerNow =
        DateTime.now().millisecondsSinceEpoch + _serverClockOffset;
    final remainingMs = math.max(0, nextEnergyAtMs - estimatedServerNow);
    final totalSeconds = (remainingMs / 1000).ceil();

    if (totalSeconds <= 0) {
      return '00:00';
    }

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _handleBuyOneEnergy(int cost) async {
    if (_isPurchasing) return;

    if (widget.userCoins < cost) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              AppStrings.insufficientCoins,
              style: TextStyle(
                fontFamily: AppTextStyles.fontNunito,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: AppColors.ink,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    setState(() => _isPurchasing = true);
    final res = await ref
        .read(storeNotifierProvider.notifier)
        .purchaseEnergy('one');
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    if (res is StorePurchaseEnergySuccess) {
      Navigator.of(context).pop();
      widget.onEnergyPurchased?.call();
    } else if (res is StorePurchaseEnergyNotEnoughCoins) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              res.message,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontNunito,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: AppColors.ink,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packOne = widget.energy.packs.firstWhere(
      (p) => p.id == 'one',
      orElse: () => const EnergyPack(id: 'one', cost: 20, energy: 1),
    );
    final countdownStr = _formatRemainingCountdown(
      widget.energy.nextEnergyAtMs,
    );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst Çubuk: Başlık ve Kapat Butonu
            Row(
              children: [
                const Expanded(
                  child: Text(
                    AppStrings.energyDepletedTitle,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  semanticLabel: AppStrings.cancel,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: AppDimens.space12),

            // Açıklama Metni
            const Text(
              AppStrings.energyDepletedSubtitle,
              style: TextStyle(
                fontFamily: AppTextStyles.fontNunito,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),

            const SizedBox(height: AppDimens.space16),

            // Canlı Geri Sayım Kartı
            if (countdownStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space16,
                  vertical: AppDimens.space12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppDimens.borderRadiusListCard,
                  border: Border.all(
                    color: AppColors.mint,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppIcon(
                      AppIcons.bolt,
                      size: 20,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      '${AppStrings.nextEnergyPrefix}$countdownStr',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontNunito,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: AppDimens.space20),

            // Buton 1: "1 Enerji · 20"
            PrimaryButton(
              key: const Key('energy_sheet_buy_button'),
              text: '1 Enerji  ·  ${packOne.cost} Jeton',
              onPressed: _isPurchasing
                  ? null
                  : () => _handleBuyOneEnergy(packOne.cost),
            ),

            const SizedBox(height: AppDimens.space10),

            // Buton 2: "Botla Oyna"
            SecondaryButton(
              key: const Key('energy_sheet_bot_button'),
              text: AppStrings.playWithBotEnergyFree,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPlayWithBot?.call();
              },
            ),

            const SizedBox(height: AppDimens.space6),

            // Buton 3: "Vazgeç"
            Center(
              child: TextButton(
                key: const Key('energy_sheet_cancel_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  AppStrings.cancel,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.muted,
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
