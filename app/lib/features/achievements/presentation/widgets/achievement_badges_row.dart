import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_pressable.dart';
import '../../domain/achievement_ui_manifest.dart';
import '../../domain/user_achievement.dart';
import 'achievement_detail_sheet.dart';

/// Profil ve Herkese Açık Profil ekranlarında paylaşılan yatay başarım rozet satırı.
///
/// - Bilinmeyen başarım kimliklerini sessizce eler.
/// - Sabit prestij sırasına ([AchievementUiManifest.sortByPrestige]) göre sıralar.
/// - Hiç başarım yoksa [SizedBox.shrink] döner.
/// - Ekran genişliğine göre tek satırda 4 rozet sığacak şekilde ölçeklenir; 5. rozet ve
///   sonrası için yatay kaydırma ve sağ kenarda [ShaderMask] ile hafif solma uygular.
class AchievementBadgesRow extends StatefulWidget {
  final List<UserAchievement> achievements;
  final double horizontalPadding;

  const AchievementBadgesRow({
    super.key,
    required this.achievements,
    this.horizontalPadding = AppDimens.screenPaddingHorizontal,
  });

  @override
  State<AchievementBadgesRow> createState() => _AchievementBadgesRowState();
}

class _AchievementBadgesRowState extends State<AchievementBadgesRow> {
  static const double _badgeSpacing = AppDimens.space10;
  static const double _verticalPadding = AppDimens.space8;

  late final ScrollController _scrollController;
  bool _showRightFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateFadeFromController);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeFromController());
  }

  @override
  void didUpdateWidget(covariant AchievementBadgesRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.achievements != widget.achievements) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeFromController());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFadeFromController);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFadeFromController() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _updateFadeMetrics(pos.pixels, pos.maxScrollExtent);
  }

  void _updateFadeMetrics(double pixels, double maxScrollExtent) {
    final shouldShow = maxScrollExtent > 0 && pixels < maxScrollExtent - 2.0;
    if (shouldShow != _showRightFade && mounted) {
      setState(() => _showRightFade = shouldShow);
    }
  }

  double _computeBadgeSize(double maxWidth) {
    final availableWidth =
        (maxWidth - (widget.horizontalPadding * 2)).clamp(0.0, double.infinity);
    final raw = (availableWidth - (_badgeSpacing * 3)) / 4.0;
    return raw.clamp(48.0, 84.0);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = AchievementUiManifest.sortByPrestige(widget.achievements);
    if (sorted.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final badgeSize = _computeBadgeSize(constraints.maxWidth);
        final rowHeight = badgeSize + (_verticalPadding * 2);

        Widget listView = NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _updateFadeMetrics(
              notification.metrics.pixels,
              notification.metrics.maxScrollExtent,
            );
            return false;
          },
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(
              horizontal: widget.horizontalPadding,
              vertical: _verticalPadding,
            ),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(width: _badgeSpacing),
            itemBuilder: (context, index) {
              final achievement = sorted[index];
              final item = AchievementUiManifest.get(achievement.id)!;
              return _AchievementBadgeTile(
                achievement: achievement,
                item: item,
                size: badgeSize,
                onTap: () => showAchievementDetailSheet(
                  context,
                  achievement: achievement,
                  item: item,
                ),
              );
            },
          ),
        );

        if (_showRightFade) {
          listView = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.86, 1.0],
            ).createShader(bounds),
            child: listView,
          );
        }

        return SizedBox(
          height: rowHeight,
          child: listView,
        );
      },
    );
  }
}

class _AchievementBadgeTile extends StatelessWidget {
  final UserAchievement achievement;
  final AchievementUiItem item;
  final double size;
  final VoidCallback onTap;

  const _AchievementBadgeTile({
    required this.achievement,
    required this.item,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pillHeight = (size * 0.30).clamp(18.0, 24.0);
    final pillFontSize = (pillHeight * 0.52).clamp(10.0, 12.5);

    return Semantics(
      button: true,
      label: AppStrings.achievementBadgeSemantic(item.title, achievement.count),
      child: AppPressable(
        ensureMinTouchTarget: true,
        pressOffset: 0.0,
        onTap: onTap,
        builder: (context, isPressed) {
          return AnimatedScale(
            scale: isPressed ? 0.92 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: SvgPicture.asset(
                      item.iconAsset,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (achievement.count >= 2)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: pillHeight,
                          minHeight: pillHeight,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.coin,
                          borderRadius: AppDimens.borderRadiusFull,
                          border: Border.all(
                            color: AppColors.ink,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: ExcludeSemantics(
                          child: Text(
                            'x${achievement.count}',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontNunito,
                              fontSize: pillFontSize,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
