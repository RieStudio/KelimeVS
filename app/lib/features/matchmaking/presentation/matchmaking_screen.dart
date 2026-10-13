import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/section_label.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/presentation/match_screen.dart';
import '../../online/data/matchmaking_client.dart';

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

  static const List<String> opponentNames = [
    'Ahmet',
    'Zeynep',
    'Mert',
    'Elif',
    'Burak',
    'Can',
    'Selin',
    'Deniz',
    'Mehmet',
    'Ayşe',
  ];

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  late final String _fallbackOpponentName;
  String _opponentName = '';
  String? _matchedMatchId;
  bool _isOnlineMatch = false;
  bool _isOpponentFound = false;
  bool _isCancelled = false;

  MatchmakingClient? _client;
  StreamSubscription<MatchmakingEvent>? _subscription;
  Timer? _searchTimer;
  Timer? _transitionTimer;
  Timer? _dotsTimer;
  int _activeDotIndex = 0;

  @override
  void initState() {
    super.initState();
    final rng = widget.random ?? math.Random();
    _fallbackOpponentName = widget.initialOpponentName ??
        MatchmakingScreen
            .opponentNames[rng.nextInt(MatchmakingScreen.opponentNames.length)];
    _opponentName = _fallbackOpponentName;

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
        widget.matchmakingClient ?? ref.read(matchmakingClientFactoryProvider)();
    _client = client;

    _subscription = client.events.listen((event) {
      if (!mounted || _isCancelled || _isOpponentFound) return;

      if (event is MatchmakingMatched) {
        _isOnlineMatch = true;
        _matchedMatchId = event.matchId;
        _opponentName = event.opponentName.isNotEmpty
            ? event.opponentName
            : _fallbackOpponentName;
        _handleOpponentFound();
      } else if (event is MatchmakingNoOpponent ||
          event is MatchmakingUnavailable ||
          event is MatchmakingFailed) {
        // Sessizce yerel botlu maça düş (hata gösterilmez, bot ibaresi yok)
        _isOnlineMatch = false;
        _matchedMatchId = null;
        _opponentName = _fallbackOpponentName;
        _handleOpponentFound();
      }
    });

    unawaited(client.start(AppStrings.defaultPlayerName));
  }

  void _handleOpponentFound() {
    if (!mounted || _isCancelled || _isOpponentFound) return;
    _dotsTimer?.cancel();
    _dotsTimer = null;

    setState(() {
      _isOpponentFound = true;
    });

    // 800 ms sonra maç ekranına geç ve maçı başlat
    _transitionTimer =
        Timer(const Duration(milliseconds: 800), _navigateToMatch);
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

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MatchScreen(),
        ),
      );

      unawaited(
        ref.read(onlineMatchSessionProvider.notifier).startOnlineMatch(
              matchId: matchId,
              opponentName: oppName,
            ),
      );
    } else {
      ref
          .read(activeMatchSessionModeProvider.notifier)
          .setMode(MatchSessionMode.bot);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MatchScreen(),
        ),
      );

      unawaited(
        ref.read(matchControllerProvider.notifier).startMatch(
              opponentName: oppName,
            ),
      );
    }
  }

  void _cancelAndExit() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelAllTimers();
    _cancelMatchmakingClient();
    if (mounted) {
      Navigator.of(context).pop();
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
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.space12,
          ),
          child: Column(
            children: [
              // 1. Üst Kapat Butonu
              Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.close,
                    semanticLabel: AppStrings.cancel,
                    onTap: _cancelAndExit,
                  ),
                  const Spacer(),
                ],
              ),

              const Spacer(flex: 2),

              // 2. Ortadaki Avatarlar (Sen VS Rakip)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Kendi Avatarım (92 px, primary zemin, beyaz harf)
                  const PlayerAvatar.selfMatch(
                    name: 'S',
                    size: AppDimens.avatarSearch,
                  ),

                  // VS Metni
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space16,
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

                  // Rakip Avatarı
                  if (!_isOpponentFound)
                    const PlayerAvatar.unknown(
                      size: AppDimens.avatarSearch,
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlayerAvatar.opponent(
                          name: _opponentName,
                          size: AppDimens.avatarSearch,
                        ),
                        const SizedBox(height: AppDimens.space6),
                        Text(
                          _opponentName,
                          style: AppTextStyles.playerName.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: AppDimens.space24),

              // 3. Başlık ("Rakip aranıyor…")
              Semantics(
                header: true,
                child: Text(
                  AppStrings.searchingOpponent,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: AppDimens.space6),

              // 4. Alt Yazı ("Birazdan başlıyoruz")
              Text(
                AppStrings.startingSoon,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppDimens.space20),

              // 5. Üç Noktalı Yükleme Göstergesi
              Semantics(
                label: 'Yükleniyor',
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

              const Spacer(flex: 3),

              // 6. İpucu Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimens.space16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppDimens.borderRadiusListCard,
                  border: Border.all(
                    color: AppColors.mint,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel(AppStrings.searchTipTitle),
                    const SizedBox(height: AppDimens.space6),
                    Text(
                      AppStrings.searchTipContent,
                      style: AppTextStyles.bodyText.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimens.space16),

              // 7. Vazgeç Butonu
              SecondaryButton(
                text: AppStrings.cancel,
                onPressed: _cancelAndExit,
              ),

              const SizedBox(height: AppDimens.space12),
            ],
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

