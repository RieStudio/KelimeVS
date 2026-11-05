import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

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
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/avatar_frame_registry.dart';
import '../../../core/widgets/match_tip_card.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/question_preview_card.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../main.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/domain/bot/bot_opponent_names.dart';
import '../../game/domain/models.dart';
import '../../game/presentation/match_screen.dart';
import '../../online/data/matchmaking_client.dart';
import '../../profile/application/profile_notifier.dart';
import '../../profile/domain/energy_state.dart';
import '../domain/match_tip_selector.dart';

/// DESIGN.md Bölüm 7: 2) Eşleşme Bekleme Ekranı
///
/// Ekran 1 (Arama):
/// - Sol üstte kapat butonu.
/// - Ortada: Kendi profilimiz + kullanıcı adımız · "VS" · animasyonlu "?" yer tutucu avatarı.
/// - "Rakip aranıyor…" (Fredoka 30/700) ve 3 noktalı yükleme göstergesi.
/// - Altta: İpucu kartı ve kırmızı "Vazgeç" butonu.
///
/// Ekran 2 (Rakip Bulundu & Soru Önizleme):
/// - Eşleşme olunca avatarlar yukarı kayar.
/// - Kendi avatarımızın altında "Sen", sağda rakip adı ve avatarı.
/// - Ortada: 1. Tur Soru Kartı (kategori önizleme). Online maçta sunucu göndermezse gösterilmez.
/// - Altta: 3.5 sn'de dolan ince, metinsiz ilerleme çubuğu. Kapat ve Vazgeç butonları kilitli.
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

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transitionController;
  late final Animation<double> _transitionAnimation;

  late String _fallbackOpponentName;
  String _opponentName = '';
  String _opponentFrame = 'classic';
  String? _matchedMatchId;
  bool _isOnlineMatch = false;
  bool _isOpponentFound = false;
  bool _isCancelled = false;
  bool _isMatchedLocked = false;

  String? _onlineFirstQuestionText;
  Question? _preselectedBotQuestion;
  List<Question> _localQuestions = const [];

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
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _transitionAnimation = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    );
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

    // Yerel soru havuzunu bot eşleşmesi / çevrimdışı fallback için arka planda hazırla
    _loadLocalQuestions();

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

  Future<void> _loadLocalQuestions() async {
    try {
      final repo = ref.read(questionRepositoryProvider);
      final questions = await repo.loadAll();
      if (!mounted) return;
      _localQuestions = questions;
      if (questions.isNotEmpty && _preselectedBotQuestion == null) {
        final rng = widget.random ?? math.Random();
        final minAnswers = ref.read(matchConfigProvider).minAnswersPerQuestion;
        final eligible =
            questions.where((q) => q.answers.length >= minAnswers).toList();
        final pool = eligible.isNotEmpty ? eligible : questions;
        _preselectedBotQuestion = pool[rng.nextInt(pool.length)];
      }
    } catch (_) {}
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
        _onlineFirstQuestionText = event.firstQuestion?.text;

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
    final remainingSearchMs =
        AppDimens.matchmakingMinSearchDurationMs - elapsedMs;

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

    // Bot maçı için henüz soru seçilmediyse ve havuz yüklendiyse seç
    if (!_isOnlineMatch &&
        _preselectedBotQuestion == null &&
        _localQuestions.isNotEmpty) {
      final rng = widget.random ?? math.Random();
      final minAnswers = ref.read(matchConfigProvider).minAnswersPerQuestion;
      final eligible =
          _localQuestions.where((q) => q.answers.length >= minAnswers).toList();
      final pool = eligible.isNotEmpty ? eligible : _localQuestions;
      _preselectedBotQuestion = pool[rng.nextInt(pool.length)];
    }

    setState(() {
      _isOpponentFound = true;
    });

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      _transitionController.value = 1.0;
    } else {
      _transitionController.forward();
    }

    // Tanıtım süresi (3.5 sn) boyunca rakip, soru kartı ve dolan ilerleme çubuğu gösterilir
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
            .startMatch(
              opponentName: oppName,
              preselectedQuestionId: _preselectedBotQuestion?.id,
              questions: _localQuestions.isNotEmpty ? _localQuestions : null,
            ),
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
    _transitionController.dispose();
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

    final myNickname = ref.watch(profileProvider).nickname?.trim();
    final myDisplayName = (myNickname != null && myNickname.isNotEmpty)
        ? myNickname
        : AppStrings.defaultPlayerName;
    final selfName = _isOpponentFound ? AppStrings.you : myDisplayName;

    // İlk soru kategori metni: Online maçta sunucudan gelmişse, bot maçında yerel seçimden
    final String? categoryText = _isOnlineMatch
        ? _onlineFirstQuestionText
        : _preselectedBotQuestion?.text;
    final bool hasCategory =
        categoryText != null && categoryText.trim().isNotEmpty;

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
              return AnimatedBuilder(
                animation: _transitionAnimation,
                builder: (context, _) {
                  final double anim = _transitionAnimation.value;
                  final textScaler = MediaQuery.textScalerOf(context);
                  final double totalInnerHeight =
                      constraints.maxHeight - (AppDimens.space12 * 2.0);

                  final double cardContentWidth = math.max(
                    100.0,
                    constraints.maxWidth -
                        (AppDimens.screenPaddingHorizontal * 2.0) -
                        (AppDimens.space16 * 2.0) -
                        (AppDimens.borderThin * 2.0),
                  );

                  final sectionPainter = TextPainter(
                    text: TextSpan(
                      text: AppStrings.searchTipTitle
                          .replaceAll('i', 'İ')
                          .replaceAll('ı', 'I')
                          .toUpperCase(),
                      style: AppTextStyles.sectionLabel,
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: textScaler,
                  )..layout(maxWidth: cardContentWidth);

                  final tipPainter = TextPainter(
                    text: TextSpan(
                      text: _tipText,
                      style: AppTextStyles.bodyText.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: textScaler,
                  )..layout(maxWidth: cardContentWidth);

                  final double tipCardHeight = (AppDimens.space16 * 2.0) +
                      (AppDimens.borderThin * 2.0) +
                      sectionPainter.height +
                      AppDimens.space6 +
                      tipPainter.height;

                  final double searchBottomAreaContentHeight = tipCardHeight +
                      AppDimens.space16 +
                      AppDimens.secondaryButtonHeight;
                  final double searchBottomAreaHeight =
                      searchBottomAreaContentHeight + AppDimens.space12;

                  final titlePainter = TextPainter(
                    text: const TextSpan(
                      text: AppStrings.searchingOpponent,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFredoka,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: textScaler,
                  )..layout(
                      maxWidth: constraints.maxWidth -
                          (AppDimens.screenPaddingHorizontal * 2.0),
                    );
                  final double titleHeight = titlePainter.height;

                  const double dotsHeight = 12.0;
                  final double searchGroupHeight =
                      AppDimens.matchmakingAvatarSlotHeight +
                          AppDimens.matchmakingBelowAvatarsGap +
                          titleHeight +
                          AppDimens.space12 +
                          dotsHeight;

                  final double availableMidGap = totalInnerHeight -
                      AppDimens.minTouchTarget -
                      searchBottomAreaHeight;

                  final double searchTopGap = math.max(
                    AppDimens.space8,
                    (availableMidGap - searchGroupHeight) / 2.0,
                  );

                  final double foundAvatarsTopOffset =
                      AppDimens.space8 + titleHeight + AppDimens.space12;
                  final double currentAvatarsTopOffset =
                      lerpDouble(searchTopGap, foundAvatarsTopOffset, anim)!;

                  const double foundBottomAreaContentHeight =
                      14.0 + (AppDimens.space16 * 2.0);
                  final double currentBottomAreaHeight = lerpDouble(
                    searchBottomAreaContentHeight,
                    foundBottomAreaContentHeight,
                    anim,
                  )!;

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.screenPaddingHorizontal,
                            vertical: AppDimens.space12,
                          ),
                          child: Column(
                            children: [
                              // 1. Üst Kapat Butonu (Aramada aktif; Eşleşme kilitlendiğinde veya tanıtımda gizli)
                              SizedBox(
                                height: AppDimens.minTouchTarget,
                                child: Row(
                                  children: [
                                    if (!_isOpponentFound)
                                      AnimatedOpacity(
                                        duration:
                                            const Duration(milliseconds: 200),
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

                              // Dinamik yukarı alan: Aramada dikey ortalama boşluğu, bulundu durumunda ise üstte "Rakip bulundu!" başlığı + boşluk
                              SizedBox(
                                height: currentAvatarsTopOffset,
                                child: Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    if (_isOpponentFound)
                                      Positioned(
                                        top: AppDimens.space8,
                                        left: 0,
                                        right: 0,
                                        child: Opacity(
                                          opacity: ((anim - 0.2) / 0.8)
                                              .clamp(0.0, 1.0),
                                          child: Semantics(
                                            header: true,
                                            child: const Text(
                                              AppStrings.opponentFound,
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFredoka,
                                                fontSize: 30,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // 2. Ortadaki Avatarlar + Arama Başlığı ve Noktaları
                              RepaintBoundary(
                                key: const ValueKey('matchmaking_group'),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RepaintBoundary(
                                      key: const ValueKey(
                                          'matchmaking_avatars_group'),
                                      child: () {
                                        final avatarSize =
                                            AppDimens.avatarSearch;
                                        final avatarSlotSize =
                                            VisualFrameRegistry.maxFrameSizeFor(
                                          avatarSize,
                                        );
                                        final avatarBottomInSlot =
                                            (avatarSlotSize + avatarSize) / 2.0;

                                        final selfFrame = ref
                                            .watch(profileProvider)
                                            .equippedFrame;
                                        final selfOverflow =
                                            VisualFrameRegistry
                                                .getFrameOverflow(
                                          avatarSize: avatarSize,
                                          frameId: selfFrame,
                                        );
                                        final oppOverflow = _isOpponentFound
                                            ? VisualFrameRegistry
                                                .getFrameOverflow(
                                                avatarSize: avatarSize,
                                                frameId: _opponentFrame,
                                              )
                                            : 0.0;
                                        final maxOverflow =
                                            math.max(selfOverflow, oppOverflow);
                                        final nameTopOffset =
                                            avatarBottomInSlot +
                                                maxOverflow +
                                                AppDimens.matchmakingNameGap;

                                        final myInitial = (myNickname != null &&
                                                myNickname.isNotEmpty)
                                            ? myNickname
                                            : 'S';

                                        return FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Sol Avatar Yuvası (Kendi avatarımız ve kullanıcı adımız / "Sen")
                                            SizedBox(
                                              width: avatarSlotSize,
                                              height: AppDimens
                                                  .matchmakingAvatarSlotHeight,
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                alignment: Alignment.topCenter,
                                                children: [
                                                  SizedBox(
                                                    width: avatarSlotSize,
                                                    height: avatarSlotSize,
                                                    child: Center(
                                                      child: PlayerAvatar
                                                          .selfMatch(
                                                        name: myInitial,
                                                        frame: selfFrame,
                                                        size: avatarSize,
                                                        includeFramePadding:
                                                            true,
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: nameTopOffset,
                                                    left: 0,
                                                    right: 0,
                                                    child: Text(
                                                      selfName,
                                                      style: AppTextStyles
                                                          .playerName
                                                          .copyWith(
                                                        color: AppColors.ink,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // VS Metni Yuvası (Dikeyde avatar merkezleriyle tam hizalı)
                                            SizedBox(
                                              height: AppDimens
                                                  .matchmakingAvatarSlotHeight,
                                              child: Align(
                                                alignment: Alignment.topCenter,
                                                child: SizedBox(
                                                  height: avatarSlotSize,
                                                  child: Center(
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: AppDimens
                                                            .matchmakingVsGap,
                                                      ),
                                                      child: Text(
                                                        AppStrings.vs,
                                                        style: const TextStyle(
                                                          fontFamily:
                                                              AppTextStyles
                                                                  .fontFredoka,
                                                          fontSize: 26,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: AppColors.ink,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Sağ Avatar Yuvası (Arama durumunda dalga animasyonlu "?", bulundu durumunda rakip)
                                            SizedBox(
                                              width: avatarSlotSize,
                                              height: AppDimens
                                                  .matchmakingAvatarSlotHeight,
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                alignment: Alignment.topCenter,
                                                children: [
                                                  SizedBox(
                                                    width: avatarSlotSize,
                                                    height: avatarSlotSize,
                                                    child: Center(
                                                      child: !_isOpponentFound
                                                          ? _SearchPulseAvatar(
                                                              size: avatarSize,
                                                              animate:
                                                                  !disableAnimations,
                                                            )
                                                          : PlayerAvatar
                                                              .opponent(
                                                              name:
                                                                  _opponentName,
                                                              frame:
                                                                  _opponentFrame,
                                                              size: avatarSize,
                                                              includeFramePadding:
                                                                  true,
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
                                                        style: AppTextStyles
                                                            .playerName
                                                            .copyWith(
                                                          color: AppColors.ink,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }(),
                                  ),

                                    // Arama durumunda avatarların altında başlık ("Rakip aranıyor…") ve noktalar
                                    if (!_isOpponentFound || anim < 1.0)
                                      SizedBox(
                                        height: lerpDouble(
                                          AppDimens
                                                  .matchmakingBelowAvatarsGap +
                                              titleHeight +
                                              AppDimens.space12 +
                                              dotsHeight,
                                          0.0,
                                          anim,
                                        )!,
                                        child: Stack(
                                          alignment: Alignment.topCenter,
                                          children: [
                                            if (!_isOpponentFound ||
                                                anim < 0.5)
                                              Positioned(
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                child: Opacity(
                                                  opacity: _isOpponentFound
                                                      ? (1.0 - anim * 2.0)
                                                          .clamp(0.0, 1.0)
                                                      : 1.0,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const SizedBox(
                                                        height: AppDimens
                                                            .matchmakingBelowAvatarsGap,
                                                      ),
                                                      Semantics(
                                                        header: true,
                                                        child: SizedBox(
                                                          height: titleHeight,
                                                          child: const Center(
                                                            child: Text(
                                                              AppStrings
                                                                  .searchingOpponent,
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    AppTextStyles
                                                                        .fontFredoka,
                                                                fontSize: 30,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: AppColors
                                                                    .ink,
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: AppDimens
                                                              .space12),
                                                      Semantics(
                                                        label: 'Yükleniyor',
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            _buildDot(
                                                                0,
                                                                AppColors
                                                                    .primary,
                                                                disableAnimations),
                                                            const SizedBox(
                                                                width: AppDimens
                                                                    .space10),
                                                            _buildDot(
                                                                1,
                                                                AppColors
                                                                    .bright,
                                                                disableAnimations),
                                                            const SizedBox(
                                                                width: AppDimens
                                                                    .space10),
                                                            _buildDot(
                                                                2,
                                                                AppColors.mint,
                                                                disableAnimations),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Bulundu durumunda avatarlar ile ilerleme çubuğu arasındaki alanın DİKEY ORTASINDA soru kartı + "İlk soru" etiketi
                              if (_isOpponentFound &&
                                  hasCategory &&
                                  anim >= 0.4) ...[
                                const Spacer(flex: 1),
                                Opacity(
                                  opacity: ((anim - 0.4) / 0.6).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: lerpDouble(
                                      0.92,
                                      1.0,
                                      Curves.easeOutBack.transform(
                                        ((anim - 0.4) / 0.6).clamp(0.0, 1.0),
                                      ),
                                    )!,
                                    child: Column(
                                      key: const ValueKey(
                                          'first_question_card_block'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppStrings.firstQuestionLabel,
                                          style: AppTextStyles
                                              .questionPreviewLabel,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(
                                            height: AppDimens.space6),
                                        QuestionPreviewCard(
                                          key: const ValueKey(
                                              'first_question_card'),
                                          categoryText: categoryText,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Spacer(flex: 1),
                              ] else ...[
                                const Spacer(),
                              ],

                              // 6. Alt Bölüm: Arama durumunda İpucu Kartı + Vazgeç Butonu;
                              // Bulundu durumunda ise 3.5 sn'de dolan metinsiz ince ilerleme çubuğu.
                              SizedBox(
                                height: currentBottomAreaHeight,
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  clipBehavior: Clip.none,
                                  children: [
                                    if (!_isOpponentFound || anim < 0.5)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Opacity(
                                          opacity: _isOpponentFound
                                              ? (1.0 - anim * 2.0)
                                                  .clamp(0.0, 1.0)
                                              : 1.0,
                                          child: IgnorePointer(
                                            ignoring: _isOpponentFound ||
                                                _isMatchedLocked,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                MatchTipCard(
                                                  key: const ValueKey(
                                                      'matchmaking_tip_card'),
                                                  tip: _tipText,
                                                ),
                                                const SizedBox(
                                                    height: AppDimens.space16),
                                                AnimatedOpacity(
                                                  duration: const Duration(
                                                      milliseconds: 200),
                                                  opacity: _isMatchedLocked
                                                      ? 0.5
                                                      : 1.0,
                                                  child: SecondaryButton(
                                                    text: AppStrings.cancel,
                                                    backgroundColor:
                                                        AppColors.card,
                                                    textColor: AppColors.danger,
                                                    borderColor:
                                                        AppColors.danger,
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: AppColors
                                                            .dangerShadow,
                                                        offset: Offset(0, 4),
                                                        blurRadius: 0,
                                                      ),
                                                    ],
                                                    onPressed:
                                                        (_isMatchedLocked ||
                                                                _isOpponentFound)
                                                            ? null
                                                            : _cancelAndExit,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_isOpponentFound)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: Opacity(
                                          opacity: ((anim - 0.3) / 0.7)
                                              .clamp(0.0, 1.0),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: AppDimens.space16,
                                            ),
                                            child: AppProgressBar.filling(
                                              key: ValueKey(
                                                  'matchmaking_progress_bar'),
                                              fillDuration: AppDimens
                                                  .matchmakingRevealDuration,
                                              maxWidth: 300,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: AppDimens.space12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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

/// Arama aşamasında rakip "?" avatarının çevresinde hafifçe yayılan halka dalgası.
class _SearchPulseAvatar extends StatefulWidget {
  final double size;
  final bool animate;

  const _SearchPulseAvatar({
    required this.size,
    required this.animate,
  });

  @override
  State<_SearchPulseAvatar> createState() => _SearchPulseAvatarState();
}

class _SearchPulseAvatarState extends State<_SearchPulseAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _SearchPulseAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate || _controller == null) {
      return PlayerAvatar.unknown(
        size: widget.size,
        includeFramePadding: true,
      );
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        final t = _controller!.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            _buildPulseRing(t),
            _buildPulseRing((t + 0.5) % 1.0),
            child!,
          ],
        );
      },
      child: PlayerAvatar.unknown(
        size: widget.size,
        includeFramePadding: true,
      ),
    );
  }

  Widget _buildPulseRing(double progress) {
    final scale = 1.0 + (progress * 0.32);
    final opacity = (1.0 - progress) * 0.28;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withValues(alpha: opacity),
            width: 2.0,
          ),
        ),
      ),
    );
  }
}
