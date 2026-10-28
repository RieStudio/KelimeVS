import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/network/network_guard.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/domain/energy_state.dart';
import '../../application/store_notifier.dart';
import '../../data/store_api_client.dart';

/// DESIGN.md 9a: Enerji Sekmesi Görünümü
/// - Üstte 5 hücreli enerji kartı ve canlı mm:ss geri sayımı
/// - Altta jetonla enerji paketleri (+1 Enerji, Tam Doldur)
class EnergyTabView extends ConsumerStatefulWidget {
  final EnergyState energy;
  final int userCoins;
  final int? serverNowMs;

  const EnergyTabView({
    super.key,
    required this.energy,
    required this.userCoins,
    this.serverNowMs,
  });

  @override
  ConsumerState<EnergyTabView> createState() => _EnergyTabViewState();
}

class _EnergyTabViewState extends ConsumerState<EnergyTabView> {
  Timer? _ticker;
  late int _serverClockOffset;

  @override
  void initState() {
    super.initState();
    _initClockOffset();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant EnergyTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.serverNowMs != oldWidget.serverNowMs) {
      _initClockOffset();
    }
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
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

  Future<void> _handlePurchase(String packId, int cost) async {
    if (widget.energy.isFull) {
      _showSnackBar(AppStrings.energyAlreadyFull);
      return;
    }
    if (widget.userCoins < cost) {
      _showSnackBar(AppStrings.insufficientCoins);
      return;
    }

    if (!ensureNetworkConnected(context, ref)) return;

    final res = await ref
        .read(storeNotifierProvider.notifier)
        .purchaseEnergy(packId);

    if (!mounted) return;
    if (res is StorePurchaseEnergySuccess) {
      _showSnackBar(AppStrings.energyPackPurchased);
    } else if (res is StorePurchaseEnergyNotEnoughCoins) {
      _showSnackBar(res.message);
    } else if (res is StorePurchaseEnergyFull) {
      _showSnackBar(res.message);
    } else if (res is StorePurchaseEnergyDisabled) {
      _showSnackBar(res.message);
    } else if (res is StorePurchaseEnergyNetworkError) {
      _showSnackBar(res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.energy.current;
    final max = widget.energy.max;
    final isFull = widget.energy.isFull;
    final countdownStr = _formatRemainingCountdown(
      widget.energy.nextEnergyAtMs,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Büyük Enerji Kartı
          Container(
            padding: const EdgeInsets.all(AppDimens.space20),
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
                  offset: Offset(0, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Column(
              children: [
                // 5 Hücreli Yıldırım Göstergesi
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(max, (index) {
                    final isFilled = index < current;
                    return Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isFilled ? AppColors.coin : AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isFilled ? AppColors.ink : AppColors.mint,
                          width: isFilled
                              ? AppDimens.borderThin
                              : AppDimens.borderThick,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        AppIcons.bolt,
                        size: 20,
                        color: isFilled ? AppColors.ink : AppColors.mint,
                      ),
                    );
                  }),
                ),

                const SizedBox(height: AppDimens.space16),

                // "3 / 5" Metni
                Text(
                  '$current / $max',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                    color: AppColors.ink,
                    height: 1.0,
                  ),
                ),

                const SizedBox(height: AppDimens.space8),

                // Canlı Geri Sayım veya "Tüm enerjin doldu"
                if (isFull)
                  Text(
                    AppStrings.energyFull,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.primary,
                    ),
                  )
                else ...[
                  Text(
                    '${AppStrings.nextEnergyPrefix}$countdownStr',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),

                  const SizedBox(height: AppDimens.space4),

                  Text(
                    AppStrings.energyRegenInfo,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppDimens.space24),

          // 2. Enerji Paketleri Bölüm Başlığı
          const Text(
            'ENERJİ PAKETLERİ',
            style: TextStyle(
              fontFamily: AppTextStyles.fontNunito,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),

          const SizedBox(height: AppDimens.space12),

          // Paket Kartları
          ...widget.energy.packs.map((pack) {
            final isPackFullType = pack.id == 'full';
            final title = isPackFullType
                ? AppStrings.energyPackFullTitle
                : AppStrings.energyPackOneTitle;
            final desc = isPackFullType
                ? AppStrings.energyPackFullDesc
                : AppStrings.energyPackOneDesc;
            final canAfford = widget.userCoins >= pack.cost;

            return _buildEnergyPackCard(
              pack: pack,
              title: title,
              desc: desc,
              isFull: isFull,
              canAfford: canAfford,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEnergyPackCard({
    required EnergyPack pack,
    required String title,
    required String desc,
    required bool isFull,
    required bool canAfford,
  }) {
    final isDisabled = isFull || !canAfford;

    return Container(
      margin: const EdgeInsets.only(bottom: AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(color: AppColors.ink, width: AppDimens.borderThin),
      ),
      child: Row(
        children: [
          // Yıldırım İkonu Dairesi
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isFull ? AppColors.mint : AppColors.coin,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            alignment: Alignment.center,
            child: const AppIcon(AppIcons.bolt, size: 24, color: AppColors.ink),
          ),

          const SizedBox(width: AppDimens.space12),

          // Paket Bilgisi
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppDimens.space8),

          // Fiyat Butonu / Dolu Durumu
          GestureDetector(
            key: ValueKey('buy_energy_pack_${pack.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _handlePurchase(pack.id, pack.cost),
            child: Opacity(
              opacity: isDisabled ? 0.6 : 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space8,
                ),
                decoration: BoxDecoration(
                  color: isFull
                      ? AppColors.surface
                      : (canAfford ? AppColors.coin : AppColors.card),
                  borderRadius: AppDimens.borderRadiusFull,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                  boxShadow: isFull || !canAfford
                      ? null
                      : const [
                          BoxShadow(
                            color: AppColors.ink,
                            offset: Offset(0, 2),
                            blurRadius: 0,
                          ),
                        ],
                ),
                child: isFull
                    ? Text(
                        AppStrings.energyFullButton,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontNunito,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.card,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'G',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFredoka,
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${pack.cost}',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFredoka,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
