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
import '../../game/presentation/match_screen.dart';

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

  const MatchmakingScreen({
    super.key,
    this.searchDuration,
    this.initialOpponentName,
    this.random,
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
  late final String _opponentName;
  bool _isOpponentFound = false;

  Timer? _searchTimer;
  Timer? _transitionTimer;
  Timer? _dotsTimer;
  int _activeDotIndex = 0;

  @override
  void initState() {
    super.initState();
    final rng = widget.random ?? math.Random();
    _opponentName = widget.initialOpponentName ??
        MatchmakingScreen.opponentNames[rng.nextInt(MatchmakingScreen.opponentNames.length)];

    final duration = widget.searchDuration ??
        Duration(milliseconds: 2500 + rng.nextInt(2000));

    // Üç noktanın periyodik animasyonu
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) {
        setState(() {
          _activeDotIndex = (_activeDotIndex + 1) % 3;
        });
      }
    });

    // Sahte arama süresi
    _searchTimer = Timer(duration, _handleOpponentFound);
  }

  void _handleOpponentFound() {
    if (!mounted) return;
    _dotsTimer?.cancel();
    _dotsTimer = null;

    setState(() {
      _isOpponentFound = true;
    });

    // 800 ms sonra maç ekranına geç ve maçı başlat
    _transitionTimer = Timer(const Duration(milliseconds: 800), _navigateToMatch);
  }

  void _navigateToMatch() {
    if (!mounted) return;
    _cancelAllTimers();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const MatchScreen(),
      ),
    );

    ref.read(matchControllerProvider.notifier).startMatch(
      opponentName: _opponentName,
    );
  }

  void _cancelAndExit() {
    _cancelAllTimers();
    if (mounted) {
      Navigator.of(context).pop();
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

