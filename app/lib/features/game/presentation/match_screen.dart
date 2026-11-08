import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  final TextEditingController _inputController = TextEditingController();
  late final BannerSuppressionNotifier _suppressionNotifier;
  int _scrollGeneration = 0;
  double _lastBottomInset = 0.0;

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
    _inputController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool immediate = false}) {
    final int currentGen = ++_scrollGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || currentGen != _scrollGeneration) return;
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;
      final target1 = position.maxScrollExtent;

      if (immediate) {
        _scrollController.jumpTo(target1);
      } else {
        _scrollController.animateTo(
          target1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }

      // 2. Aşama: Yeni eklenen öğe ve ayraç render edilip maxScrollExtent
      // genişlemişse, bir sonraki frame'de güncel sınıra kaydır:
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || currentGen != _scrollGeneration) return;
        if (!_scrollController.hasClients) return;

        final updatedTarget = _scrollController.position.maxScrollExtent;
        if (_scrollController.position.pixels < updatedTarget) {
          if (immediate) {
            _scrollController.jumpTo(updatedTarget);
          } else {
            _scrollController.animateTo(
              updatedTarget,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        }
      });
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
      activeMatchUiStateProvider.select((s) {
        final attempts = s.displayAttempts;
        if (attempts.isEmpty) return '';
        final last = attempts.last;
        return '${attempts.length}_${last.playerId}_${last.text}_${last.isCorrect}';
      }),
      (prev, next) {
        if (next.isNotEmpty && next != prev) {
          _scrollToBottom();
        }
      },
    );

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (bottomInset != _lastBottomInset) {
      _lastBottomInset = bottomInset;
      _scrollToBottom();
    }

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

    final profile = ref.watch(profileProvider);
    final myNickname = profile.nickname?.trim();

    final decisiveRounds = matchState?.decisiveRounds ?? 0;
    final roundNumber = math.min(3, decisiveRounds + 1);

    final mode = ref.watch(activeMatchSessionModeProvider);
    final isOnlineRanked =
        mode == MatchSessionMode.online && !uiState.isFriendly;
    final hasExtraTime = uiState.extraTimeCost != null;
    final hasGiveAnswer = uiState.giveAnswerCost != null;
    final showPowerups = isOnlineRanked && (hasExtraTime || hasGiveAnswer);

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
                        child: PlayerCard(
                          name: AppStrings.you,
                          score: uiState.displayedScores['me'] ?? 0,
                          avatar: PlayerAvatar.selfMatch(
                            name: (myNickname != null && myNickname.isNotEmpty)
                                ? myNickname
                                : AppStrings.you,
                            frame: profile.equippedFrame,
                          ),
                          isActive: isMyTurn,
                          remainingSeconds: isMyTurn ? remainingSec : null,
                          timeProgress: isMyTurn ? timeProgress : null,
                          maxSeconds: maxSec,
                          isPaused: uiState.isPaused,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space8),
                      Expanded(
                        child: PlayerCard(
                          name: uiState.opponentName.isNotEmpty
                              ? uiState.opponentName
                              : AppStrings.opponent,
                          score: uiState.displayedScores['bot'] ?? 0,
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
                      ),
                    ],
                  ),
                  if (showPowerups) ...[
                    const SizedBox(height: AppDimens.space8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        if (hasExtraTime) ...[
                          _ExtraTimePowerupButton(
                            isMyTurn: isMyTurn,
                            remainingUses:
                                uiState.extraTimeRemainingUses ?? 1,
                            cost: uiState.extraTimeCost ?? 30,
                            seconds: uiState.extraTimeSeconds ?? 5,
                            isLoading: uiState.isUsingPowerup,
                            userCoins: profile.coins,
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
                        if (hasExtraTime && hasGiveAnswer)
                          const SizedBox(width: AppDimens.space8),
                        if (hasGiveAnswer) ...[
                          _GiveAnswerPowerupButton(
                            isMyTurn: isMyTurn,
                            remainingUses:
                                uiState.giveAnswerRemainingUses ?? 1,
                            cost: uiState.giveAnswerCost ?? 50,
                            isLoading: uiState.isUsingPowerup,
                            userCoins: profile.coins,
                            onTap: () {
                              _inputController.clear();
                              ref
                                  .read(activeMatchSessionProvider)
                                  .useGiveAnswer();
                            },
                            onInsufficientCoins: (cost) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppStrings.notEnoughCoinsForGiveAnswer(
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
                ],
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
                          viaPowerup: item.viaPowerup,
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
                    controller: _inputController,
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
  final bool viaPowerup;

  const _AnimatedBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isRejected = false,
    this.showTail = true,
    this.viaPowerup = false,
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
        viaPowerup: widget.viaPowerup,
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
                const CoinIcon(size: 14, opacity: 0.5),
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
                const CoinIcon(size: 14),
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

/// Cevap Ver (give_answer) güçlendiricisi butonu
class _GiveAnswerPowerupButton extends StatelessWidget {
  final bool isMyTurn;
  final int remainingUses;
  final int cost;
  final bool isLoading;
  final int userCoins;
  final VoidCallback onTap;
  final void Function(int cost) onInsufficientCoins;

  const _GiveAnswerPowerupButton({
    required this.isMyTurn,
    required this.remainingUses,
    required this.cost,
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

    // Durum 1: Kullanıldı (soluk gri, tıklanamaz)
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
              AppStrings.giveAnswerUsed,
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

    // Durum 2: Yetersiz Jeton (Soluk, tıklandığında SnackBar gösterir)
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
                SvgPicture.asset(
                  'assets/icons/powerup_auto_answer.svg',
                  width: 14,
                  height: 14,
                  colorFilter: const ColorFilter.mode(
                    AppColors.ink,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  AppStrings.giveAnswerPowerup,
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
                const CoinIcon(size: 14, opacity: 0.5),
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

    // Durum 3: Yeterli Jeton ve Kullanılabilir / Sıra Bende Değil / Yükleniyor
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
                SvgPicture.asset(
                  'assets/icons/powerup_auto_answer.svg',
                  width: 14,
                  height: 14,
                  colorFilter: const ColorFilter.mode(
                    AppColors.ink,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: AppDimens.space4),
                Text(
                  AppStrings.giveAnswerPowerup,
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
                const CoinIcon(size: 14),
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
            content: Text(AppStrings.notYourTurnGiveAnswer),
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
