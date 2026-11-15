import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../friend_match/presentation/friend_reveal_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../../store/presentation/widgets/energy_depleted_bottom_sheet.dart';
import '../application/match_requests_notifier.dart';
import '../application/match_requests_providers.dart';
import '../application/presence_controller.dart';
import '../domain/match_request_models.dart';
import '../domain/match_request_reducer.dart';
import 'widgets/incoming_match_request_banner.dart';
import 'widgets/match_request_toast.dart';
import 'widgets/outgoing_match_request_chip.dart';

/// Tüm uygulama genelinde kök Navigator'ı kontrol eden anahtar.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigatorKey');

/// MaterialApp.builder katmanında Navigator'ın üstünde yer alan global katman.
///
/// Görevleri:
/// 1. Gelen maç/rövanş isteği bildirim bandı (IncomingMatchRequestBanner)
/// 2. Giden istek bekleme çipi (OutgoingMatchRequestChip)
/// 3. Geri bildirim tostları (MatchRequestToastWidget)
/// 4. Tek seferlik hata ve sonuç tüketimi (one-shot feedback)
/// 5. Eşleşme tamamlandığında temiz global navigasyon (MatchedEvent -> FriendMatchRevealScreen)
class GlobalMatchRequestOverlay extends ConsumerStatefulWidget {
  final Widget child;
  final Duration? revealDurationForTesting;

  const GlobalMatchRequestOverlay({
    super.key,
    required this.child,
    this.revealDurationForTesting,
  });

  @override
  ConsumerState<GlobalMatchRequestOverlay> createState() =>
      _GlobalMatchRequestOverlayState();
}

class _GlobalMatchRequestOverlayState
    extends ConsumerState<GlobalMatchRequestOverlay> {
  String? _lastNavigatedMatchId;
  bool _isAccepting = false;
  MatchRequestToastState? _currentToast;
  Timer? _toastDismissTimer;

  @override
  void dispose() {
    _toastDismissTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message, {bool isDanger = false}) {
    _toastDismissTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _currentToast = MatchRequestToastState(
        message: message,
        isDanger: isDanger,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    });
    _toastDismissTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        setState(() {
          _currentToast = null;
        });
      }
    });
  }

  void _dismissToast() {
    _toastDismissTimer?.cancel();
    if (mounted) {
      setState(() {
        _currentToast = null;
      });
    }
  }

  void _handleMatchedEvent(MatchedEvent event) {
    if (_lastNavigatedMatchId == event.matchId) {
      return; // Aynı maç için mükerrer tetikleme önleme
    }
    _lastNavigatedMatchId = event.matchId;

    // 1. Klavyeyi kapat
    FocusManager.instance.primaryFocus?.unfocus();

    final navContext = rootNavigatorKey.currentContext;
    final navState = rootNavigatorKey.currentState;
    if (navState == null || navContext == null) return;

    // 2. Açık dialog veya alt sayfaları ve stale maç ekranlarını temizle, FriendMatchRevealScreen aç
    navState.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => FriendMatchRevealScreen(
          matchId: event.matchId,
          opponentName: event.opponentName,
          opponentFrame: event.opponentFrame,
          opponentUid: event.opponentUid,
          isHost: true,
          isFriendly: event.isFriendly,
          revealDuration: widget.revealDurationForTesting,
        ),
      ),
      (route) => route.isFirst,
    );

    // Rankli maçlarda arka planda profili senkronize et
    if (!event.isFriendly) {
      unawaited(ref.read(profileProvider.notifier).syncWithServer());
    }
  }

  void _handleEndStatus(MatchRequestEndStatusInfo endStatus) {
    if (endStatus.isOutgoing) {
      if (endStatus.status == MatchRequestEndStatus.declined) {
        _showToast(AppStrings.matchRequestDeclinedToast, isDanger: true);
      } else if (endStatus.status == MatchRequestEndStatus.expired) {
        _showToast(AppStrings.matchRequestExpiredToast, isDanger: false);
      }
      // Kullanıcı kendisi iptal ettiğinde (cancelled) toast gösterilmez
    }
    // Alıcı için: İstek zaman aşımına uğradıysa veya karşı taraf iptal ettiyse banner sessizce kapanır.
    ref.read(matchRequestsProvider.notifier).clearLastEndStatus();
  }

  void _handleError(MatchRequestErrorInfo error) {
    final wasAccepting = _isAccepting;
    _isAccepting = false;

    switch (error.code) {
      case MatchRequestErrorCode.noEnergy:
        final profile = ref.read(profileProvider);
        final energy = profile.energy;
        final navContext = rootNavigatorKey.currentContext;
        if (energy != null && navContext != null) {
          showModalBottomSheet<void>(
            context: navContext,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => EnergyDepletedBottomSheet(
              energy: energy,
              userCoins: profile.coins,
              serverNowMs: profile.serverNowMs,
            ),
          );
        }
        break;

      case MatchRequestErrorCode.unavailable:
        if (wasAccepting) {
          _showToast(
            AppStrings.matchRequestUnavailableForAcceptToast,
            isDanger: false,
          );
        } else {
          _showToast(
            AppStrings.matchRequestUnavailableToast,
            isDanger: false,
          );
        }
        break;

      case MatchRequestErrorCode.cooldownActive:
        final sec = error.retryAfterSec ?? 45;
        _showToast(
          AppStrings.matchRequestCooldownToast(sec),
          isDanger: false,
        );
        break;

      case MatchRequestErrorCode.rateLimited:
        _showToast(
          AppStrings.matchRequestRateLimitedToast,
          isDanger: false,
        );
        break;

      case MatchRequestErrorCode.opponentNoEnergy:
        _showToast(
          AppStrings.matchRequestOpponentNoEnergyToast,
          isDanger: false,
        );
        break;

      case MatchRequestErrorCode.invalid:
        _showToast(
          AppStrings.matchRequestInvalidToast,
          isDanger: false,
        );
        break;
    }

    ref.read(matchRequestsProvider.notifier).clearLastError();
  }

  @override
  Widget build(BuildContext context) {
    // 1. matched olaylarını dinle
    ref.listen<AsyncValue<MatchedEvent>>(
      matchedEventsProvider,
      (previous, next) {
        next.whenData(_handleMatchedEvent);
      },
    );

    // 2. Maç istekleri durumunu ve tek seferlik olayları dinle
    ref.listen<MatchRequestsState>(
      matchRequestsProvider,
      (previous, current) {
        if (current.incoming == null) {
          _isAccepting = false;
        }

        if (current.lastEndStatus != null &&
            current.lastEndStatus != previous?.lastEndStatus) {
          _handleEndStatus(current.lastEndStatus!);
        }

        if (current.lastError != null &&
            current.lastError != previous?.lastError) {
          _handleError(current.lastError!);
        }
      },
    );

    // 3. Harici toast isteklerini dinle
    ref.listen<MatchRequestToastState?>(
      matchRequestToastProvider,
      (previous, current) {
        if (current != null) {
          _showToast(current.message, isDanger: current.isDanger);
          ref.read(matchRequestToastProvider.notifier).clear();
        }
      },
    );

    final requestsState = ref.watch(matchRequestsProvider);
    final presenceState = ref.watch(presenceControllerProvider);
    final hasNickname = ref.watch(profileProvider.select((p) => p.hasNickname));

    // Bastırma kuralı: Kullanıcı meşgulken (maçta, kuyrukta, odada vs.) veya onboarding'de banner/çip gösterilmez.
    final isSuppressed = presenceState == UserPresenceState.busy || !hasNickname;

    final incoming = requestsState.incoming;
    final outgoing = requestsState.outgoing;

    final showIncoming = !isSuppressed && incoming != null;
    final showOutgoing = !isSuppressed && outgoing != null;
    final showToast = _currentToast != null;

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final animationDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 250);

    return Stack(
      children: [
        // Katman 0: Ana uygulama ağacı
        widget.child,

        // Katman 1: Üst bildirim alanı (dokunuşları boş alanlarda engellemez)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gelen İstek Bildirim Bandı
                  AnimatedSwitcher(
                    duration: animationDuration,
                    reverseDuration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      if (disableAnimations) return child;
                      final slide = Tween<Offset>(
                        begin: const Offset(0.0, -0.4),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: showIncoming
                        ? KeyedSubtree(
                            key: ValueKey('incoming_${incoming.id}'),
                            child: IncomingMatchRequestBanner(
                              request: incoming,
                              isAccepting: _isAccepting,
                              onAccept: () {
                                setState(() {
                                  _isAccepting = true;
                                });
                                ref
                                    .read(matchRequestsProvider.notifier)
                                    .accept(incoming.id);
                              },
                              onDecline: () {
                                ref
                                    .read(matchRequestsProvider.notifier)
                                    .decline(incoming.id);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  if (showIncoming && (showOutgoing || showToast))
                    const SizedBox(height: 8),

                  // Giden İstek Bilgi Çipi
                  AnimatedSwitcher(
                    duration: animationDuration,
                    reverseDuration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      if (disableAnimations) return child;
                      final slide = Tween<Offset>(
                        begin: const Offset(0.0, -0.3),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: showOutgoing
                        ? Center(
                            key: ValueKey('outgoing_${outgoing.id}'),
                            child: OutgoingMatchRequestChip(
                              request: outgoing,
                              onCancel: () {
                                ref
                                    .read(matchRequestsProvider.notifier)
                                    .cancel(outgoing.id);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  if (showOutgoing && showToast) const SizedBox(height: 8),

                  // Geri Bildirim Tostu
                  AnimatedSwitcher(
                    duration: animationDuration,
                    reverseDuration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      if (disableAnimations) return child;
                      final slide = Tween<Offset>(
                        begin: const Offset(0.0, -0.3),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: showToast
                        ? Center(
                            key: ValueKey(
                              'toast_${_currentToast!.timestamp}_${_currentToast!.message}',
                            ),
                            child: MatchRequestToastWidget(
                              message: _currentToast!.message,
                              isDanger: _currentToast!.isDanger,
                              onDismiss: _dismissToast,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
