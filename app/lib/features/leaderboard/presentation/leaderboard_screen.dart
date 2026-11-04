import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../application/leaderboard_providers.dart';
import '../domain/models/leaderboard_models.dart';

/// DESIGN.md Bölüm 7 & GDD 5.4: Haftalık Liderlik Tablosu
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardNotifierProvider);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      key: const Key('leaderboard_screen'),
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppDimens.space12),

            // 1. Üst Çubuk: Geri butonu (yalnızca canPop ise), Başlık ve Kalan Süre Rozeti
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
              ),
              child: Row(
                children: [
                  if (canPop) ...[
                    AppIconButton(
                      key: const Key('leaderboard_back_button'),
                      icon: AppIcons.back,
                      semanticLabel: AppStrings.back,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: AppDimens.space12),
                  ],
                  const Expanded(
                    child: Text(
                      AppStrings.leaderboardTitle,
                      style: AppTextStyles.screenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Kalan Süre Rozeti (Pazartesi 00:00'a kadar)
                  leaderboardAsync.maybeWhen(
                    data: (data) => _CountdownPill(data: data),
                    orElse: () => leaderboardAsync.value != null
                        ? _CountdownPill(data: leaderboardAsync.value!)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimens.space16),

            // 2. Ana Gövde (Durumlara göre)
            Expanded(
              child: _buildBody(context, ref, leaderboardAsync),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<LeaderboardData> leaderboardAsync,
  ) {
    // 1. İlk yükleme durumları (henüz hafızada hiç veri yokken)
    if (!leaderboardAsync.hasValue) {
      if (leaderboardAsync.isLoading) {
        return const Center(
          key: Key('leaderboard_loading'),
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      if (leaderboardAsync.hasError) {
        return _ErrorView(
          onRetry: () => ref
              .read(leaderboardNotifierProvider.notifier)
              .refresh(),
        );
      }
      return const Center(
        key: Key('leaderboard_loading'),
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // 2. Veri mevcut (ilk yükleme tamamlanmış, sonraki ziyaret veya arka plan tazelemesi)
    final data = leaderboardAsync.value!;
    final syncError = ref.watch(leaderboardSyncErrorProvider);
    final hasSyncError = syncError != null;

    if (data.top.isEmpty) {
      return _EmptyView(
        onPlay: () {
          if (!ensureNetworkConnected(context, ref)) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MatchmakingScreen(),
            ),
          );
        },
      );
    }

    final isMeInTop = data.top.any((entry) => entry.isMe);
    final showStickyMe = data.me != null && !isMeInTop;

    return Stack(
      children: [
        // Kaydırılabilir Sıralama Listesi (yenileme anında liste korunur, çark gösterilmez)
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref
              .read(leaderboardNotifierProvider.notifier)
              .refresh(),
          child: ListView.separated(
            key: const Key('leaderboard_list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              left: AppDimens.screenPaddingHorizontal,
              right: AppDimens.screenPaddingHorizontal,
              top: AppDimens.space8,
              bottom: showStickyMe
                  ? 96.0
                  : AppDimens.screenPaddingHorizontal,
            ),
            itemCount: data.top.length + (hasSyncError ? 1 : 0),
            separatorBuilder: (_, index) =>
                const SizedBox(height: AppDimens.space10),
            itemBuilder: (context, index) {
              if (hasSyncError) {
                if (index == 0) {
                  return _SyncErrorBanner(
                    onRetry: () => ref
                        .read(leaderboardNotifierProvider.notifier)
                        .refresh(),
                  );
                }
                final entry = data.top[index - 1];
                return _LeaderboardItemCard(
                  key: Key('leaderboard_item_${entry.rank}'),
                  entry: entry,
                );
              }
              final entry = data.top[index];
              return _LeaderboardItemCard(
                key: Key('leaderboard_item_${entry.rank}'),
                entry: entry,
              );
            },
          ),
        ),

        // İlk 100 dışındaki oyuncu için alt yapışkan "Senin Sıran" çubuğu
        if (showStickyMe)
          Positioned(
            left: AppDimens.screenPaddingHorizontal,
            right: AppDimens.screenPaddingHorizontal,
            bottom: AppDimens.space12,
            child: _StickyMeBar(me: data.me!),
          ),
      ],
    );
  }
}

/// Arka plan tazeleme başarısız olduğunda listenin üstünde beliren küçük uyarı şeridi
class _SyncErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _SyncErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('leaderboard_sync_error_banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space8,
      ),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.dangerSoft,
          width: AppDimens.borderThin,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.dangerText,
          ),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              AppStrings.leaderboardError,
              style: AppTextStyles.secondaryText.copyWith(
                color: AppColors.dangerText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              AppStrings.retry,
              style: AppTextStyles.secondaryText.copyWith(
                color: AppColors.dangerText,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kalan süreyi gösteren rozet (Pazartesi 00:00 Europe/Istanbul)
class _CountdownPill extends StatefulWidget {
  final LeaderboardData data;

  const _CountdownPill({required this.data});

  @override
  State<_CountdownPill> createState() => _CountdownPillState();
}

class _CountdownPillState extends State<_CountdownPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // TickerMode kapalıysa (sekme görünür değilken) gereksiz yeniden çizim yapma
      if (!TickerMode.valuesOf(context).enabled) return;
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted && TickerMode.valuesOf(context).enabled) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant _CountdownPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.endsAt != widget.data.endsAt) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingText = widget.data.formatRemainingTime();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.radiusNavPill),
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(
            AppIcons.leaderboard,
            size: 16,
            color: AppColors.muted,
          ),
          const SizedBox(width: AppDimens.space4),
          Text(
            remainingText,
            style: AppTextStyles.secondaryText.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sıralama ekranı kartları (satırlar, yapışkan çubuk ve durum kartları) için ortak kart dekorasyonu.
BoxDecoration _buildCardDecoration({
  Color color = AppColors.card,
  Color borderColor = AppColors.ink,
  bool isThickBorder = false,
  double? borderWidth,
}) {
  return EmptyStateCard.buildDecoration(
    color: color,
    borderColor: borderColor,
    borderWidth: borderWidth ??
        (isThickBorder ? AppDimens.borderThick : AppDimens.borderThin),
  );
}

/// Liderlik tablosundaki her bir oyuncu kartı
class _LeaderboardItemCard extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderboardItemCard({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = entry.isMe;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space12,
      ),
      decoration: _buildCardDecoration(
        color: isMe ? AppColors.selfHighlight : AppColors.card,
        isThickBorder: isMe,
      ),
      child: Row(
        children: [
          // Sıra Rozeti (İlk 3 özel rozetli)
          _RankBadge(
            rank: entry.rank,
            isMe: isMe,
          ),

          const SizedBox(width: AppDimens.space10),

          // Oyuncu Avatarı
          isMe
              ? PlayerAvatar.selfHome(
                  name: entry.nickname,
                  frame: entry.frame,
                  size: AppDimens.avatarMatch,
                  borderWidth: AppDimens.borderThin,
                )
              : PlayerAvatar.opponent(
                  name: entry.nickname,
                  frame: entry.frame,
                  size: AppDimens.avatarMatch,
                  borderWidth: AppDimens.borderThin,
                ),

          const SizedBox(width: AppDimens.space10),

          // Takma Ad (SEN rozeti kaldırıldı, kart zemini vurgu rengindedir)
          Expanded(
            child: Text(
              entry.nickname,
              style: AppTextStyles.playerName.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: AppDimens.space8),

          // Galibiyet Sayısı (Dar ekranda ve büyük yazı tipi ölçeğinde taşmaz)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${entry.wins}${AppStrings.winsSuffix}',
                style: AppTextStyles.bodyText.copyWith(
                  color: isMe ? AppColors.ink : AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 sivri uçlu, bilyeli, taban şeritli ve mücevher detaylı vektör taç çizen CustomPainter
class _CrownPainter extends CustomPainter {
  final Color color;

  const _CrownPainter({this.color = AppColors.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Taban şeridi
    final baseRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.12, h * 0.78, w * 0.88, h * 0.94),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(baseRect, fillPaint);
    canvas.drawRRect(baseRect, strokePaint);

    // 3 sivri uçlu taç poligonu
    final path = Path()
      ..moveTo(w * 0.16, h * 0.78)
      ..lineTo(w * 0.14, h * 0.32)
      ..lineTo(w * 0.34, h * 0.54)
      ..lineTo(w * 0.50, h * 0.18)
      ..lineTo(w * 0.66, h * 0.54)
      ..lineTo(w * 0.86, h * 0.32)
      ..lineTo(w * 0.84, h * 0.78)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    // 3 sivri ucun tepesindeki küçük toplar (bilye uçları)
    canvas.drawCircle(Offset(w * 0.14, h * 0.28), w * 0.075, fillPaint);
    canvas.drawCircle(Offset(w * 0.50, h * 0.13), w * 0.090, fillPaint);
    canvas.drawCircle(Offset(w * 0.86, h * 0.28), w * 0.075, fillPaint);

    // Taban şeridi üzerindeki 3 küçük mücevher noktası (ortadaki biraz daha büyük)
    final gemPaint = Paint()
      ..color = AppColors.card
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(w * 0.50, h * 0.86), 1.3, gemPaint);
    canvas.drawCircle(Offset(w * 0.28, h * 0.86), 0.95, gemPaint);
    canvas.drawCircle(Offset(w * 0.72, h * 0.86), 0.95, gemPaint);

    // Üst yüzeyde hafif açık bir parlama çizgisi (gleam)
    final gleamPaint = Paint()
      ..color = AppColors.card.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final gleamPath = Path()
      ..moveTo(w * 0.22, h * 0.44)
      ..lineTo(w * 0.34, h * 0.53)
      ..lineTo(w * 0.48, h * 0.22);
    canvas.drawPath(gleamPath, gleamPaint);
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 1., 2., 3. ve diğer sıralar için rozet
class _RankBadge extends StatelessWidget {
  final int rank;
  final bool isMe;

  const _RankBadge({
    required this.rank,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    if (rank <= 3) {
      Color bgColor;
      Widget content;

      switch (rank) {
        case 1:
          bgColor = AppColors.rankGold;
          content = const CustomPaint(
            size: Size(20, 16),
            painter: _CrownPainter(color: AppColors.ink),
          );
          break;
        case 2:
          bgColor = AppColors.rankSilver;
          content = Text(
            '2',
            style: AppTextStyles.playerName.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          );
          break;
        case 3:
        default:
          bgColor = AppColors.rankBronze;
          content = Text(
            '3',
            style: AppTextStyles.playerName.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          );
          break;
      }

      return SizedBox(
        width: 40,
        child: Center(
          child: Semantics(
            label: '$rank. sıra',
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      );
    }

    // Kullanıcının kendi kartı ilk 100 içinde ve 3. sıradan sonraysa (#12 gibi)
    // turuncu zeminde öne çıkan beyaz hap rozet kullanılır
    if (isMe) {
      return SizedBox(
        width: 40,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space4,
            vertical: AppDimens.space4,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusBadge,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThin,
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '#$rank',
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.playerName.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 40,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          '#$rank',
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          style: AppTextStyles.secondaryText.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// İlk 100 dışındaki oyuncunun sırasını gösteren yapışkan çubuk (satır kartlarıyla aynı düzende)
class _StickyMeBar extends ConsumerWidget {
  final LeaderboardMe me;

  const _StickyMeBar({
    required this.me,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final myNickname = (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : AppStrings.defaultPlayerName;
    final myFrame = profile.equippedFrame;

    return Container(
      key: const Key('leaderboard_sticky_me'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space12,
      ),
      decoration: _buildCardDecoration(
        color: AppColors.selfHighlight,
        isThickBorder: true,
      ),
      child: Row(
        children: [
          // Solda Sıra Rozeti (3 haneyi taşırmadan rozet/hap içinde)
          SizedBox(
            width: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space4,
                vertical: AppDimens.space4,
              ),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusBadge,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '#${me.rank}',
                  maxLines: 1,
                  softWrap: false,
                  style: AppTextStyles.playerName.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: AppDimens.space10),

          // Ortada Kullanıcının Kendi Avatarı
          PlayerAvatar.selfHome(
            name: myNickname,
            frame: myFrame,
            size: AppDimens.avatarMatch,
            borderWidth: AppDimens.borderThin,
          ),

          const SizedBox(width: AppDimens.space10),

          // Ortada Takma Ad
          Expanded(
            child: Text(
              myNickname,
              style: AppTextStyles.playerName.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: AppDimens.space8),

          // Sağda Galibiyet Sayısı
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${me.wins}${AppStrings.winsSuffix}',
                style: AppTextStyles.bodyText.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş liste görünümü ("Bu hafta henüz maç yok")
class _EmptyView extends StatelessWidget {
  final VoidCallback onPlay;

  const _EmptyView({required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('leaderboard_empty'),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
        child: EmptyStateCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(
                AppIcons.trophy,
                size: 64,
                color: AppColors.coin,
              ),
              const SizedBox(height: AppDimens.space16),
              const Text(
                AppStrings.emptyLeaderboard,
                style: AppTextStyles.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space8),
              const Text(
                AppStrings.emptyLeaderboardSubtitle,
                style: AppTextStyles.bodyText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space20),
              PrimaryButton(
                text: AppStrings.quickMatch,
                onPressed: onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hata durumu görünümü (yalnızca ilk yüklemede veri yokken)
class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('leaderboard_error'),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.space24),
          decoration: _buildCardDecoration(
            borderColor: AppColors.dangerSoft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStrings.leaderboardError,
                style: AppTextStyles.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space8),
              const Text(
                AppStrings.networkError,
                style: AppTextStyles.bodyText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space20),
              SecondaryButton(
                text: AppStrings.retry,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}