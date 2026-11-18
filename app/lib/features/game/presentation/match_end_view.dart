import 'dart:async';

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
import '../../match_detail/presentation/match_detail_screen.dart';
import '../../match_request/application/match_requests_notifier.dart';
import '../../match_request/application/match_requests_providers.dart';
import '../../match_request/domain/match_request_models.dart';
import '../../match_request/domain/match_request_reducer.dart';
import '../../profile/application/profile_notifier.dart';
import '../../store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import '../application/bot_rematch_controller.dart';
import '../application/match_end_rematch_state.dart';
import '../application/match_history_provider.dart';
import '../application/match_providers.dart';
import '../application/match_session.dart';
import '../domain/history/match_history_entry.dart';

/// DESIGN.md Bölüm 7: 5) Maç Sonu Ekranı
///
/// Sol üstte kapat (ana ekrana döner).
/// Ortada MatchResultIcon (kazandın: match_win.svg, kaybettin: match_lose.svg), başlık,
/// terk notu (varsa), skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı.
/// Altta Rövanş eylem alanı ve "Maç Detayı" (ikincil buton).
class MatchEndView extends ConsumerStatefulWidget {
  const MatchEndView({super.key});

  @override
  ConsumerState<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends ConsumerState<MatchEndView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  BotRematchController? _botRematchController;
  InlineHandledRematchNotifier? _inlineHandledNotifier;
  bool _isOnline = false;
  String? _registeredOpponentUid;

  // Çevrim içi maç sonu durum yönetimi
  MatchEndRematchState? _terminalState;
  bool _hasSentOrAcceptedRematch = false;
  bool _isStarting = false;
  bool _awaitingResponseForSend = false;
  String? _lastActiveRequestId;
  Timer? _countdownTicker;

  /// Rakip adını sanitize eder (ortak [OpponentNameSanitizer] sınıfını kullanır).
  static String _sanitizeOpponentName(String? raw, {String? opponentUid}) =>
      OpponentNameSanitizer.sanitize(raw, opponentUid: opponentUid);

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
    _isOnline =
        ref.read(activeMatchSessionModeProvider) == MatchSessionMode.online;

    if (_isOnline) {
      _inlineHandledNotifier =
          ref.read(inlineHandledRematchOpponentUidProvider.notifier);
      final uiState = ref.read(activeMatchUiStateProvider);
      final oppUid = uiState.lastSavedMatch?.opponentUid;
      if (oppUid != null && oppUid.isNotEmpty && _registeredOpponentUid != oppUid) {
        _registeredOpponentUid = oppUid;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _inlineHandledNotifier?.setUid(oppUid);
          }
        });
      }
    } else if (_botRematchController == null) {
      final uiState = ref.read(activeMatchUiStateProvider);
      final isNormal =
          (uiState.lastSavedMatch?.endReason ?? MatchEndReason.normal) ==
              MatchEndReason.normal;
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
    _countdownTicker?.cancel();
    _countdownTicker = null;
    // Satır içi kayıt sızıntısını önlemek için kesinlikle sıfırla
    if (_registeredOpponentUid != null) {
      final notifier = _inlineHandledNotifier;
      Future.microtask(() => notifier?.clear());
      _registeredOpponentUid = null;
    }
    _botRematchController?.removeListener(_onBotRematchChanged);
    _botRematchController?.dispose();
    _botRematchController = null;
    super.dispose();
  }

  void _startCountdownTickerIfNeeded() {
    if (_countdownTicker != null) return;
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopCountdownTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
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

  MatchEndRematchState _resolveRematchState({
    required bool isEligible,
    required String? opponentUid,
    required MatchRequestsState requestsState,
  }) {
    if (!_isOnline) {
      return _botRematchController?.state ??
          const MatchEndRematchUnavailable();
    }

    if (!isEligible || opponentUid == null || opponentUid.isEmpty) {
      _stopCountdownTicker();
      return const MatchEndRematchUnavailable();
    }

    if (_isStarting) {
      _stopCountdownTicker();
      return const MatchEndRematchStarting();
    }

    if (_terminalState != null) {
      _stopCountdownTicker();
      return _terminalState!;
    }

    // 1. Bu rakipten gelen bir rövanş isteği var mı?
    final incoming = requestsState.incoming;
    if (incoming != null &&
        incoming.origin == MatchRequestOrigin.rematch &&
        incoming.fromUid == opponentUid) {
      _startCountdownTickerIfNeeded();
      _lastActiveRequestId = incoming.id;
      return MatchEndRematchPendingReceived(
        secondsRemaining: incoming.calculateRemainingSeconds(),
        requestId: incoming.id,
      );
    }

    // 2. Bu rakibe gönderilmiş bekleyen bir rövanş isteği var mı?
    final outgoing = requestsState.outgoing;
    if (outgoing != null &&
        outgoing.origin == MatchRequestOrigin.rematch &&
        outgoing.toUid == opponentUid) {
      _startCountdownTickerIfNeeded();
      _lastActiveRequestId = outgoing.id;
      return MatchEndRematchPendingSent(
        secondsRemaining: outgoing.calculateRemainingSeconds(),
        requestId: outgoing.id,
      );
    }

    _stopCountdownTicker();

    // 3. Teklif önceden gönderildi/kabul edildiyse ve artık aktif istek yoksa
    // maç başına tek istek kuralı gereği rövanş butonu tekrar aktif olmaz.
    if (_hasSentOrAcceptedRematch) {
      return const MatchEndRematchUnavailable();
    }

    return const MatchEndRematchIdle();
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
    final opponentUid = lastMatch?.opponentUid;
    final opponentDisplayName =
        _sanitizeOpponentName(rawOpponentName, opponentUid: opponentUid);

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

    // Çevrim içi maç istekleri durum dinleyicisi
    final requestsState = ref.watch(matchRequestsProvider);

    ref.listen<MatchRequestsState>(matchRequestsProvider, (previous, current) {
      if (!_isOnline) return;

      final endStatus = current.lastEndStatus;
      if (endStatus != null && endStatus != previous?.lastEndStatus) {
        if (_lastActiveRequestId != null && endStatus.id == _lastActiveRequestId) {
          if (endStatus.status == MatchRequestEndStatus.declined) {
            setState(() {
              _terminalState = const MatchEndRematchDeclined();
            });
          } else if (endStatus.status == MatchRequestEndStatus.expired) {
            setState(() {
              _terminalState = const MatchEndRematchExpired();
            });
          } else if (endStatus.status == MatchRequestEndStatus.cancelled) {
            setState(() {
              _terminalState = const MatchEndRematchUnavailable();
            });
          }
        }
      }

      final error = current.lastError;
      if (error != null && error != previous?.lastError) {
        if (_awaitingResponseForSend) {
          _awaitingResponseForSend = false;
          if (error.code == MatchRequestErrorCode.noEnergy) {
            _showEnergyDepletedSheet();
            setState(() {
              _terminalState =
                  const MatchEndRematchError(MatchRequestErrorCode.noEnergy);
            });
          } else if (error.code == MatchRequestErrorCode.opponentNoEnergy) {
            setState(() {
              _terminalState =
                  const MatchEndRematchError(MatchRequestErrorCode.opponentNoEnergy);
            });
          } else if (error.code == MatchRequestErrorCode.unavailable ||
              error.code == MatchRequestErrorCode.offline ||
              error.code == MatchRequestErrorCode.requestsDisabled) {
            // Alıcı o an müsait değilse / offline / istekleri kapalıysa tek rövanş hakkı yanmaz, tekrar denenebilir
            _hasSentOrAcceptedRematch = false;
            setState(() {
              _terminalState = MatchEndRematchError(error.code);
            });
          } else if (error.code == MatchRequestErrorCode.cooldownActive) {
            _hasSentOrAcceptedRematch = false;
            setState(() {
              _terminalState = MatchEndRematchError(
                MatchRequestErrorCode.cooldownActive,
                retryAfterSec: error.retryAfterSec,
              );
            });
          } else if (error.code == MatchRequestErrorCode.rateLimited) {
            _hasSentOrAcceptedRematch = false;
            setState(() {
              _terminalState = const MatchEndRematchError(
                MatchRequestErrorCode.rateLimited,
              );
            });
          } else {
            setState(() {
              _terminalState = MatchEndRematchError(error.code);
            });
          }
        }
      }
    });

    final matchId = lastMatch?.matchId;
    final isEligible = uiState.rematchAvailable &&
        opponentUid != null &&
        opponentUid.trim().isNotEmpty;

    final rematchState = _resolveRematchState(
      isEligible: isEligible,
      opponentUid: opponentUid,
      requestsState: requestsState,
    );

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
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst);
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
                          label:
                              'Skor: Sen $myScore, $opponentDisplayName $opponentScore',
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
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * 0.35,
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
                            if (_isOnline &&
                                !ensureNetworkConnected(context, ref)) {
                              return;
                            }
                            if (!_ensureEnergyAvailable(isFriendly)) return;

                            if (_isOnline) {
                              if (opponentUid == null || matchId == null) return;
                              setState(() {
                                _terminalState = null;
                              });
                              _hasSentOrAcceptedRematch = true;
                              _awaitingResponseForSend = true;
                              ref
                                  .read(matchRequestsProvider.notifier)
                                  .sendRematchRequest(
                                    toUid: opponentUid,
                                    matchId: matchId,
                                  );
                            } else {
                              _botRematchController?.offerRematch();
                            }
                          },
                          onCancelRematch: (requestId) {
                            if (_isOnline) {
                              if (requestId != null) {
                                ref
                                    .read(matchRequestsProvider.notifier)
                                    .cancel(requestId);
                              }
                              setState(() {
                                _terminalState =
                                    const MatchEndRematchUnavailable();
                              });
                            } else {
                              _botRematchController?.cancelRematch();
                            }
                          },
                          onAcceptRematch: (requestId) {
                            if (_isOnline &&
                                !ensureNetworkConnected(context, ref)) {
                              return;
                            }
                            if (!_ensureEnergyAvailable(isFriendly)) return;

                            if (_isOnline) {
                              setState(() {
                                _isStarting = true;
                                _hasSentOrAcceptedRematch = true;
                              });
                              ref
                                  .read(matchRequestsProvider.notifier)
                                  .accept(requestId);
                            }
                          },
                          onDeclineRematch: (requestId) {
                            if (_isOnline) {
                              setState(() {
                                _terminalState =
                                    const MatchEndRematchDeclined();
                              });
                              ref
                                  .read(matchRequestsProvider.notifier)
                                  .decline(requestId);
                            } else {
                              _botRematchController?.declineRematch();
                            }
                          },
                          onGoHome: () {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                        ),

                        const SizedBox(height: AppDimens.space12),

                        SecondaryButton(
                          text: AppStrings.matchDetail,
                          onPressed: () async {
                            final last = ref
                                .read(activeMatchUiStateProvider)
                                .lastSavedMatch;
                            if (last != null) {
                              if (context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MatchDetailScreen(match: last),
                                  ),
                                );
                              }
                              return;
                            }

                            // Fallback: geçmişten en son maçı al
                            final recent = await ref
                                .read(matchHistoryRepositoryProvider)
                                .loadRecent();
                            if (recent.isNotEmpty && context.mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MatchDetailScreen(match: recent.first),
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
      child: body,
    );
  }

  Widget _buildRematchActionArea({
    required MatchEndRematchState rematchState,
    required String opponentDisplayName,
    required VoidCallback onOfferRematch,
    required void Function(String? requestId) onCancelRematch,
    required void Function(String requestId) onAcceptRematch,
    required void Function(String requestId) onDeclineRematch,
    required VoidCallback onGoHome,
  }) {
    if (rematchState is MatchEndRematchIdle) {
      return PrimaryButton(
        key: const Key('match_end_rematch_button'),
        text: AppStrings.rematchAction,
        onPressed: onOfferRematch,
      );
    }

    if (rematchState is MatchEndRematchPendingSent) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                key: const Key('match_end_rematch_waiting_text'),
                AppStrings.rematchWaiting(rematchState.secondsRemaining),
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
          SecondaryButton.danger(
            key: const Key('match_end_rematch_cancel_button'),
            text: AppStrings.matchRequestCancel,
            onPressed: () => onCancelRematch(rematchState.requestId),
          ),
        ],
      );
    }

    if (rematchState is MatchEndRematchPendingReceived) {
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
                  onPressed: () => onDeclineRematch(rematchState.requestId),
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: PrimaryButton(
                  key: const Key('match_end_rematch_accept_button'),
                  text: AppStrings.rematchAccept(rematchState.secondsRemaining),
                  onPressed: () => onAcceptRematch(rematchState.requestId),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (rematchState is MatchEndRematchStarting) {
      return const PrimaryButton(
        key: Key('match_end_rematch_starting_button'),
        text: AppStrings.rematchStarting,
        onPressed: null,
      );
    }

    // Terminal veya unavailable durumları
    final String? infoText;
    final Color infoColor;

    if (rematchState is MatchEndRematchDeclined) {
      infoText = AppStrings.rematchDeclined;
      // "Rövanş reddedildi" metni KIRMIZI (AppColors.dangerText)
      infoColor = AppColors.dangerText;
    } else if (rematchState is MatchEndRematchExpired) {
      infoText = AppStrings.rematchExpired;
      infoColor = AppColors.muted;
    } else if (rematchState is MatchEndRematchUnavailableReason) {
      infoText = AppStrings.rematchUnavailable;
      infoColor = AppColors.muted;
    } else if (rematchState is MatchEndRematchError) {
      switch (rematchState.code) {
        case MatchRequestErrorCode.noEnergy:
          infoText = AppStrings.rematchNoEnergy;
          infoColor = AppColors.dangerText;
        case MatchRequestErrorCode.opponentNoEnergy:
          infoText = AppStrings.rematchOpponentNoEnergy;
          infoColor = AppColors.dangerText;
        case MatchRequestErrorCode.cooldownActive:
          final sec = rematchState.retryAfterSec ?? 45;
          infoText = AppStrings.matchRequestCooldownToast(sec);
          infoColor = AppColors.muted;
        case MatchRequestErrorCode.rateLimited:
          infoText = AppStrings.matchRequestRateLimitedToast;
          infoColor = AppColors.muted;
        case MatchRequestErrorCode.offline:
          infoText = AppStrings.rematchOffline;
          infoColor = AppColors.muted;
        case MatchRequestErrorCode.requestsDisabled:
          infoText = AppStrings.rematchRequestsDisabled;
          infoColor = AppColors.muted;
        case MatchRequestErrorCode.unavailable:
        case MatchRequestErrorCode.invalid:
          infoText = AppStrings.rematchUnavailable;
          infoColor = AppColors.muted;
      }
    } else {
      // MatchEndRematchUnavailable: üstte bilgi metni gösterilmez, sadece Ana Sayfa
      infoText = null;
      infoColor = AppColors.muted;
    }

    final bool canRetry = rematchState is MatchEndRematchUnavailableReason ||
        (rematchState is MatchEndRematchError &&
            (rematchState.code == MatchRequestErrorCode.offline ||
                rematchState.code == MatchRequestErrorCode.requestsDisabled ||
                rematchState.code == MatchRequestErrorCode.unavailable ||
                rematchState.code == MatchRequestErrorCode.cooldownActive ||
                rematchState.code == MatchRequestErrorCode.rateLimited));

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
        if (canRetry)
          PrimaryButton(
            key: const Key('match_end_rematch_retry_button'),
            text: AppStrings.rematchAction,
            onPressed: onOfferRematch,
          )
        else
          PrimaryButton(
            key: const Key('match_end_home_button'),
            text: AppStrings.homeAction,
            onPressed: onGoHome,
          ),
      ],
    );
  }
}
