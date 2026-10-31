import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/coin_pill.dart';
import '../../../core/widgets/section_label.dart';
import '../../profile/application/profile_notifier.dart';
import '../application/store_notifier.dart';
import '../data/store_api_client.dart';
import '../domain/models/store_item.dart';
import 'widgets/coins_tab_view.dart';
import 'widgets/energy_tab_view.dart';
import 'widgets/purchase_bottom_sheet.dart';
import 'widgets/store_frame_card.dart';
import 'widgets/store_segmented_control.dart';

/// DESIGN.md Bölüm 7: 9) Mağaza Ekranı & 9a) Mağaza Sekmeleri
///
/// Üst çubukta başlık ("Mağaza") ve sağda CoinPill.
/// Altında segmentli kontrol: **Jeton · Enerji · Çerçeve**.
/// (Enerji kapalıyken Enerji sekmesi gösterilmez; varsayılan açılış Çerçeve sekmesidir).
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  final Map<StoreTab, GlobalKey> _tabKeys = {
    StoreTab.coins: GlobalKey(),
    StoreTab.energy: GlobalKey(),
    StoreTab.frames: GlobalKey(),
  };

  void _showSnackBar(BuildContext context, String message) {
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

  void _handleEquipResult(BuildContext context, StoreEquipResult? res) {
    if (!context.mounted || res == null) return;
    if (res is StoreEquipSuccess) {
      HapticFeedback.lightImpact();
      _showSnackBar(context, AppStrings.frameEquippedSuccess);
    } else if (res is StoreEquipNotOwned) {
      _showSnackBar(context, res.message);
    } else if (res is StoreEquipInvalidFrame) {
      _showSnackBar(context, res.message);
    } else if (res is StoreEquipNetworkError) {
      _showSnackBar(context, res.message);
    } else if (res is! StoreEquipAccountDeleted) {
      _showSnackBar(context, AppStrings.storeGenericError);
    }
  }

  void _openPurchaseSheet(
    BuildContext context,
    WidgetRef ref,
    StoreItem item,
    int userCoins,
    String playerName,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PurchaseBottomSheet(
        item: item,
        userCoins: userCoins,
        playerName: playerName,
        onBuy: () async {
          if (!ensureNetworkConnected(context, ref)) return;
          final res = await ref
              .read(storeNotifierProvider.notifier)
              .purchase(item.id);
          if (res is StorePurchaseSuccess) {
            HapticFeedback.lightImpact();
            if (context.mounted) {
              _showSnackBar(context, AppStrings.framePurchasedSuccess);
            }
          } else if (res is StorePurchaseNotEnoughCoins) {
            if (context.mounted) {
              _showSnackBar(context, res.message);
            }
          } else if (res is StorePurchaseAlreadyOwned) {
            if (context.mounted) {
              _showSnackBar(context, res.message);
            }
          } else if (res is StorePurchaseUnsupportedVersion) {
            if (context.mounted) {
              _showSnackBar(context, res.message);
            }
          } else if (res != null) {
            if (context.mounted) {
              _showSnackBar(context, AppStrings.storeGenericError);
            }
          }
        },
        onEquip: () async {
          if (!ensureNetworkConnected(context, ref)) return;
          final res = await ref
              .read(storeNotifierProvider.notifier)
              .equip(item.id);
          if (context.mounted) {
            _handleEquipResult(context, res);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(storeNotifierProvider);
    final profile = ref.watch(profileProvider);
    final playerName =
        (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : 'S';

    final isEnergyEnabled = storeState.energy?.enabled ?? false;

    // DESIGN.md 9a: Enerji kapalıyken sekme hiç gösterilmez
    final availableTabs = [
      StoreTab.coins,
      if (isEnergyEnabled) StoreTab.energy,
      StoreTab.frames,
    ];

    // Eğer seçili sekme mevcut sekmelerde yoksa (örn. enerji kapandıysa) Çerçeve'ye al
    final effectiveTab = availableTabs.contains(storeState.selectedTab)
        ? storeState.selectedTab
        : StoreTab.frames;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.card,
          onRefresh: () => ref.read(storeNotifierProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Üst Çubuk: Başlık ve CoinPill
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.screenPaddingHorizontal,
                  vertical: AppDimens.space12,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          AppStrings.storeTitle,
                          style: AppTextStyles.screenTitle,
                        ),
                      ),
                      const Spacer(),
                      CoinPill(amount: storeState.coins),
                    ],
                  ),
                ),
              ),

              // 2. Segmentli Sekme Kontrolü: Jeton · Enerji · Çerçeve
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.screenPaddingHorizontal,
                ),
                sliver: SliverToBoxAdapter(
                  child: StoreSegmentedControl(
                    availableTabs: availableTabs,
                    selectedTab: effectiveTab,
                    onTabSelected: (tab) {
                      ref.read(storeNotifierProvider.notifier).setTab(tab);
                    },
                    tabKeys: _tabKeys,
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimens.space16),
              ),

              // 3. Sekme İçeriği
              if (effectiveTab == StoreTab.coins)
                const SliverToBoxAdapter(child: CoinsTabView())
              else if (effectiveTab == StoreTab.energy && isEnergyEnabled)
                SliverToBoxAdapter(
                  child: EnergyTabView(
                    energy: storeState.energy!,
                    userCoins: storeState.coins,
                    serverNowMs: storeState.serverNowMs,
                  ),
                )
              else ...[
                // Çerçeve Sekmesi
                const SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppDimens.screenPaddingHorizontal,
                    vertical: AppDimens.space6,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SectionLabel(AppStrings.avatarFramesSection),
                  ),
                ),

                if (storeState.isLoading && storeState.items.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.ink,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                      vertical: AppDimens.space12,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppDimens.space12,
                            crossAxisSpacing: AppDimens.space12,
                            childAspectRatio: 0.72,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = storeState.items[index];
                        final isItemLoading =
                            storeState.actionInProgressItemId == item.id;

                        return StoreFrameCard(
                          key: ValueKey('store_frame_${item.id}'),
                          item: item,
                          userCoins: storeState.coins,
                          playerName: playerName,
                          isLoading: isItemLoading,
                          onPreview: () => _openPurchaseSheet(
                            context,
                            ref,
                            item,
                            storeState.coins,
                            playerName,
                          ),
                          onEquip: () async {
                            if (!ensureNetworkConnected(context, ref)) return;
                            final res = await ref
                                .read(storeNotifierProvider.notifier)
                                .equip(item.id);
                            if (context.mounted) {
                              _handleEquipResult(context, res);
                            }
                          },
                          onBuy: () {
                            if (storeState.coins < item.price) {
                              _showSnackBar(
                                context,
                                AppStrings.insufficientCoins,
                              );
                              return;
                            }
                            _openPurchaseSheet(
                              context,
                              ref,
                              item,
                              storeState.coins,
                              playerName,
                            );
                          },
                        );
                      }, childCount: storeState.items.length),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
