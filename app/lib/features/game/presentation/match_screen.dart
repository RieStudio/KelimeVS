import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_status_provider.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/match_providers.dart';
import '../application/match_session.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../domain/match/match_state.dart';
import 'match_end_view.dart';
import 'round_end_view.dart';

/// DESIGN.md Bölüm 7: Maç Ekranı
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  final ScrollController _scrollController = ScrollController();
  late final BannerSuppressionNotifier _suppressionNotifier;

  @override
  void initState() {
    super.initState();
    _suppressionNotifier = ref.read(bannerSuppressionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressionNotifier.suppress();
        final mode = ref.read(activeMatchSessionModeProvider);
        if (mode == MatchSessionMode.bot) {
          final current = ref.read(matchControllerProvider);
          if (!current.isLoading &&
              (current.matchState == null ||
                  current.matchState?.phase == MatchPhase.matchFinished)) {
            ref.read(matchControllerProvider.notifier).startMatch();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _suppressionNotifier.unsuppress();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showLeaveConfirmDialog() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimens.borderRadiusQuestionCard,
          side: const BorderSide(
            color: AppColors.ink,
            width: AppDimens.borderThin,
          ),
        ),
        title: const Text(
          AppStrings.leaveMatchConfirmTitle,
          style: AppTextStyles.cardTitle,
        ),
        content: const Text(
          AppStrings.leaveMatchPrompt,
          style: AppTextStyles.secondaryText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              AppStrings.cancel,
              style: AppTextStyles.cardTitle,
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              ref.read(activeMatchSessionProvider).leaveMatch();
            },
            child: Text(
              AppStrings.exit,
              style: AppTextStyles.cardTitle.copyWith(
                color: AppColors.dangerText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      activeMatchUiStateProvider.select((s) => s.displayAttempts.length),
      (prev, next) {
        if (next > (prev ?? 0)) {
          _scrollToBottom();
        }
      },
    );

    ref.listen<bool>(
      activeMatchUiStateProvider.select((s) => s.isVoided),
      (prev, next) {
        if (next && !(prev ?? false) && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const MatchmakingScreen(forceBotFallback: true),
            ),
          );
        }
      },
    );

    ref.listen<bool>(
      activeMatchUiStateProvider.select(
        (s) => s.isDisconnectedPermanent || s.isDisconnectedReplaced,
      ),
      (prev, next) {
        if (next && !(prev ?? false) && mounted) {
          final isReplaced =
              ref.read(activeMatchUiStateProvider).isDisconnectedReplaced;
          final messenger = ScaffoldMessenger.maybeOf(context);
          Navigator.of(context).popUntil((route) => route.isFirst);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                isReplaced
                    ? AppStrings.matchReplacedNotice
                    : AppStrings.connectionLostNotice,
              ),
            ),
          );
        }
      },
    );

    ref.listen<int>(
      activeMatchUiStateProvider.select((s) => s.powerupErrorCounter),
      (prev, next) {
        if (next > (prev ?? 0) && mounted) {
          final notice =
              ref.read(activeMatchUiStateProvider).powerupErrorNotice;
          if (notice != null && notice.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(notice),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      },
    );

    final uiState = ref.watch(activeMatchUiStateProvider);
    final matchState = uiState.matchState;

    final decisiveRounds = matchState?.decisiveRounds ?? 0;
    final roundNumber = math.min(3, decisiveRounds + 1);

    final mode = ref.watch(activeMatchSessionModeProvider);
    final isOnlineRanked =
        mode == MatchSessionMode.online && !uiState.isFriendly;

    final isMyTurn = uiState.isMyTurn;
    final isBotTurn = matchState?.phase == MatchPhase.roundActive &&
        matchState?.turnPlayerId == 'bot';

    final maxSec = uiState.maxAllowedSeconds;
    final remainingSec = (uiState.remainingMs / 1000).ceil().clamp(0, maxSec);
    final timeProgress =
        (uiState.remainingMs / (maxSec * 1000.0)).clamp(0.0, 1.0);
    final canLeaveWithoutPenalty = uiState.isMatchFinished;

    return PopScope(
      canPop: canLeaveWithoutPenalty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (canLeaveWithoutPenalty) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _showLeaveConfirmDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
                vertical: AppDimens.space8,
              ),
              child: Column(
                children: [
                  // 1. Üst Çubuk (Kapat İkon Butonu + "Tur N" Hapı)
                  Row(
                    children: [
                      AppIconButton(
                        icon: AppIcons.close,
                        semanticLabel: AppStrings.leaveMatch,
                        onTap: _showLeaveConfirmDialog,
                      ),
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.space16,
                              vertical: AppDimens.space6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: AppDimens.borderRadiusFull,
                              border: Border.all(
                                color: AppColors.ink,
                                width: AppDimens.borderThin,
                              ),
                            ),
                            child: Text(
                              AppStrings.round(roundNumber),
                              style: AppTextStyles.questionText.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: AppDimens.iconButtonSize,
                        height: AppDimens.iconButtonSize,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space12),

                  // 2. Oyuncu Kartları (Sen vs Rakip)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PlayerCard(
                              name: AppStrings.you,
                              score: matchState?.scores['me'] ?? 0,
                              avatar: PlayerAvatar.selfMatch(
                                frame: ref.watch(profileProvider).equippedFrame,
                              ),
                              isActive: isMyTurn,
                              remainingSeconds: isMyTurn ? remainingSec : null,
                              timeProgress: isMyTurn ? timeProgress : null,
                              maxSeconds: maxSec,
                              isPaused: uiState.isPaused,
                            ),
                            if (isOnlineRanked) ...[
                              const SizedBox(height: AppDimens.space6),
                              _ExtraTimePowerupButton(
                                isMyTurn: isMyTurn,
                                remainingUses:
                                    uiState.extraTimeRemainingUses ?? 1,
                                cost: uiState.extraTimeCost ?? 30,
                                seconds: uiState.extraTimeSeconds ?? 5,
                                isLoading: uiState.isUsingPowerup,
                                userCoins: ref.watch(profileProvider).coins,
                                onTap: () {
                                  ref
                                      .read(activeMatchSessionProvider)
                                      .useExtraTime();
                                },
                                onInsufficientCoins: (cost) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppStrings.notEnoughCoinsForExtraTime(
                                            cost),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PlayerCard(
                              name: uiState.opponentName.isNotEmpty
                                  ? uiState.opponentName
                                  : AppStrings.opponent,
                              score: matchState?.scores['bot'] ?? 0,
                              avatar: PlayerAvatar.opponent(
                                name: uiState.opponentName,
                                frame: uiState.opponentFrame,
                                size: AppDimens.avatarMatch,
                              ),
                              isActive: isBotTurn,
                              remainingSeconds: isBotTurn ? remainingSec : null,
                              timeProgress: isBotTurn ? timeProgress : null,
                              maxSeconds: maxSec,
                              isPaused: uiState.isPaused,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.space12),

                  // 3. Soru Kartı
                  QuestionCard(
                    text: matchState?.currentQuestion?.text ?? '',
                  ),
                  const SizedBox(height: AppDimens.space8),

                  // 4. Cevap Geçmişi Listesi
                  Expanded(
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.space8,
                      ),
                      itemCount: uiState.displayAttempts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppDimens.bubbleSpacing),
                      itemBuilder: (context, index) {
                        final item = uiState.displayAttempts[index];
                        final bool showTail = index == 0 ||
                            uiState.displayAttempts[index - 1].playerId !=
                                item.playerId;
                        return _AnimatedBubble(
                          key: ValueKey('${item.playerId}_${item.text}_$index'),
                          text: item.text,
                          isMe: item.playerId == uiState.myPlayerId,
                          isRejected: !item.isCorrect,
                          showTail: showTail,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppDimens.space8),

                  // 5. Giriş Alanı ve Gönder Butonu
                  AnswerInputBar(
                    isMyTurn: isMyTurn,
                    feedback: uiState.lastFeedback,
                    feedbackCounter: uiState.feedbackCounter,
                    onSubmitted: (text) {
                      ref.read(activeMatchSessionProvider).submit(text);
                    },
                  ),
                ],
              ),
            ),

            // 1.5 Bağlantı Uyarısı Şeridi (üst çubuğun hemen altında, içeriğin üstüne biner)
            if (!uiState.isMatchFinished && matchState != null)
              Positioned(
                top: AppDimens.space8 + AppDimens.iconButtonSize + 2,
                left: 0,
                right: 0,
                child: ConnectionBanner(
                  status: uiState.kendiBaglanti,
                  opponentConnected: uiState.opponentConnected,
                ),
              ),

            // 1.6 Rakip Ek Süre Bildirimi (üst çubuk altında 2 sn gösterilen hap)
            if (uiState.opponentExtraTimeBanner != null)
              Positioned(
                top: AppDimens.space8 + AppDimens.iconButtonSize + 4,
                left: AppDimens.screenPaddingHorizontal,
                right: AppDimens.screenPaddingHorizontal,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space16,
                      vertical: AppDimens.space6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.coin,
                      borderRadius: AppDimens.borderRadiusFull,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThin,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.ink,
                          offset: Offset(0, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer,
                          size: 16,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: AppDimens.space6),
                        Text(
                          uiState.opponentExtraTimeBanner!,
                          style: AppTextStyles.cardTitle.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 6. Tur Sonu Ekranı
            if (uiState.isRoundEnded)
              const Positioned.fill(
                child: RoundEndView(),
              ),

            // 7. Maç Sonucu Ekranı
            if (uiState.isMatchFinished)
              const Positioned.fill(
                child: MatchEndView(),
              ),
          ],
        ),
      ),
    ),
  );
}
}

/// 200 ms aşağıdan yukarı kayarak giren cevap balonu
class _AnimatedBubble extends StatefulWidget {
  final String text;
  final bool isMe;
  final bool isRejected;
  final bool showTail;

  const _AnimatedBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isRejected = false,
    this.showTail = true,
  });

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    _offsetAnim = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnim,
      child: AnswerBubble(
        text: widget.text,
        isMe: widget.isMe,
        isRejected: widget.isRejected,
        showTail: widget.showTail,
      ),
    );
  }
}

/// Ek süre güçlendiricisi (+5 sn) butonu
class _ExtraTimePowerupButton extends StatelessWidget {
  final bool isMyTurn;
  final int remainingUses;
  final int cost;
  final int seconds;
  final bool isLoading;
  final int userCoins;
  final VoidCallback onTap;
  final void Function(int cost) onInsufficientCoins;

  const _ExtraTimePowerupButton({
    required this.isMyTurn,
    required this.remainingUses,
    required this.cost,
    required this.seconds,
    required this.isLoading,
    required this.userCoins,
    required this.onTap,
    required this.onInsufficientCoins,
  });

  @override
  Widget build(BuildContext context) {
    final isUsed = remainingUses <= 0;
    final hasEnoughCoins = userCoins >= cost;
    final isInteractive = !isUsed && isMyTurn && !isLoading;

    // Durum 1: Kullanıldı
    if (isUsed) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space10,
          vertical: AppDimens.space4,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimens.borderRadiusFull,
          border: Border.all(
            color: AppColors.ink.withValues(alpha: 0.3),
            width: AppDimens.borderThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 14,
              color: AppColors.muted.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppDimens.space4),
            Text(
              AppStrings.extraTimeUsed,
              style: AppTextStyles.secondaryText.copyWith(
                fontSize: 11,
                color: AppColors.muted.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Durum 2: Yetersiz Jeton (Soluk, tıklandığında toast gösterir)
    if (!hasEnoughCoins) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onInsufficientCoins(cost),
        child: Opacity(
          opacity: 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space10,
              vertical: AppDimens.space4,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppDimens.borderRadiusFull,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer,
                  size: 14,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  '+$seconds sn',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  '·',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.coin,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.ink,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontWeight: FontWeight.w700,
                      fontSize: 8,
                      color: AppColors.ink,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '$cost',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Durum 3: Yeterli Jeton ve Kullanılabilir
    final buttonContent = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space4,
      ),
      decoration: BoxDecoration(
        color: isInteractive ? AppColors.coin : AppColors.card,
        borderRadius: AppDimens.borderRadiusFull,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
        boxShadow: isInteractive
            ? const [
                BoxShadow(
                  color: AppColors.ink,
                  offset: Offset(0, 2),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: isLoading
          ? const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.ink,
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer,
                  size: 14,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  '+$seconds sn',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  '·',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isInteractive ? AppColors.card : AppColors.coin,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.ink,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontWeight: FontWeight.w700,
                      fontSize: 8,
                      color: AppColors.ink,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '$cost',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );

    if (isInteractive) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: buttonContent,
      );
    }

    if (isLoading) {
      return Opacity(
        opacity: 0.7,
        child: buttonContent,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.notYourTurnPowerup),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Opacity(
        opacity: 0.5,
        child: buttonContent,
      ),
    );
  }
}
