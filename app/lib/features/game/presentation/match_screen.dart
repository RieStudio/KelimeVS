import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/match_providers.dart';
import '../domain/match/match_state.dart';

/// DESIGN.md Bölüm 7: Maç Ekranı
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final current = ref.read(matchControllerProvider);
        if (current.matchState == null ||
            current.matchState?.phase == MatchPhase.matchFinished) {
          ref.read(matchControllerProvider.notifier).startMatch();
        }
      }
    });
  }

  @override
  void dispose() {
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
              ref.read(matchControllerProvider.notifier).leaveMatch();
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

  String _getRoundResultText(MatchState? matchState) {
    if (matchState == null || matchState.roundHistory.isEmpty) return '';
    final lastRound = matchState.roundHistory.last;
    if (lastRound.winnerId == null) {
      return AppStrings.resultExhausted;
    }
    if (lastRound.winnerId == 'me') {
      return AppStrings.roundWonExclamation;
    }
    return AppStrings.roundLostExclamation;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      matchControllerProvider.select((s) => s.displayAttempts.length),
      (prev, next) {
        if (next > (prev ?? 0)) {
          _scrollToBottom();
        }
      },
    );

    final uiState = ref.watch(matchControllerProvider);
    final matchState = uiState.matchState;

    final decisiveRounds = matchState?.decisiveRounds ?? 0;
    final roundNumber = math.min(3, decisiveRounds + 1);

    final isMyTurn = uiState.isMyTurn;
    final isBotTurn = matchState?.phase == MatchPhase.roundActive &&
        matchState?.turnPlayerId == 'bot';

    final remainingSec = (uiState.remainingMs / 1000).ceil();
    final timeProgress = (uiState.remainingMs / 15000.0).clamp(0.0, 1.0);

    return Scaffold(
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
                  // 1. Üst Çubuk (Kapat İkon Butonu + "Tur N / 3" Hapı)
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
                              '${AppStrings.roundPrefix}$roundNumber / 3',
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
                    children: [
                      Expanded(
                        child: PlayerCard(
                          name: AppStrings.you,
                          score: matchState?.scores['me'] ?? 0,
                          avatar: const PlayerAvatar.selfMatch(),
                          isActive: isMyTurn,
                          remainingSeconds: isMyTurn ? remainingSec : null,
                          timeProgress: isMyTurn ? timeProgress : null,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: PlayerCard(
                          name: uiState.opponentName.isNotEmpty
                              ? uiState.opponentName
                              : AppStrings.opponent,
                          score: matchState?.scores['bot'] ?? 0,
                          avatar: PlayerAvatar.opponent(
                            name: uiState.opponentName,
                            size: AppDimens.avatarMatch,
                          ),
                          isActive: isBotTurn,
                          remainingSeconds: isBotTurn ? remainingSec : null,
                          timeProgress: isBotTurn ? timeProgress : null,
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
                        return _AnimatedBubble(
                          key: ValueKey('${item.playerId}_${item.text}_$index'),
                          text: item.text,
                          isMe: item.playerId == uiState.myPlayerId,
                          isRejected: !item.isCorrect,
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
                      ref.read(matchControllerProvider.notifier).submit(text);
                    },
                  ),
                ],
              ),
            ),

            // Geçici Tur Sonu Kartı (GEÇİCİ)
            if (uiState.isRoundEnded)
              Positioned.fill(
                child: Container(
                  color: AppColors.ink.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.screenPaddingHorizontal,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDimens.space20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusQuestionCard,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThick,
                      ),
                      boxShadow: AppDimens.shadowQuestionCard,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          AppStrings.temporaryTodoNotice,
                          style: AppTextStyles.secondaryText,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppDimens.space10),
                        const Text(
                          AppStrings.roundEndedTitle,
                          style: AppTextStyles.roundResultTitle,
                        ),
                        const SizedBox(height: AppDimens.space8),
                        Text(
                          _getRoundResultText(matchState),
                          style: AppTextStyles.questionText,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Geçici Maç Bitti Özet Kartı (GEÇİCİ)
            if (uiState.isMatchFinished)
              Positioned.fill(
                child: Container(
                  color: AppColors.ink.withValues(alpha: 0.25),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.screenPaddingHorizontal,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDimens.space20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusQuestionCard,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThick,
                      ),
                      boxShadow: AppDimens.shadowQuestionCard,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          AppStrings.temporaryTodoNotice,
                          style: AppTextStyles.secondaryText,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppDimens.space10),
                        Text(
                          matchState?.winnerId == 'me'
                              ? AppStrings.wonExclamation
                              : AppStrings.lostExclamation,
                          style: AppTextStyles.largeResult,
                        ),
                        const SizedBox(height: AppDimens.space8),
                        Text(
                          '${AppStrings.scorePrefix}${matchState?.scores['me'] ?? 0} - ${matchState?.scores['bot'] ?? 0}',
                          style: AppTextStyles.scoreSmall,
                        ),
                        const SizedBox(height: AppDimens.space20),
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                text: AppStrings.newMatch,
                                onPressed: () {
                                  ref
                                      .read(matchControllerProvider.notifier)
                                      .startMatch();
                                },
                              ),
                            ),
                            const SizedBox(width: AppDimens.space10),
                            Expanded(
                              child: SecondaryButton(
                                text: AppStrings.close,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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

  const _AnimatedBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isRejected = false,
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
      ),
    );
  }
}
