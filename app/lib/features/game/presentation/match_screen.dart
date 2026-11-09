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

class _MatchScreenState extends ConsumerState<MatchScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  late final BannerSuppressionNotifier _suppressionNotifier;
  int _scrollGeneration = 0;
  double _lastBottomInset = 0.0;
  bool _isPowerupPanelOpen = false;
  late final AnimationController _radialAnimController;
  late final Animation<double> _radialAnim;

  void _openPowerupMenu() {
    setState(() {
      _isPowerupPanelOpen = true;
    });
    _radialAnimController.forward(from: 0.0);
  }

  void _closePowerupMenu({bool immediate = false}) {
    if (!_isPowerupPanelOpen && _radialAnimController.isDismissed) return;
    if (immediate) {
      _radialAnimController.reset();
      if (mounted) {
        setState(() {
          _isPowerupPanelOpen = false;
        });
      }
      return;
    }
    _radialAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isPowerupPanelOpen = false;
        });
      }
    });
  }

  void _togglePowerupMenu() {
    if (_isPowerupPanelOpen) {
      _closePowerupMenu();
    } else {
      _openPowerupMenu();
    }
  }

  @override
  void initState() {
    super.initState();
    _suppressionNotifier = ref.read(bannerSuppressionProvider.notifier);
    _radialAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _radialAnim = CurvedAnimation(
      parent: _radialAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
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
    _radialAnimController.dispose();
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

    // Tur değiştiğinde veya maç bittiğinde joker menüsünü otomatik kapat
    ref.listen<String>(
      activeMatchUiStateProvider.select(
        (s) =>
            '${s.matchState?.totalRoundsPlayed}_${s.matchState?.phase}_${s.matchState?.turnPlayerId}_${s.isMatchFinished}',
      ),
      (prev, next) {
        if (prev != null && prev != next && _isPowerupPanelOpen) {
          _closePowerupMenu(immediate: true);
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
    final isPowerupEligibleMode =
        (mode == MatchSessionMode.online || mode == MatchSessionMode.bot) &&
            !uiState.isFriendly;
    final hasExtraTime = uiState.extraTimeCost != null;
    final hasGiveAnswer = uiState.giveAnswerCost != null;
    final showPowerups =
        isPowerupEligibleMode && (hasExtraTime || hasGiveAnswer);
    final extraTimeUsed = (uiState.extraTimeRemainingUses ?? 1) <= 0;
    final giveAnswerUsed = (uiState.giveAnswerRemainingUses ?? 1) <= 0;
    final allPowerupsUsed =
        (hasExtraTime ? extraTimeUsed : true) &&
        (hasGiveAnswer ? giveAnswerUsed : true);

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

            // 1.7 Joker Butonu ve Çeyrek Radial Menü
            if (showPowerups) ...[
              if (_isPowerupPanelOpen) ...[
                // Dışarı dokunma bariyeri (ExcludeFocus ile klavye odağını çalmaz)
                Positioned.fill(
                  child: ExcludeFocus(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _closePowerupMenu(),
                    ),
                  ),
                ),
                // Radial Menü Öğeleri
                ..._buildRadialMenuItems(
                  context: context,
                  hasExtraTime: hasExtraTime,
                  hasGiveAnswer: hasGiveAnswer,
                  isMyTurn: isMyTurn,
                  extraTimeRemainingUses:
                      uiState.extraTimeRemainingUses ?? 1,
                  extraTimeCost: uiState.extraTimeCost ?? 30,
                  extraTimeSeconds: uiState.extraTimeSeconds ?? 5,
                  giveAnswerRemainingUses:
                      uiState.giveAnswerRemainingUses ?? 1,
                  giveAnswerCost: uiState.giveAnswerCost ?? 50,
                  isUsingPowerup: uiState.isUsingPowerup,
                  userCoins: profile.coins,
                ),
              ],
              // Jokerler Ana Butonu (Bariyerin üstünde, sağ üstte 40x40)
              Positioned(
                top: AppDimens.space8,
                right: AppDimens.screenPaddingHorizontal,
                child: ExcludeFocus(
                  child: _PowerupMenuButton(
                    animation: _radialAnim,
                    isOpen: _isPowerupPanelOpen,
                    allUsed: allPowerupsUsed,
                    isLoading: uiState.isUsingPowerup,
                    onTap: _togglePowerupMenu,
                  ),
                ),
              ),
            ],

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

  List<Widget> _buildRadialMenuItems({
    required BuildContext context,
    required bool hasExtraTime,
    required bool hasGiveAnswer,
    required bool isMyTurn,
    required int extraTimeRemainingUses,
    required int extraTimeCost,
    required int extraTimeSeconds,
    required int giveAnswerRemainingUses,
    required int giveAnswerCost,
    required bool isUsingPowerup,
    required int userCoins,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cx = screenWidth -
        (AppDimens.screenPaddingHorizontal + AppDimens.iconButtonSize / 2);
    const cy = AppDimens.space8 + AppDimens.iconButtonSize / 2;

    const radius = 82.0;

    // Buton 1 (Süre): Doğrudan aşağı (90°)
    const angleSure = 90.0 * (math.pi / 180.0);
    final targetX1 = cx + radius * math.cos(angleSure);
    final targetY1 = cy + radius * math.sin(angleSure);

    // Buton 2 (Cevap Ver): Sol-aşağı (141°)
    const angleCevapVer = 141.0 * (math.pi / 180.0);
    final targetX2 = cx + radius * math.cos(angleCevapVer);
    final targetY2 = cy + radius * math.sin(angleCevapVer);

    return [
      if (hasExtraTime)
        AnimatedBuilder(
          animation: _radialAnim,
          builder: (context, _) {
            final t = _radialAnim.value;
            final currentX = cx + (targetX1 - cx) * t;
            final currentY = cy + (targetY1 - cy) * t;
            final rightOffset = screenWidth - currentX;

            return Positioned(
              right: rightOffset - 26.0,
              top: currentY - 26.0,
              child: Transform.scale(
                scale: t,
                child: Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: ExcludeFocus(
                    child: _RadialPowerupItem(
                      title: AppStrings.extraTimePowerup,
                      cost: extraTimeCost,
                      icon: const Icon(
                        Icons.timer,
                        size: 24,
                        color: AppColors.ink,
                      ),
                      isUsed: extraTimeRemainingUses <= 0,
                      isInteractive: extraTimeRemainingUses > 0 &&
                          isMyTurn &&
                          !isUsingPowerup &&
                          userCoins >= extraTimeCost,
                      hasEnoughCoins: userCoins >= extraTimeCost,
                      isLoading: isUsingPowerup,
                      onTap: () {
                        _closePowerupMenu(immediate: true);
                        ref.read(activeMatchSessionProvider).useExtraTime();
                      },
                      onInsufficientCoins: (cost) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.notEnoughCoinsForExtraTime(cost),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      notMyTurnMessage: AppStrings.notYourTurnPowerup,
                      semanticLabel: extraTimeRemainingUses <= 0
                          ? '${AppStrings.extraTimePowerup} jokeri, ${AppStrings.extraTimeUsed}'
                          : '${AppStrings.extraTimePowerup} jokeri, $extraTimeCost jeton',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      if (hasGiveAnswer)
        AnimatedBuilder(
          animation: _radialAnim,
          builder: (context, _) {
            final t = _radialAnim.value;
            final currentX = cx + (targetX2 - cx) * t;
            final currentY = cy + (targetY2 - cy) * t;
            final rightOffset = screenWidth - currentX;

            return Positioned(
              right: rightOffset - 28.0,
              top: currentY - 26.0,
              child: Transform.scale(
                scale: t,
                child: Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: ExcludeFocus(
                    child: _RadialPowerupItem(
                      title: AppStrings.giveAnswerPowerup,
                      cost: giveAnswerCost,
                      icon: SvgPicture.asset(
                        'assets/icons/powerup_auto_answer.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          AppColors.ink,
                          BlendMode.srcIn,
                        ),
                      ),
                      isUsed: giveAnswerRemainingUses <= 0,
                      isInteractive: giveAnswerRemainingUses > 0 &&
                          isMyTurn &&
                          !isUsingPowerup &&
                          userCoins >= giveAnswerCost,
                      hasEnoughCoins: userCoins >= giveAnswerCost,
                      isLoading: isUsingPowerup,
                      onTap: () {
                        _closePowerupMenu(immediate: true);
                        _inputController.clear();
                        ref.read(activeMatchSessionProvider).useGiveAnswer();
                      },
                      onInsufficientCoins: (cost) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.notEnoughCoinsForGiveAnswer(cost),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      notMyTurnMessage: AppStrings.notYourTurnGiveAnswer,
                      semanticLabel: giveAnswerRemainingUses <= 0
                          ? '${AppStrings.giveAnswerPowerup} jokeri, ${AppStrings.giveAnswerUsed}'
                          : '${AppStrings.giveAnswerPowerup} jokeri, $giveAnswerCost jeton',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];
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

/// Joker butonu ikonu. İleride SVG ile değiştirilebilir.
const IconData _kPowerupMenuIcon = Icons.auto_awesome;

/// Sağ üstteki küçük Jokerler menü butonu (~40 dp)
class _PowerupMenuButton extends StatelessWidget {
  final Animation<double> animation;
  final bool isOpen;
  final bool allUsed;
  final bool isLoading;
  final VoidCallback onTap;

  const _PowerupMenuButton({
    required this.animation,
    required this.isOpen,
    required this.allUsed,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppStrings.powerups,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isLoading ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppDimens.minTouchTarget,
            minHeight: AppDimens.minTouchTarget,
          ),
          child: Center(
            child: Opacity(
              opacity: allUsed ? 0.5 : 1.0,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = animation.value;
                  return Container(
                    width: AppDimens.iconButtonSize,
                    height: AppDimens.iconButtonSize,
                    decoration: BoxDecoration(
                      color: Color.lerp(AppColors.card, AppColors.coin, t),
                      borderRadius: AppDimens.borderRadiusIconBtn,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThin,
                      ),
                      boxShadow: t > 0.5
                          ? null
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 2),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                    alignment: Alignment.center,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.ink,
                            ),
                          )
                        : Transform.rotate(
                            angle: t * (math.pi / 4), // 45° dönüş
                            child: const Icon(
                              _kPowerupMenuIcon,
                              size: 20,
                              color: AppColors.ink,
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Çeyrek radial menü üzerindeki yuvarlak joker butonu ve etiketi
class _RadialPowerupItem extends StatelessWidget {
  final String title;
  final int cost;
  final Widget icon;
  final bool isUsed;
  final bool isInteractive;
  final bool hasEnoughCoins;
  final bool isLoading;
  final VoidCallback onTap;
  final void Function(int cost) onInsufficientCoins;
  final String notMyTurnMessage;
  final String semanticLabel;

  const _RadialPowerupItem({
    required this.title,
    required this.cost,
    required this.icon,
    required this.isUsed,
    required this.isInteractive,
    required this.hasEnoughCoins,
    required this.isLoading,
    required this.onTap,
    required this.onInsufficientCoins,
    required this.notMyTurnMessage,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final double itemWidth =
        title == AppStrings.giveAnswerPowerup ? 56.0 : 52.0;

    final circle = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUsed
            ? AppColors.surface
            : (isInteractive ? AppColors.coin : AppColors.card),
        border: Border.all(
          color: isUsed
              ? AppColors.ink.withValues(alpha: 0.3)
              : AppColors.ink,
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
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.ink,
              ),
            )
          : (isUsed
              ? Icon(
                  Icons.check_circle_outline,
                  size: 24,
                  color: AppColors.muted.withValues(alpha: 0.6),
                )
              : icon),
    );

    final content = SizedBox(
      width: itemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          circle,
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isUsed
                    ? AppColors.muted.withValues(alpha: 0.7)
                    : AppColors.ink,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 1),
          if (isUsed)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppStrings.extraTimeUsed, // "Kullanıldı"
                style: AppTextStyles.secondaryText.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CoinIcon(size: 11, opacity: hasEnoughCoins ? 1.0 : 0.5),
                  const SizedBox(width: 2),
                  Text(
                    '$cost',
                    style: AppTextStyles.cardTitle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          hasEnoughCoins ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    Widget wrappedContent;
    if (isInteractive) {
      wrappedContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    } else if (isUsed || isLoading) {
      wrappedContent = Opacity(
        opacity: isUsed ? 0.85 : 0.7,
        child: content,
      );
    } else if (!hasEnoughCoins) {
      wrappedContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onInsufficientCoins(cost),
        child: Opacity(
          opacity: 0.5,
          child: content,
        ),
      );
    } else {
      wrappedContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(notMyTurnMessage),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Opacity(
          opacity: 0.5,
          child: content,
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        child: wrappedContent,
      ),
    );
  }
}
