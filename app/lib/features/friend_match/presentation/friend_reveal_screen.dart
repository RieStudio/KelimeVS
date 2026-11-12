import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_status_provider.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/avatar_frame_registry.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/presentation/match_screen.dart';
import '../../profile/application/profile_notifier.dart';

/// Arkadaş düellosunda ilk tur başlamadan önce gösterilen eşleşme ekranı.
///
/// Host ve Join her iki taraf da "matched" yanıtını aldığında bu ekrana geçer.
/// 3.5 saniye boyunca rakibin avatarı, adı ve dolan ilerleme çubuğu gösterilir;
/// süre dolunca [MatchScreen]'e geçilir ve [OnlineMatchSession.startOnlineMatch]
/// tam bu geçiş anında tetiklenir.
class FriendMatchRevealScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String opponentName;
  final String opponentFrame;
  final String? opponentUid;
  final bool isHost;
  final Duration? revealDuration;

  const FriendMatchRevealScreen({
    super.key,
    required this.matchId,
    required this.opponentName,
    this.opponentFrame = 'classic',
    this.opponentUid,
    this.isHost = true,
    this.revealDuration,
  });

  @override
  ConsumerState<FriendMatchRevealScreen> createState() =>
      _FriendMatchRevealScreenState();
}

class _FriendMatchRevealScreenState
    extends ConsumerState<FriendMatchRevealScreen> with WidgetsBindingObserver {
  late final BannerSuppressionNotifier _suppressionNotifier;
  late final DateTime _startTime;
  Timer? _revealTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _suppressionNotifier = ref.read(bannerSuppressionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressionNotifier.suppress();
      }
    });

    _startTime = DateTime.now();
    _revealTimer = Timer(
      widget.revealDuration ?? AppDimens.matchmakingRevealDuration,
      _navigateToMatch,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasNavigated) {
      final elapsed = DateTime.now().difference(_startTime);
      final total =
          widget.revealDuration ?? AppDimens.matchmakingRevealDuration;
      if (elapsed >= total) {
        _navigateToMatch();
      }
    }
  }

  void _navigateToMatch() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _revealTimer?.cancel();
    _revealTimer = null;

    ref
        .read(activeMatchSessionModeProvider.notifier)
        .setMode(MatchSessionMode.online);

    final safeOpponent = AppStrings.safeOpponentName(widget.opponentName);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const MatchScreen(),
      ),
    );

    unawaited(
      ref.read(onlineMatchSessionProvider.notifier).startOnlineMatch(
            matchId: widget.matchId,
            opponentName: safeOpponent,
            opponentUid: widget.opponentUid,
            opponentFrame: widget.opponentFrame,
            isFriendly: true,
          ),
    );
  }

  @override
  void dispose() {
    _suppressionNotifier.unsuppress();
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _revealTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final myNickname = profile.nickname?.trim();
    final myInitial =
        (myNickname != null && myNickname.isNotEmpty) ? myNickname : 'S';
    final selfFrame = profile.equippedFrame;

    final safeOpponentName = AppStrings.safeOpponentName(widget.opponentName);
    final opponentFrame = widget.opponentFrame;

    const avatarSize = AppDimens.avatarSearch;
    final avatarSlotSize = VisualFrameRegistry.maxFrameSizeFor(avatarSize);
    final avatarBottomInSlot = (avatarSlotSize + avatarSize) / 2.0;

    final selfOverflow = VisualFrameRegistry.getFrameOverflow(
      avatarSize: avatarSize,
      frameId: selfFrame,
    );
    final oppOverflow = VisualFrameRegistry.getFrameOverflow(
      avatarSize: avatarSize,
      frameId: opponentFrame,
    );
    final maxOverflow = math.max(selfOverflow, oppOverflow);
    final nameTopOffset =
        avatarBottomInSlot + maxOverflow + AppDimens.matchmakingNameGap;

    final duration =
        widget.revealDuration ?? AppDimens.matchmakingRevealDuration;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.screenPaddingHorizontal,
                        vertical: AppDimens.space12,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: AppDimens.space16),

                          // Üst Başlık: "Düello başlıyor!"
                          Semantics(
                            header: true,
                            child: const Text(
                              AppStrings.duelStarting,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFredoka,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const Spacer(),

                          // Ortadaki Avatarlar + VS Grubu
                          RepaintBoundary(
                            key: const ValueKey('friend_reveal_avatars_group'),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Sol: Sen
                                  SizedBox(
                                    width: avatarSlotSize,
                                    height: AppDimens
                                        .matchmakingAvatarSlotHeight,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.topCenter,
                                      children: [
                                        SizedBox(
                                          width: avatarSlotSize,
                                          height: avatarSlotSize,
                                          child: Center(
                                            child: PlayerAvatar.selfMatch(
                                              name: myInitial,
                                              frame: selfFrame,
                                              size: avatarSize,
                                              includeFramePadding: true,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: nameTopOffset,
                                          left: 0,
                                          right: 0,
                                          child: Text(
                                            AppStrings.you,
                                            style: AppTextStyles.playerName
                                                .copyWith(
                                              color: AppColors.ink,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // VS Metni
                                  SizedBox(
                                    height: AppDimens
                                        .matchmakingAvatarSlotHeight,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        height: avatarSlotSize,
                                        child: const Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal:
                                                  AppDimens.matchmakingVsGap,
                                            ),
                                            child: Text(
                                              AppStrings.vs,
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFredoka,
                                                fontSize: 26,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Sağ: Rakip (Arkadaş)
                                  SizedBox(
                                    width: avatarSlotSize,
                                    height: AppDimens
                                        .matchmakingAvatarSlotHeight,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.topCenter,
                                      children: [
                                        SizedBox(
                                          width: avatarSlotSize,
                                          height: avatarSlotSize,
                                          child: Center(
                                            child: PlayerAvatar.opponent(
                                              name: safeOpponentName,
                                              frame: opponentFrame,
                                              size: avatarSize,
                                              includeFramePadding: true,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: nameTopOffset,
                                          left: 0,
                                          right: 0,
                                          child: Text(
                                            safeOpponentName,
                                            style: AppTextStyles.playerName
                                                .copyWith(
                                              color: AppColors.ink,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Alt: 3.5 sn'de dolan metinsiz ilerleme çubuğu
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppDimens.space16,
                            ),
                            child: AppProgressBar.filling(
                              key: const ValueKey(
                                  'friend_reveal_progress_bar'),
                              fillDuration: duration,
                              maxWidth: 300,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
