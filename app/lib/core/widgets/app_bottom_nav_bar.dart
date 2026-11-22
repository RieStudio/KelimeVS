import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

class AppNavItem {
  final String svgAsset;
  final String label;

  const AppNavItem({
    required this.svgAsset,
    required this.label,
  });

  /// Alias for backward compatibility or convenience.
  String get iconAsset => svgAsset;
}

/// DESIGN.md Bölüm 6: Alt Gezinme Çubuğu
/// Beyaz, üstte 2 px mint çizgi, yükseklik 76 (+ güvenli alan).
/// 4 öğe: Ana Sayfa, Sıralama, Mağaza, Profil.
/// Etkin öğe mint zeminli yuvarlak dikdörtgen (köşe 16), renkli SVG + Nunito 12/800 etiket.
/// Seçili olmayan öğe: grayscale matrisli ColorFiltered + %55 solukluk.
class AppBottomNavBar extends StatelessWidget {
  static const String homeAsset = 'assets/icons/nav_home.svg';
  static const String leaderboardAsset = 'assets/icons/nav_leaderboard.svg';
  static const String storeAsset = 'assets/icons/nav_store.svg';
  static const String profileAsset = 'assets/icons/nav_profile.svg';

  static const double iconSize = 32.0;
  static const double unselectedOpacity = 0.55;

  /// Seçili olmayan sekmeler için ITU-R BT.709 luminance matrisi
  static const List<double> grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ];

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

              Widget iconWidget = SvgPicture.asset(
                item.svgAsset,
                width: iconSize,
                height: iconSize,
              );

              if (!isSelected) {
                iconWidget = Opacity(
                  opacity: unselectedOpacity,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(grayscaleMatrix),
                    child: iconWidget,
                  ),
                );
              }

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
                              iconWidget,
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

