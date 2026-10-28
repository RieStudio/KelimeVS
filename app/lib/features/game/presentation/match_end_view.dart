import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/result_circle.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../match_detail/presentation/match_detail_screen.dart';
import '../../matchmaking/presentation/matchmaking_screen.dart';
import '../application/match_history_provider.dart';
import '../application/match_providers.dart';
import '../application/match_session.dart';
import '../domain/history/match_history_entry.dart';
import '../../profile/application/blocked_users_notifier.dart';
import '../../profile/data/blocked_users_api_client.dart';

/// DESIGN.md Bölüm 7: 5) Maç Sonucu Ekranı
///
/// Sol üstte kapat (ana ekrana; şimdilik galeriye döner).
/// Ortada ResultCircle (kazandın: kupa, kaybettin: tekrar oku), başlık,
/// terk notu (varsa), skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı.
/// Altta "Tekrar Oyna" (ana buton).
/// // TODO: Sonraki adımda "Maç Detayı" butonu eklenecek.
class MatchEndView extends ConsumerStatefulWidget {
  const MatchEndView({super.key});

  @override
  ConsumerState<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends ConsumerState<MatchEndView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  bool _isReported = false;
  bool _isBlocked = false;
  bool _isSubmittingReport = false;
  bool _isSubmittingBlock = false;

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontNunito,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.ink,
      ),
    );
  }

  void _showReportBottomSheet(BuildContext context, String matchId, String opponentName) {
    if (!ensureNetworkConnected(context, ref)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ReportBottomSheet(
        opponentName: opponentName,
        onSubmit: (reason) async {
          Navigator.of(sheetContext).pop();
          setState(() => _isSubmittingReport = true);
          final client = ref.read(blockedUsersApiClientProvider);
          final res = await client.reportUser(matchId: matchId, reason: reason);
          if (!mounted) return;
          setState(() => _isSubmittingReport = false);

          if (res is ReportUserSuccess) {
            setState(() => _isReported = true);
            _showSnackBar(AppStrings.reportSuccess);
          } else if (res is ReportUserError) {
            if (res.isAlreadyReported) {
              setState(() => _isReported = true);
            }
            _showSnackBar(res.message);
          }
        },
      ),
    );
  }

  void _showBlockDialog(BuildContext context, String matchId, String opponentName) {
    if (!ensureNetworkConnected(context, ref)) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: AppDimens.borderRadiusDialog,
            side: const BorderSide(
              color: AppColors.ink,
              width: AppDimens.borderThick,
            ),
          ),
          title: const Text(
            AppStrings.blockDialogTitle,
            style: AppTextStyles.cardTitle,
          ),
          content: Text(
            AppStrings.blockDialogMessage(opponentName),
            style: AppTextStyles.bodyText,
          ),
          actions: [
            PrimaryButton(
              text: AppStrings.blockConfirm,
              backgroundColor: AppColors.danger,
              shadowColor: AppColors.dangerDark,
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                setState(() => _isSubmittingBlock = true);
                final client = ref.read(blockedUsersApiClientProvider);
                final res = await client.blockUser(matchId);
                if (!mounted) return;
                setState(() => _isSubmittingBlock = false);

                if (res is BlockUserSuccess) {
                  ref.invalidate(blockedUsersProvider);
                  setState(() => _isBlocked = true);
                  _showSnackBar(AppStrings.blockSuccess(opponentName));
                } else if (res is BlockUserError) {
                  _showSnackBar(res.message);
                }
              },
            ),
            const SizedBox(height: AppDimens.space8),
            SecondaryButton(
              text: AppStrings.cancel,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(activeMatchUiStateProvider);
    final matchState = uiState.matchState;

    final isWinner = matchState?.winnerId == 'me';
    final isForfeit = matchState?.endedBy == 'forfeit';

    final resolvedEndReason = uiState.lastSavedMatch?.endReason ??
        (isForfeit
            ? (isWinner ? MatchEndReason.rakipTerk : MatchEndReason.terk)
            : MatchEndReason.normal);

    final String? endNote;
    final Color endNoteColor;
    switch (resolvedEndReason) {
      case MatchEndReason.terk:
        endNote = AppStrings.youLeftMatch;
        endNoteColor = AppColors.dangerText;
      case MatchEndReason.baglantiKoptu:
        endNote = AppStrings.yourConnectionLost;
        endNoteColor = AppColors.dangerText;
      case MatchEndReason.rakipTerk:
        endNote = AppStrings.opponentLeftMatch;
        endNoteColor = AppColors.muted;
      case MatchEndReason.rakipBaglantiKoptu:
        endNote = AppStrings.opponentConnectionLost;
        endNoteColor = AppColors.muted;
      case MatchEndReason.normal:
        final lastRound = matchState?.roundHistory.isNotEmpty == true
            ? matchState!.roundHistory.last
            : (uiState.lastSavedMatch?.roundRecords.isNotEmpty == true
                ? uiState.lastSavedMatch!.roundRecords.last
                : null);
        final totalRounds = matchState?.totalRoundsPlayed ??
            uiState.lastSavedMatch?.roundRecords.length ??
            0;
        final maxTotal = matchState?.config.maxTotalRounds ?? 5;

        if (totalRounds >= maxTotal && lastRound?.winnerId == null) {
          endNote = AppStrings.reasonRoundLimitReached;
          endNoteColor = AppColors.muted;
        } else if (lastRound != null) {
          if (lastRound.winnerId == 'me') {
            endNote = AppStrings.reasonOpponentTimeout;
            endNoteColor = AppColors.muted;
          } else if (lastRound.winnerId != null) {
            endNote = AppStrings.reasonMyTimeout;
            endNoteColor = AppColors.dangerText;
          } else {
            endNote = null;
            endNoteColor = AppColors.muted;
          }
        } else {
          endNote = null;
          endNoteColor = AppColors.muted;
        }
    }

    final myScore = matchState?.scores['me'] ?? 0;
    final opponentScore = matchState?.scores['bot'] ?? 0;

    final mode = ref.watch(activeMatchSessionModeProvider);
    final lastMatch = uiState.lastSavedMatch;
    final isOnlineMatch = mode == MatchSessionMode.online &&
        lastMatch != null &&
        lastMatch.matchId != null &&
        !lastMatch.botlaOynandi;
    final matchId = lastMatch?.matchId;
    final opponentDisplayName = (lastMatch?.opponentName.isNotEmpty ?? false)
        ? lastMatch!.opponentName
        : (uiState.opponentName.isNotEmpty ? uiState.opponentName : AppStrings.opponent);
    final oppFrame = lastMatch?.opponentFrame ?? uiState.opponentFrame;

    final ResultCircleVariant circleVariant;
    final AppIconData icon;
    final String title;
    final TextStyle titleStyle;

    if (isWinner) {
      circleVariant = ResultCircleVariant.win;
      icon = AppIcons.trophy;
      title = AppStrings.wonExclamation;
      titleStyle = AppTextStyles.largeResult;
    } else {
      circleVariant = ResultCircleVariant.lose;
      icon = AppIcons.refresh;
      title = AppStrings.lost;
      titleStyle = AppTextStyles.largeResultDanger;
    }

    final int? coinsAwarded = uiState.coinsAwarded;
    final bool isFriendly = uiState.isFriendly ||
        (uiState.lastSavedMatch?.isFriendly ?? false);

    final Widget content = Container(
      color: AppColors.surface,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.space12,
          ),
          child: Column(
            children: [
              // 1. Üst Çubuk (Sol üstte Kapat ikonu)
              Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.close,
                    semanticLabel: AppStrings.close,
                    onTap: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                  const Spacer(),
                ],
              ),

              const Spacer(flex: 3),

              // 2. ResultCircle (104 px)
              ResultCircle(
                variant: circleVariant,
                icon: icon,
              ),

              const SizedBox(height: AppDimens.space20),

              // 3. Başlık ("Kazandın!" / "Kaybettin")
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),

              // 4. Terk / Bağlantı Notu (varsa)
              if (endNote != null) ...[
                const SizedBox(height: AppDimens.space6),
                Text(
                  endNote,
                  style: AppTextStyles.secondaryText.copyWith(
                    color: endNoteColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: AppDimens.space16),

              // 5. Skor ("Sen 2 – 1 Rakip")
              Semantics(
                label: 'Skor: Sen $myScore, Rakip $opponentScore',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      AppStrings.you,
                      style: AppTextStyles.questionText.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      '$myScore${AppStrings.scoreDash}$opponentScore',
                      style: AppTextStyles.scoreSmall.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppDimens.space8),
                    Text(
                      AppStrings.opponent,
                      style: AppTextStyles.questionText.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              // 6. Dostluk Maçı Rozeti veya Jeton Ödülü Kartı
              if (isFriendly) ...[
                const SizedBox(height: AppDimens.space20),
                Semantics(
                  container: true,
                  label: AppStrings.friendDuelMatchBadge,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space20,
                      vertical: AppDimens.space8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusFull,
                      border: Border.all(
                        color: AppColors.mint,
                        width: AppDimens.borderThin,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          size: 20,
                          color: AppColors.mint,
                        ),
                        const SizedBox(width: AppDimens.space8),
                        Text(
                          AppStrings.friendDuelMatchBadge,
                          style: AppTextStyles.bodyText.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (coinsAwarded != null) ...[
                const SizedBox(height: AppDimens.space20),
                Semantics(
                  container: true,
                  label: 'Jeton ödülü: $coinsAwarded',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space20,
                      vertical: AppDimens.space8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusFull,
                      border: Border.all(
                        color: AppColors.mint,
                        width: AppDimens.borderThin,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Jeton Dairesi ("G")
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.coin,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.ink,
                              width: AppDimens.borderThin,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFredoka,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.ink,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimens.space10),
                        Text(
                          '+$coinsAwarded${AppStrings.coinSuffix}',
                          style: AppTextStyles.questionText.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 6b. Rakip Kartı (Yalnızca online maçta gösterilir, bot maçında ASLA gösterilmez)
              if (isOnlineMatch && matchId != null) ...[
                const SizedBox(height: AppDimens.space16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppDimens.borderRadiusListCard,
                    border: Border.all(
                      color: AppColors.mint,
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
                    children: [
                      // Rakip Avatar
                      PlayerAvatar.opponent(
                        name: opponentDisplayName,
                        frame: oppFrame,
                        size: 36,
                      ),
                      const SizedBox(width: AppDimens.space10),

                      // Rakip Takma Adı
                      Expanded(
                        child: Text(
                          opponentDisplayName,
                          style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space8),

                      // Bildir Düğmesi
                      SecondaryButton(
                        text: _isReported ? AppStrings.reportedStatus : AppStrings.reportAction,
                        height: 38,
                        width: 78,
                        onPressed: (_isReported || _isSubmittingReport)
                            ? null
                            : () => _showReportBottomSheet(context, matchId, opponentDisplayName),
                      ),
                      const SizedBox(width: AppDimens.space8),

                      // Engelle Düğmesi
                      SecondaryButton.danger(
                        text: _isBlocked ? AppStrings.blockedStatus : AppStrings.blockAction,
                        height: 38,
                        width: 82,
                        onPressed: (_isBlocked || _isSubmittingBlock)
                            ? null
                            : () => _showBlockDialog(context, matchId, opponentDisplayName),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(flex: 4),

              // 7. Butonlar ("Tekrar Oyna")
              PrimaryButton(
                text: AppStrings.playAgain,
                onPressed: () {
                  if (!ensureNetworkConnected(context, ref)) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const MatchmakingScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: AppDimens.space12),

              SecondaryButton(
                text: AppStrings.matchDetail,
                onPressed: () async {
                  final lastMatch =
                      ref.read(activeMatchUiStateProvider).lastSavedMatch;
                  if (lastMatch != null) {
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MatchDetailScreen(match: lastMatch),
                        ),
                      );
                    }
                    return;
                  }

                  // Fallback: geçmişten en son maçı al
                  final recent =
                      await ref.read(matchHistoryRepositoryProvider).loadRecent();
                  if (recent.isNotEmpty && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatchDetailScreen(match: recent.first),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: AppDimens.space12),
            ],
          ),
        ),
      ),
    );

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      return content;
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: content,
    );
  }
}

class _ReportBottomSheet extends StatefulWidget {
  final String opponentName;
  final ValueChanged<String> onSubmit;

  const _ReportBottomSheet({
    required this.opponentName,
    required this.onSubmit,
  });

  @override
  State<_ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<_ReportBottomSheet> {
  String? _selectedReason;

  final _reasons = const [
    (key: 'inappropriate_nickname', label: AppStrings.reasonInappropriateNickname),
    (key: 'inappropriate_content', label: AppStrings.reasonInappropriateContent),
    (key: 'cheating', label: AppStrings.reasonCheating),
    (key: 'other', label: AppStrings.reasonOther),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.screenPaddingHorizontal,
          vertical: AppDimens.space20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.reportDialogTitle,
              style: AppTextStyles.cardTitle.copyWith(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space6),
            Text(
              '${widget.opponentName} adlı oyuncuyu neden bildirmek istiyorsun?',
              style: AppTextStyles.bodyText.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space16),
            ..._reasons.map((r) {
              final isSelected = _selectedReason == r.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.space8),
                child: InkWell(
                  onTap: () => setState(() => _selectedReason = r.key),
                  borderRadius: AppDimens.borderRadiusListCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space16,
                      vertical: AppDimens.space12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.surface : AppColors.card,
                      borderRadius: AppDimens.borderRadiusListCard,
                      border: Border.all(
                        color: isSelected ? AppColors.ink : AppColors.mint,
                        width: isSelected ? AppDimens.borderThick : AppDimens.borderThin,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? AppColors.primary : AppColors.muted,
                        ),
                        const SizedBox(width: AppDimens.space12),
                        Expanded(
                          child: Text(
                            r.label,
                            style: AppTextStyles.bodyText.copyWith(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppDimens.space16),
            PrimaryButton(
              text: AppStrings.reportAction,
              onPressed: _selectedReason != null
                  ? () => widget.onSubmit(_selectedReason!)
                  : null,
            ),
            const SizedBox(height: AppDimens.space8),
            SecondaryButton(
              text: AppStrings.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

