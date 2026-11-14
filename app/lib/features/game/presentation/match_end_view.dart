import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/opponent_name_sanitizer.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/coin_icon.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/match_result_icon.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../friend_match/presentation/friend_reveal_screen.dart';
import '../../match_detail/presentation/match_detail_screen.dart';
import '../../online/application/online_match_session.dart';
import '../../online/domain/models/rematch_state.dart';
import '../../profile/application/profile_notifier.dart';
import '../../store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import '../application/bot_rematch_controller.dart';
import '../application/match_history_provider.dart';
import '../application/match_providers.dart';
import '../application/match_session.dart';
import '../domain/history/match_history_entry.dart';

/// DESIGN.md Bölüm 7: 5) Maç Sonucu Ekranı
///
/// Sol üstte kapat (ana ekrana; şimdilik galeriye döner).
/// Ortada MatchResultIcon (kazandın: match_win.svg, kaybettin: match_lose.svg), başlık,
/// terk notu (varsa), skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı.
/// Altta "Tekrar Oyna" (ana buton) ve "Maç Detayı" (ikincil buton).
class MatchEndView extends ConsumerStatefulWidget {
  const MatchEndView({super.key});

  @override
  ConsumerState<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends ConsumerState<MatchEndView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  OnlineMatchSession? _onlineSession;
  BotRematchController? _botRematchController;
  bool _isOnline = false;
  bool _hasHandledMatched = false;
  RematchState _lastRematchState = RematchState.unavailable;

  /// Rakip adını sanitize eder (ortak [OpponentNameSanitizer] sınıfını kullanır).
  static String _sanitizeOpponentName(String? raw) => OpponentNameSanitizer.sanitize(raw);

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isOnline = ref.read(activeMatchSessionModeProvider) == MatchSessionMode.online;
    _onlineSession = _isOnline ? ref.read(onlineMatchSessionProvider.notifier) : null;
    if (_isOnline) {
      _lastRematchState = ref.read(rematchStateProvider);
    }
    if (!_isOnline && _botRematchController == null) {
      final uiState = ref.read(activeMatchUiStateProvider);
      final isNormal = (uiState.lastSavedMatch?.endReason ?? MatchEndReason.normal) == MatchEndReason.normal;
      _botRematchController = BotRematchController(isNormalEnd: isNormal);
      _botRematchController!.addListener(_onBotRematchChanged);
    }
  }

  void _onBotRematchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animController.dispose();
    _leaveRematchIfOnline();
    _botRematchController?.removeListener(_onBotRematchChanged);
    _botRematchController?.dispose();
    _botRematchController = null;
    super.dispose();
  }

  void _leaveRematchIfOnline() {
    if (_hasHandledMatched) return;
    if (!_isOnline) return;
    if (_lastRematchState is RematchMatched ||
        _lastRematchState is RematchStarting) {
      return;
    }
    _onlineSession?.leaveRematch();
  }

  void _showEnergyDepletedSheet() {
    final profile = ref.read(profileProvider);
    final energy = profile.energy;
    if (energy == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EnergyDepletedBottomSheet(
        energy: energy,
        userCoins: profile.coins,
        serverNowMs: profile.serverNowMs,
      ),
    );
  }

  bool _ensureEnergyAvailable(bool isFriendly) {
    if (!_isOnline || isFriendly) return true;
    final profile = ref.read(profileProvider);
    final energy = profile.energy;
    if (energy != null && energy.enabled && energy.current < 1) {
      _showEnergyDepletedSheet();
      return false;
    }
    return true;
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

    final lastMatch = uiState.lastSavedMatch;
    final rawOpponentName = (lastMatch?.opponentName.trim().isNotEmpty ?? false)
        ? lastMatch!.opponentName
        : uiState.opponentName;
    final opponentDisplayName = _sanitizeOpponentName(rawOpponentName);

    final MatchResultVariant resultVariant;
    final String title;
    final TextStyle titleStyle;

    if (isWinner) {
      resultVariant = MatchResultVariant.win;
      title = AppStrings.wonExclamation;
      titleStyle = AppTextStyles.largeResult;
    } else {
      resultVariant = MatchResultVariant.lose;
      title = AppStrings.lost;
      titleStyle = AppTextStyles.largeResultDanger;
    }

    final int? coinsAwarded = uiState.coinsAwarded;
    final bool isFriendly = uiState.isFriendly ||
        (uiState.lastSavedMatch?.isFriendly ?? false);

    ref.listen<RematchState>(rematchStateProvider, (previous, next) {
      _lastRematchState = next;
      if (_isOnline && next is RematchMatched && !_hasHandledMatched) {
        _hasHandledMatched = true;
        openRematchReveal(context, ref, next.matchedMessage);
      }
    });

    if (_isOnline && !_hasHandledMatched) {
      final currentRematch = ref.read(rematchStateProvider);
      _lastRematchState = currentRematch;
      if (currentRematch is RematchMatched) {
        _hasHandledMatched = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            openRematchReveal(context, ref, currentRematch.matchedMessage);
          }
        });
      }
    }

    final RematchState rematchState = _isOnline
        ? ref.watch(rematchStateProvider)
        : (_botRematchController?.state ?? RematchState.unavailable);
    _lastRematchState = rematchState;

    final Widget content = Container(
      color: AppColors.surface,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
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
              // 1. Üst Çubuk (Sol üstte Kapat ikonu)
              Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.close,
                    semanticLabel: AppStrings.close,
                    onTap: () {
                      _leaveRematchIfOnline();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                  const Spacer(),
                ],
              ),

              const Spacer(flex: 3),

              // 2. Maç Sonu SVG İkonu (116 dp)
              MatchResultIcon(
                variant: resultVariant,
              ),

              const SizedBox(height: AppDimens.space12),

              // 3. Başlık ("Kazandın!" / "Kaybettin")
              Semantics(
                header: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: titleStyle,
                    textAlign: TextAlign.center,
                  ),
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

              // 5. Skor ("Sen 2 – 1 Rakip" / "Sen 2 – 1 <RakipAdı>")
              Semantics(
                label: 'Skor: Sen $myScore, $opponentDisplayName $opponentScore',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.35,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            opponentDisplayName,
                            maxLines: 1,
                            style: AppTextStyles.questionText.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 6. Jeton Ödülü Kartı (Yalnızca normal maçlarda ve coinsAwarded varsa)
              if (!isFriendly && coinsAwarded != null) ...[
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Jeton Simgesi (CoinIcon)
                          const CoinIcon(size: 32),
                          const SizedBox(width: AppDimens.space10),
                          Text(
                            AppStrings.coinReward(coinsAwarded),
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
                ),
              ],

              const Spacer(flex: 4),

              // 7. Eylem Alanı (Rövanş / Bekleme / Kabul-Red / Ana Sayfa)
              _buildRematchActionArea(
                rematchState: rematchState,
                opponentDisplayName: opponentDisplayName,
                onOfferRematch: () {
                  if (_isOnline && !ensureNetworkConnected(context, ref)) return;
                  if (!_ensureEnergyAvailable(isFriendly)) return;
                  if (_isOnline) {
                    _onlineSession?.offerRematch();
                  } else {
                    _botRematchController?.offerRematch();
                  }
                },
                onAcceptRematch: () {
                  if (_isOnline && !ensureNetworkConnected(context, ref)) return;
                  if (!_ensureEnergyAvailable(isFriendly)) return;
                  if (_isOnline) {
                    _onlineSession?.acceptRematch();
                  }
                },
                onDeclineRematch: () {
                  if (_isOnline) {
                    _onlineSession?.declineRematch();
                  } else {
                    _botRematchController?.declineRematch();
                  }
                },
                onGoHome: () {
                  _leaveRematchIfOnline();
                  Navigator.of(context).popUntil((route) => route.isFirst);
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
    ),
  );
},
),
),
);

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final body = disableAnimations
        ? content
        : FadeTransition(
            opacity: _fadeAnim,
            child: content,
          );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _leaveRematchIfOnline();
        }
      },
      child: body,
    );
  }

  Widget _buildRematchActionArea({
    required RematchState rematchState,
    required String opponentDisplayName,
    required VoidCallback onOfferRematch,
    required VoidCallback onAcceptRematch,
    required VoidCallback onDeclineRematch,
    required VoidCallback onGoHome,
  }) {
    if (rematchState is RematchIdle) {
      return PrimaryButton(
        key: const Key('match_end_rematch_button'),
        text: AppStrings.rematchAction,
        onPressed: onOfferRematch,
      );
    }

    if (rematchState is RematchPendingSent) {
      return PrimaryButton(
        key: const Key('match_end_rematch_waiting_button'),
        text: AppStrings.rematchWaiting(rematchState.secondsRemaining),
        onPressed: null,
      );
    }

    if (rematchState is RematchPendingReceived) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppStrings.rematchOfferedBy(opponentDisplayName),
                style: AppTextStyles.secondaryText.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  key: const Key('match_end_rematch_decline_button'),
                  text: AppStrings.rematchDecline,
                  onPressed: onDeclineRematch,
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: PrimaryButton(
                  key: const Key('match_end_rematch_accept_button'),
                  text: AppStrings.rematchAccept(rematchState.secondsRemaining),
                  onPressed: onAcceptRematch,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (rematchState is RematchStarting || rematchState is RematchMatched) {
      return const PrimaryButton(
        key: Key('match_end_rematch_starting_button'),
        text: AppStrings.rematchStarting,
        onPressed: null,
      );
    }

    // Terminal veya unavailable durumları
    final String? infoText;
    final Color infoColor;

    if (rematchState is RematchDeclined) {
      infoText = AppStrings.rematchDeclined;
      infoColor = AppColors.muted;
    } else if (rematchState is RematchExpired) {
      infoText = AppStrings.rematchExpired;
      infoColor = AppColors.muted;
    } else if (rematchState is RematchOpponentLeft) {
      infoText = AppStrings.rematchOpponentLeft;
      infoColor = AppColors.muted;
    } else if (rematchState is RematchClosed) {
      infoText = AppStrings.rematchUnavailable;
      infoColor = AppColors.muted;
    } else if (rematchState is RematchError) {
      infoColor = AppColors.dangerText;
      switch (rematchState.code) {
        case RematchErrorCode.noEnergy:
          infoText = AppStrings.rematchNoEnergy;
        case RematchErrorCode.opponentNoEnergy:
          infoText = AppStrings.rematchOpponentNoEnergy;
        case RematchErrorCode.blocked:
        case RematchErrorCode.accountDeleted:
        case RematchErrorCode.notAvailable:
        case RematchErrorCode.unavailable:
        case RematchErrorCode.unknown:
          infoText = AppStrings.rematchUnavailable;
      }
    } else {
      // RematchUnavailable: üstte bilgi metni gösterilmez, sadece Ana Sayfa
      infoText = null;
      infoColor = AppColors.muted;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (infoText != null) ...[
          Semantics(
            container: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                infoText,
                style: AppTextStyles.secondaryText.copyWith(
                  color: infoColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
        ],
        PrimaryButton(
          key: const Key('match_end_home_button'),
          text: AppStrings.homeAction,
          onPressed: onGoHome,
        ),
      ],
    );
  }
}

