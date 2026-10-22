import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// DESIGN.md Bölüm 7: 9) Mağaza Ekranı & 9a) Mağaza Sekmeleri
///
/// Üst çubukta başlık ("Mağaza") ve sağda CoinPill.
/// Altında sekme şeridi: **Jeton · Enerji · Çerçeve**.
/// (Enerji kapalıyken Enerji sekmesi gösterilmez; varsayılan açılış Çerçeve sekmesidir).
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  final ScrollController _tabsScrollController = ScrollController();
  final Map<StoreTab, GlobalKey> _tabKeys = {
    StoreTab.coins: GlobalKey(),
    StoreTab.energy: GlobalKey(),
    StoreTab.frames: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedTab();
    });
  }

  void _scrollToSelectedTab() {
    final currentTab = ref.read(storeNotifierProvider).selectedTab;
    final key = _tabKeys[currentTab];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
  }

  @override
  void dispose() {
    _tabsScrollController.dispose();
    super.dispose();
  }

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
          } else if (res != null) {
            if (context.mounted) {
              _showSnackBar(context, AppStrings.storeGenericError);
            }
          }
        },
        onEquip: () async {
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

              // 2. Yatay Sekme Şeridi: Jeton · Enerji · Çerçeve
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    controller: _tabsScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                    ),
                    itemCount: availableTabs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppDimens.space8),
                    itemBuilder: (context, index) {
                      final tab = availableTabs[index];
                      final isSelected = tab == effectiveTab;
                      final label = switch (tab) {
                        StoreTab.coins => AppStrings.tabCoins,
                        StoreTab.energy => AppStrings.tabEnergy,
                        StoreTab.frames => AppStrings.tabFrames,
                      };

                      return GestureDetector(
                        key: _tabKeys[tab],
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          ref.read(storeNotifierProvider.notifier).setTab(tab);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToSelectedTab();
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.space16,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.ink,
                              width: AppDimens.borderThin,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontNunito,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: isSelected ? Colors.white : AppColors.ink,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimens.space12),
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
                            childAspectRatio: 0.82,
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
