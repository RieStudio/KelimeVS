// GEÇİCİ TEST SAYFASI. Sonraki adımlarda gerçek oyun ekranlarıyla değiştirilecek.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import '../game/application/match_providers.dart';
import '../game/domain/match/match_events.dart';

class MatchTestPage extends ConsumerStatefulWidget {
  const MatchTestPage({super.key});

  @override
  ConsumerState<MatchTestPage> createState() => _MatchTestPageState();
}

class _MatchTestPageState extends ConsumerState<MatchTestPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(matchControllerProvider.notifier).startMatch();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _submitInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(matchControllerProvider.notifier).submit(text);
  }

  void _confirmLeaveMatch() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimens.borderRadiusQuestionCard,
          side: const BorderSide(color: AppColors.ink, width: AppDimens.borderThin),
        ),
        title: const Text(AppStrings.leaveMatchConfirmTitle, style: AppTextStyles.cardTitle),
        content: const Text(AppStrings.leaveMatchConfirmMessage, style: AppTextStyles.secondaryText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel, style: AppTextStyles.cardTitle),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(matchControllerProvider.notifier).leaveMatch();
            },
            child: Text(
              AppStrings.leaveMatchConfirm,
              style: AppTextStyles.cardTitle.copyWith(color: AppColors.dangerText),
            ),
          ),
        ],
      ),
    );
  }

  String _formatEvent(MatchEvent event, String opponentName) {
    return switch (event) {
      AnswerAccepted(:final playerId, :final answerDisplay) =>
        playerId == 'me'
            ? 'Sen: "$answerDisplay" → ${AppStrings.resultCorrect}'
            : '$opponentName: "$answerDisplay" → ${AppStrings.resultCorrect}',
      NearMiss(:final playerId) =>
        playerId == 'me'
            ? 'Sen: ${AppStrings.nearMissExclamation}'
            : '$opponentName: ${AppStrings.nearMissExclamation}',
      WrongAnswer(:final playerId, :final rawInput) =>
        playerId == 'me'
            ? 'Sen: "$rawInput" → ${AppStrings.eventWrongAnswer}'
            : '$opponentName: "$rawInput" → ${AppStrings.eventWrongAnswer}',
      AlreadySaid(:final playerId, :final answerDisplay) =>
        playerId == 'me'
            ? 'Sen: "$answerDisplay" → ${AppStrings.eventAlreadySaid}'
            : '$opponentName: "$answerDisplay" → ${AppStrings.eventAlreadySaid}',
      RoundWon(:final winnerId, :final reason) =>
        winnerId == 'me'
            ? 'Tur kazandın (${_reasonStr(reason)})'
            : '$opponentName turu kazandı (${_reasonStr(reason)})',
      RoundDrawn(:final reason) =>
        'Tur berabere (${_reasonStr(reason)})',
      MatchFinished(:final winnerId, :final reason) =>
        reason == 'forfeit'
            ? (winnerId == 'me'
                ? 'Rakip maçı terk etti, kazandın!'
                : 'Maçı terk ettin, $opponentName kazandı!')
            : (winnerId == 'me'
                ? 'Maçı kazandın!'
                : 'Maçı $opponentName kazandı!'),
      Ignored(:final reason) =>
        reason == 'tooFast'
            ? 'Çok hızlı deneme yoksayıldı (<600ms)'
            : reason == 'tooManyAttempts'
                ? 'Maksimum deneme aşıldı (>25)'
                : 'Yoksayıldı: $reason',
    };
  }

  String _reasonStr(RoundEndReason reason) {
    return switch (reason) {
      RoundEndReason.timeout => AppStrings.eventTimeout,
      RoundEndReason.exhausted => AppStrings.eventExhausted,
      RoundEndReason.forfeit => AppStrings.eventForfeit,
    };
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(matchControllerProvider);
    final match = uiState.matchState;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(AppStrings.matchTestTitle, style: AppTextStyles.screenTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: AppIconButton(
          icon: AppIcons.back,
          onTap: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (match != null && !uiState.isMatchFinished)
            Padding(
              padding: const EdgeInsets.only(right: AppDimens.space12),
              child: TextButton(
                onPressed: _confirmLeaveMatch,
                child: Text(
                  AppStrings.leaveMatch,
                  style: AppTextStyles.secondaryText.copyWith(
                    color: AppColors.dangerText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: uiState.isLoading
            ? const Center(
                child: Text(
                  AppStrings.loadingQuestions,
                  style: AppTextStyles.cardTitle,
                ),
              )
            : uiState.errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
                      child: Text(
                        uiState.errorMessage!,
                        style: AppTextStyles.cardTitle.copyWith(color: AppColors.dangerText),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : match == null
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.screenPaddingHorizontal,
                          vertical: AppDimens.space12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Bilgilendirme Notu
                            Container(
                              padding: const EdgeInsets.all(AppDimens.space10),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: AppDimens.borderRadiusBadge,
                                border: Border.all(
                                  color: AppColors.mint,
                                  width: AppDimens.borderThin,
                                ),
                              ),
                              child: Text(
                                AppStrings.matchTestNotice,
                                style: AppTextStyles.secondaryText.copyWith(color: AppColors.muted),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: AppDimens.space12),

                            // 2. Skor ve Tur Kartı
                            Container(
                              padding: const EdgeInsets.all(AppDimens.space14),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: AppDimens.borderRadiusQuestionCard,
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: AppDimens.borderThin,
                                ),
                                boxShadow: AppDimens.shadowQuestionCard,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      Text(AppStrings.you, style: AppTextStyles.playerName),
                                      const SizedBox(height: AppDimens.space4),
                                      Text(
                                        '${match.scores['me'] ?? 0}',
                                        style: AppTextStyles.scoreSmall,
                                      ),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        '${AppStrings.roundPrefix}${match.totalRoundsPlayed + 1}',
                                        style: AppTextStyles.cardTitle,
                                      ),
                                      const SizedBox(height: AppDimens.space4),
                                      Text('vs', style: AppTextStyles.secondaryText),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text(uiState.opponentName, style: AppTextStyles.playerName),
                                      const SizedBox(height: AppDimens.space4),
                                      Text(
                                        '${match.scores['bot'] ?? 0}',
                                        style: AppTextStyles.scoreSmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimens.space12),

                            // 3. Soru Kartı
                            Container(
                              padding: const EdgeInsets.all(AppDimens.space16),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: AppDimens.borderRadiusQuestionCard,
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: AppDimens.borderThin,
                                ),
                                boxShadow: AppDimens.shadowQuestionCard,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${AppStrings.categoryPrefix}${match.currentQuestion?.categoryId ?? ""}',
                                    style: AppTextStyles.sectionLabel,
                                  ),
                                  const SizedBox(height: AppDimens.space8),
                                  Text(
                                    match.currentQuestion?.text ?? '',
                                    style: AppTextStyles.questionText,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimens.space12),

                            // 4. Durum Satırı (Kalan Süre & Sıra)
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimens.space12,
                                      vertical: AppDimens.space10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.card,
                                      borderRadius: AppDimens.borderRadiusBadge,
                                      border: Border.all(
                                        color: AppColors.mint,
                                        width: AppDimens.borderThin,
                                      ),
                                    ),
                                    child: Text(
                                      '${AppStrings.timeLeftPrefix}${(uiState.remainingMs / 1000).ceil()}${AppStrings.secondsSuffix}',
                                      style: AppTextStyles.secondaryText.copyWith(color: AppColors.ink),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppDimens.space10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimens.space12,
                                      vertical: AppDimens.space10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: uiState.isMyTurn ? AppColors.bright : AppColors.card,
                                      borderRadius: AppDimens.borderRadiusBadge,
                                      border: Border.all(
                                        color: AppColors.ink,
                                        width: AppDimens.borderThin,
                                      ),
                                    ),
                                    child: Text(
                                      '${AppStrings.turnPrefix}${uiState.isMyTurn ? AppStrings.turnMy : uiState.opponentName}',
                                      style: AppTextStyles.secondaryText.copyWith(
                                        color: AppColors.ink,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimens.space12),

                            // 5. Maç Bitti Kartı (Eğer bittiyse)
                            if (uiState.isMatchFinished) ...[
                              Container(
                                padding: const EdgeInsets.all(AppDimens.space16),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: AppDimens.borderRadiusQuestionCard,
                                  border: Border.all(
                                    color: AppColors.ink,
                                    width: AppDimens.borderThin,
                                  ),
                                  boxShadow: AppDimens.shadowQuestionCard,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      AppStrings.matchFinishedTitle,
                                      style: AppTextStyles.roundResultTitle,
                                    ),
                                    const SizedBox(height: AppDimens.space8),
                                    Text(
                                      '${AppStrings.winnerPrefix}${uiState.summary?.winnerId == "me" ? AppStrings.wonExclamation : "${uiState.opponentName} kazandı!"}',
                                      style: AppTextStyles.cardTitle,
                                    ),
                                    const SizedBox(height: AppDimens.space4),
                                    Text(
                                      '${AppStrings.scorePrefix}${uiState.summary?.scores['me'] ?? 0} - ${uiState.summary?.scores['bot'] ?? 0}',
                                      style: AppTextStyles.scoreSmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppDimens.space12),
                            ],

                            // 6. Giriş Alanı + Gönder (Sıra bendeyse ve maç bitmediyse)
                            if (!uiState.isMatchFinished) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: AppColors.card,
                                        borderRadius: AppDimens.borderRadiusInput,
                                        border: Border.all(
                                          color: AppColors.ink,
                                          width: AppDimens.borderThin,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _inputController,
                                        enabled: uiState.isMyTurn,
                                        style: AppTextStyles.inputField,
                                        decoration: InputDecoration(
                                          hintText: uiState.isMyTurn
                                              ? AppStrings.inputPlaceholder
                                              : 'Rakibin sırası…',
                                          hintStyle: AppTextStyles.inputField.copyWith(
                                            color: AppColors.muted.withValues(alpha: 0.6),
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: AppDimens.space16,
                                            vertical: AppDimens.space12,
                                          ),
                                        ),
                                        onSubmitted: (_) => _submitInput(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppDimens.space8),
                                  AppIconButton(
                                    icon: AppIcons.arrowSend,
                                    onTap: uiState.isMyTurn ? _submitInput : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppDimens.space12),
                            ],

                            // 7. Olay Günlüğü
                            Text(AppStrings.eventLogTitle, style: AppTextStyles.cardTitle),
                            const SizedBox(height: AppDimens.space8),
                            Container(
                              height: 180,
                              padding: const EdgeInsets.all(AppDimens.space12),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: AppDimens.borderRadiusQuestionCard,
                                border: Border.all(
                                  color: AppColors.mint,
                                  width: AppDimens.borderThin,
                                ),
                              ),
                              child: uiState.recentEvents.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Henüz bir olay yok.',
                                        style: AppTextStyles.secondaryText,
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _logScrollController,
                                      itemCount: uiState.recentEvents.length,
                                      itemBuilder: (context, index) {
                                        final event = uiState.recentEvents[index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: AppDimens.space4,
                                          ),
                                          child: Text(
                                            '• ${_formatEvent(event, uiState.opponentName)}',
                                            style: AppTextStyles.secondaryText.copyWith(
                                              fontSize: 13,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            const SizedBox(height: AppDimens.space16),

                            // 8. Yeni Maç Butonu
                            SecondaryButton(
                              text: AppStrings.newMatch,
                              onPressed: () {
                                ref.read(matchControllerProvider.notifier).startMatch();
                              },
                            ),
                            const SizedBox(height: AppDimens.space24),
                          ],
                        ),
                      ),
      ),
    );
  }
}
