import 'package:flutter/material.dart';
import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

class AppNavItem {
  final AppIconData icon;
  final String label;

  const AppNavItem({
    required this.icon,
    required this.label,
  });
}

/// DESIGN.md Bölüm 6: Alt Gezinme Çubuğu
/// Beyaz, üstte 2 px mint çizgi, yükseklik 76 (+ güvenli alan).
/// 4 öğe: Ana Sayfa, Sıralama, Mağaza, Profil.
/// Etkin öğe mint zeminli yuvarlak dikdörtgen (köşe 16), ikon + Nunito 12/800 etiket.
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(
            color: AppColors.mint,
            width: AppDimens.borderThin,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppDimens.bottomNavHeight,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: item.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(index),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: AppDimens.minTouchTarget,
                        minHeight: AppDimens.minTouchTarget,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          padding: isSelected
                              ? const EdgeInsets.symmetric(
                                  horizontal: AppDimens.space14,
                                  vertical: AppDimens.space8,
                                )
                              : const EdgeInsets.symmetric(
                                  horizontal: AppDimens.space8,
                                  vertical: AppDimens.space8,
                                ),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.mint : Colors.transparent,
                            borderRadius: AppDimens.borderRadiusNavPill,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppIcon(
                                item.icon,
                                size: 24,
                                color: AppColors.ink,
                              ),
                              const SizedBox(height: AppDimens.space4),
                              Text(
                                item.label,
                                style: AppTextStyles.navLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

