import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_status_provider.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/bot_frame_resolver.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/avatar_frame_registry.dart';
import '../../../core/widgets/match_tip_card.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../main.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/domain/bot/bot_opponent_names.dart';
import '../../game/presentation/match_screen.dart';
import '../../online/data/matchmaking_client.dart';
import '../../profile/application/profile_notifier.dart';
import '../../profile/domain/energy_state.dart';
import '../domain/match_tip_selector.dart';

/// DESIGN.md Bölüm 7: 2) Eşleşme Bekleme Ekranı
///
/// Sol üstte kapat.
/// Ortada: kendi avatarın (92) · "VS" · kesik çizgili "?" avatarı.
/// "Rakip aranıyor…" (Fredoka 30/700), altında "Birazdan başlıyoruz".
/// Üç noktalı yükleme göstergesi (primary/bright/mint, sırayla yanıp söner).
/// Altta ipucu kartı ve "Vazgeç" ikincil butonu.
class MatchmakingScreen extends ConsumerStatefulWidget {
  final Duration? searchDuration;
  final String? initialOpponentName;
  final math.Random? random;
  final bool forceBotFallback;
  final MatchmakingClient? matchmakingClient;

  const MatchmakingScreen({
    super.key,
    this.searchDuration,
    this.initialOpponentName,
    this.random,
    this.forceBotFallback = false,
    this.matchmakingClient,
  });

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  late String _fallbackOpponentName;
  String _opponentName = '';
  String _opponentFrame = 'classic';
  String? _matchedMatchId;
  bool _isOnlineMatch = false;
  bool _isOpponentFound = false;
  bool _isCancelled = false;
  bool _isMatchedLocked = false;

  MatchmakingClient? _client;
  StreamSubscription<MatchmakingEvent>? _subscription;
  Timer? _searchTimer;
  Timer? _minSearchTimer;
  Timer? _transitionTimer;
  Timer? _dotsTimer;
  int _activeDotIndex = 0;
  late final BannerSuppressionNotifier _suppressionNotifier;
  late final String _tipText;
  Stopwatch? _searchStopwatch;

  @override
  void initState() {
    super.initState();
    _searchStopwatch = Stopwatch()..start();
    _tipText = MatchTipSelector.selectTip(random: widget.random);
    _suppressionNotifier = ref.read(bannerSuppressionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressionNotifier.suppress();
      }
    });
    final myNickname = ref.read(profileProvider).nickname?.trim();
    final rng = widget.random ?? math.Random();
    _fallbackOpponentName = widget.initialOpponentName ??
        BotOpponentNames.pickOpponentName(
          random: rng,
          excludeName: myNickname,
        );
    _opponentName = _fallbackOpponentName;

    // Son karşılaşılan bot adlarını asenkron yükleyip henüz eşleşme olmadan havuzdan dışla
    if (widget.initialOpponentName == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted || _isOpponentFound || _isOnlineMatch) return;
        final recent = BotOpponentNames.loadRecentNames(prefs);
        final refinedName = BotOpponentNames.pickOpponentName(
          random: rng,
          recentNames: recent,
          excludeName: myNickname,
        );
        setState(() {
          _fallbackOpponentName = refinedName;
          _opponentName = refinedName;
          _opponentFrame = BotFrameResolver.resolve(refinedName);
        });
      }).catchError((_) {});
    }

    // Üç noktanın periyodik animasyonu
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) {
        setState(() {
          _activeDotIndex = (_activeDotIndex + 1) % 3;
        });
      }
    });

    final onlineEnabled = ref.read(onlineMatchmakingEnabledProvider);
    if (!onlineEnabled || widget.forceBotFallback) {
      // Devre kesici kapalıysa veya voided sonrası doğrudan botlu maça düşülüyorsa
      _isOnlineMatch = false;
      _matchedMatchId = null;
      _opponentFrame = BotFrameResolver.resolve(_opponentName);
      _searchTimer = Timer(
        widget.searchDuration ?? Duration.zero,
        _handleOpponentFound,
      );
    } else {
      _startOnlineMatchmaking();
    }
  }

  void _startOnlineMatchmaking() {
    final client =
        widget.matchmakingClient ??
        ref.read(matchmakingClientFactoryProvider)();
    _client = client;

    _subscription = client.events.listen((event) {
      if (!mounted || _isCancelled || _isOpponentFound) return;

      if (event is MatchmakingMatched) {
        _isOnlineMatch = true;
        _isMatchedLocked = true;
        _matchedMatchId = event.matchId;
        _opponentName = event.opponentName.isNotEmpty
            ? event.opponentName
            : _fallbackOpponentName;
        _opponentFrame = event.opponentFrame;

        // DESIGN.md 9b: Sunucu matched mesajıyla güncel enerjiyi bildirdiğinde anında güncelle
        if (event.energy != null) {
          final currentEnergy = ref.read(profileProvider).energy;
          final updatedEnergy = (currentEnergy ??
                  EnergyState(
                    enabled: true,
                    current: event.energy!.current,
                    max: event.energy!.max,
                  ))
              .copyWith(
            enabled: true,
            current: event.energy!.current,
            max: event.energy!.max,
            nextEnergyAtMs: event.energy!.nextEnergyAtMs,
          );
          ref
              .read(profileProvider.notifier)
              .updateEnergy(updatedEnergy, event.serverNowMs);
        }

        setState(() {});
        _handleOpponentFound();
      } else if (event is MatchmakingNoEnergy) {
        _cancelAllTimers();
        _cancelMatchmakingClient();
        if (mounted) {
          Navigator.of(context).pop();
          final currentProfile = ref.read(profileProvider);
          if (currentProfile.energy != null) {
            ref
                .read(profileProvider.notifier)
                .updateEnergy(currentProfile.energy!.copyWith(current: 0));
          }
        }
      } else if (event is MatchmakingNoOpponent ||
          event is MatchmakingUnavailable ||
          event is MatchmakingFailed) {
        // Sessizce yerel botlu maça düş (hata gösterilmez, bot ibaresi yok)
        _isOnlineMatch = false;
        _matchedMatchId = null;
        _opponentName = _fallbackOpponentName;
        _opponentFrame = BotFrameResolver.resolve(_opponentName);
        _handleOpponentFound();
      }
    });

    final myNickname = ref.read(profileProvider).nickname?.trim();
    final nameToSend = (myNickname != null && myNickname.isNotEmpty)
        ? myNickname
        : AppStrings.defaultPlayerName;

    unawaited(client.start(nameToSend));
  }

  void _handleOpponentFound() {
    if (!mounted || _isCancelled || _isOpponentFound) return;

    // Minimum arama süresi kontrolü: 1.5 sn dolmadıysa kalan süre kadar bekle
    final elapsedMs = _searchStopwatch?.elapsedMilliseconds ?? 0;
    final remainingSearchMs = AppDimens.matchmakingMinSearchDurationMs - elapsedMs;

    if (remainingSearchMs > 0) {
      _minSearchTimer?.cancel();
      _minSearchTimer = Timer(Duration(milliseconds: remainingSearchMs), () {
        if (!mounted || _isCancelled || _isOpponentFound) return;
        _startReveal();
      });
      return;
    }

    _startReveal();
  }

  void _startReveal() {
    _dotsTimer?.cancel();
    _dotsTimer = null;

    setState(() {
      _isOpponentFound = true;
    });

    // Tanıtım süresi boyunca rakip ve "Rakip bulundu!" gösterilir, sonra maça geçilir
    _transitionTimer = Timer(
      AppDimens.matchmakingRevealDuration,
      _navigateToMatch,
    );
  }

  void _navigateToMatch() {
    if (!mounted || _isCancelled) return;
    _cancelAllTimers();

    final isOnline = _isOnlineMatch && _matchedMatchId != null;
    final matchId = _matchedMatchId;
    final oppName = _opponentName;

    if (isOnline && matchId != null) {
      ref
          .read(activeMatchSessionModeProvider.notifier)
          .setMode(MatchSessionMode.online);

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MatchScreen()));

      unawaited(
        ref
            .read(onlineMatchSessionProvider.notifier)
            .startOnlineMatch(
              matchId: matchId,
              opponentName: oppName,
              opponentFrame: _opponentFrame,
            ),
      );
    } else {
      ref
          .read(activeMatchSessionModeProvider.notifier)
          .setMode(MatchSessionMode.bot);

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MatchScreen()));

      unawaited(
        ref
            .read(matchControllerProvider.notifier)
            .startMatch(opponentName: oppName),
      );
    }
  }

  void _cancelAndExit() {
    if (_isCancelled || _isOpponentFound || _isMatchedLocked) return;
    _isCancelled = true;
    _cancelAllTimers();
    _cancelMatchmakingClient();
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    }
  }

  void _cancelMatchmakingClient() {
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(client.cancel());
    }
  }

  void _cancelAllTimers() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _minSearchTimer?.cancel();
    _minSearchTimer = null;
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  @override
  void dispose() {
    _suppressionNotifier.unsuppress();
    _cancelAllTimers();
    if (!_isOpponentFound) {
      _cancelMatchmakingClient();
    } else {
      final sub = _subscription;
      _subscription = null;
      if (sub != null) {
        unawaited(sub.cancel());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isOpponentFound || _isMatchedLocked) return;
        _cancelAndExit();
      },
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
              // 1. Üst Kapat Butonu (Tanıtım anında veya çevrimiçi eşleşmede kilitlendiğinde devre dışı kalır)
              SizedBox(
                height: AppDimens.minTouchTarget,
                child: Row(
                  children: [
                    if (!_isOpponentFound)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isMatchedLocked ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: _isMatchedLocked,
                          child: AppIconButton(
                            icon: AppIcons.close,
                            semanticLabel: AppStrings.cancel,
                            onTap: _cancelAndExit,
                          ),
                        ),
                      )
                    else
                      const SizedBox(
                        width: AppDimens.minTouchTarget,
                        height: AppDimens.minTouchTarget,
                      ),
                    const Spacer(),
                  ],
                ),
              ),

              const SizedBox(height: AppDimens.space24),

              // 2. Ortadaki Avatarlar (Sen VS Rakip)
              // Her iki taraf için sabit genişlikte yuva (en geniş çerçeve olan Sarmaşık / vine boyutu)
              () {
                final avatarSize = AppDimens.avatarSearch;
                final avatarSlotSize = VisualFrameRegistry.maxFrameSizeFor(
                  avatarSize,
                );
                final avatarBottomInSlot = (avatarSlotSize + avatarSize) / 2.0;

                final selfFrame = ref.watch(profileProvider).equippedFrame;
                final selfOverflow = VisualFrameRegistry.getFrameOverflow(
                  avatarSize: avatarSize,
                  frameId: selfFrame,
                );
                final oppOverflow = _isOpponentFound
                    ? VisualFrameRegistry.getFrameOverflow(
                        avatarSize: avatarSize,
                        frameId: _opponentFrame,
                      )
                    : 0.0;
                final maxOverflow = math.max(selfOverflow, oppOverflow);
                final nameTopOffset = avatarBottomInSlot +
                    maxOverflow +
                    AppDimens.matchmakingNameGap;

                final myNickname = ref.watch(profileProvider).nickname?.trim();
                final myInitial = (myNickname != null && myNickname.isNotEmpty)
                    ? myNickname
                    : 'S';

                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sol Avatar Yuvası (Kendi avatarım ve "Sen")
                      SizedBox(
                        width: avatarSlotSize,
                        height: AppDimens.matchmakingAvatarSlotHeight,
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
                            if (_isOpponentFound)
                              Positioned(
                                top: nameTopOffset,
                                left: 0,
                                right: 0,
                                child: Text(
                                  AppStrings.you,
                                  style: AppTextStyles.playerName.copyWith(
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

                      // VS Metni Yuvası (Dikeyde avatar merkezleriyle tam hizalı)
                      SizedBox(
                        height: AppDimens.matchmakingAvatarSlotHeight,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            height: avatarSlotSize,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.matchmakingVsGap,
                                ),
                                child: Text(
                                  AppStrings.vs,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFredoka,
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

                      // Sağ Avatar Yuvası (Rakip avatarı ve adı)
                      SizedBox(
                        width: avatarSlotSize,
                        height: AppDimens.matchmakingAvatarSlotHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.topCenter,
                          children: [
                            SizedBox(
                              width: avatarSlotSize,
                              height: avatarSlotSize,
                              child: Center(
                                child: !_isOpponentFound
                                    ? const PlayerAvatar.unknown(
                                        size: AppDimens.avatarSearch,
                                        includeFramePadding: true,
                                      )
                                    : PlayerAvatar.opponent(
                                        name: _opponentName,
                                        frame: _opponentFrame,
                                        size: avatarSize,
                                        includeFramePadding: true,
                                      ),
                              ),
                            ),
                            if (_isOpponentFound)
                              Positioned(
                                top: nameTopOffset,
                                left: 0,
                                right: 0,
                                child: Text(
                                  _opponentName,
                                  style: AppTextStyles.playerName.copyWith(
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
                );
              }(),

              const SizedBox(height: AppDimens.matchmakingBelowAvatarsGap),

              // 3. Başlık ("Rakip aranıyor…" -> "Rakip bulundu!")
              Semantics(
                header: true,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: Text(
                    _isOpponentFound
                        ? AppStrings.opponentFound
                        : AppStrings.searchingOpponent,
                    key: ValueKey<bool>(_isOpponentFound),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: AppDimens.space20),

              // 4. Üç Noktalı Yükleme Göstergesi
              Semantics(
                label: 'Yükleniyor',
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isOpponentFound ? 0.0 : 1.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDot(0, AppColors.primary, disableAnimations),
                      const SizedBox(width: AppDimens.space10),
                      _buildDot(1, AppColors.bright, disableAnimations),
                      const SizedBox(width: AppDimens.space10),
                      _buildDot(2, AppColors.mint, disableAnimations),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // 5. İpucu Kartı (Tanıtım anında yumuşak solma ile kaldırılır)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: !_isOpponentFound
                    ? MatchTipCard(
                        key: const ValueKey('matchmaking_tip_card'),
                        tip: _tipText,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('matchmaking_tip_empty'),
                      ),
              ),

              const SizedBox(height: AppDimens.space16),

              // 6. Vazgeç Butonu (Tanıtım anında düzen kaymasını önlemek için aynı boyutta boş kutu bırakılır)
              if (!_isOpponentFound)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isMatchedLocked ? 0.5 : 1.0,
                  child: SecondaryButton(
                    text: AppStrings.cancel,
                    backgroundColor: AppColors.card,
                    textColor: AppColors.dangerDark,
                    borderColor: AppColors.dangerDark,
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.dangerDark,
                        offset: Offset(0, 4),
                        blurRadius: 0,
                      ),
                    ],
                    onPressed: _isMatchedLocked ? null : _cancelAndExit,
                  ),
                )
              else
                const SizedBox(height: AppDimens.secondaryButtonHeight),

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
),
);
}

  Widget _buildDot(int index, Color color, bool disableAnimations) {
    final isActive = index == _activeDotIndex;
    final double scale = disableAnimations ? 1.0 : (isActive ? 1.3 : 0.85);
    final double opacity = disableAnimations ? 1.0 : (isActive ? 1.0 : 0.45);

    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: scale,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: opacity,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
