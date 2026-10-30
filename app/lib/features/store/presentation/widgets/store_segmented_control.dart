import 'package:flutter/material.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/store_item.dart';

/// DESIGN.md 9a: Mağaza Segmentli Sekme Kontrolü
///
/// Tüm içerik genişliğini kaplayan tek yuvarlatılmış dikdörtgen:
/// - Zemin: AppColors.card, Kenarlık: 2 px AppColors.ink, Köşe: AppDimens.radiusListCard (20 px)
/// - İçinde eşit genişlikte bölümler (2 veya 3 bölüm)
/// - Seçili bölüm: AppColors.primary dolgu, beyaz kalın yazı, iç köşe yarıçapı 16 px, 2 px iç boşluk
/// - Seçili olmayan bölüm: şeffaf zemin, AppColors.ink yazı
/// - Geçiş animasyonu: ~180 ms easeInOutCubic
/// - Dokunma alanı: bölümün tamamı, en az 48 dp yükseklik
class StoreSegmentedControl extends StatelessWidget {
  final List<StoreTab> availableTabs;
  final StoreTab selectedTab;
  final ValueChanged<StoreTab> onTabSelected;
  final Map<StoreTab, Key>? tabKeys;

  const StoreSegmentedControl({
    super.key,
    required this.availableTabs,
    required this.selectedTab,
    required this.onTabSelected,
    this.tabKeys,
  });

  static const double height = 48.0;
  static const double _innerPadding = 2.0;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = availableTabs.indexOf(selectedTab);
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
    final tabCount = availableTabs.length;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
      ),
      padding: const EdgeInsets.all(_innerPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segmentWidth = tabCount > 0 ? totalWidth / tabCount : 0.0;

          return Stack(
            children: [
              // 1. Kayan Seçili Gösterge (primary dolgu)
              if (tabCount > 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOutCubic,
                  left: safeIndex * segmentWidth,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusListCard - (AppDimens.borderThin + _innerPadding),
                      ),
                    ),
                  ),
                ),

              // 2. Sekme Butonları (Eşit genişlikte, tam dokunma alanı)
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < tabCount; i++) ...[
                    Expanded(
                      child: _buildTabItem(
                        context,
                        tab: availableTabs[i],
                        isSelected: availableTabs[i] == selectedTab,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context, {
    required StoreTab tab,
    required bool isSelected,
  }) {
    final label = switch (tab) {
      StoreTab.coins => AppStrings.tabCoins,
      StoreTab.energy => AppStrings.tabEnergy,
      StoreTab.frames => AppStrings.tabFrames,
    };

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        key: tabKeys?[tab] ?? ValueKey(tab),
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabSelected(tab),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.space6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isSelected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

