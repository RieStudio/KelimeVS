import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/presentation/match_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../data/friend_match_client.dart';

/// "Oda Kur" ekranı: 6 haneli kodu üretir, gösterir, paylaşım menüsünü açar
/// ve rakip katıldığında maça yönlendirir.
class FriendHostScreen extends ConsumerStatefulWidget {
  final FriendMatchClient? client;

  const FriendHostScreen({
    super.key,
    this.client,
  });

  @override
  ConsumerState<FriendHostScreen> createState() => _FriendHostScreenState();
}

class _FriendHostScreenState extends ConsumerState<FriendHostScreen>
    with WidgetsBindingObserver {
  late final FriendMatchClient _client;
  StreamSubscription<FriendMatchEvent>? _subscription;

  String? _code;
  int _remainingSeconds = 300; // 5 dakika
  Timer? _countdownTimer;
  Timer? _dotsTimer;
  int _activeDotIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isMatched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = widget.client ?? FriendMatchClient();
    _subscription = _client.events.listen(_handleEvent);

    // Üç nokta animasyonu
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted) {
        setState(() {
          _activeDotIndex = (_activeDotIndex + 1) % 3;
        });
      }
    });

    _initRoom();
  }

  void _initRoom() {
    final profile = ref.read(profileProvider);
    final nickname = (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : null;

    _client.createRoom(name: nickname);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // WhatsApp/Telegram'dan uygulamaya geri dönüldüğünde odaya devam et
    if (state == AppLifecycleState.resumed && _code != null && !_isMatched) {
      _client.resumeRoom(_code!);
    }
  }

  void _startCountdown(int expiresAt) {
    _countdownTimer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffSec = ((expiresAt - now) / 1000).ceil();
    _remainingSeconds = diffSec > 0 ? diffSec : 0;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _showExpiredDialog();
      }
    });
  }

  void _handleEvent(FriendMatchEvent event) {
    if (!mounted) return;

    if (event is FriendMatchRoomCreated) {
      setState(() {
        _isLoading = false;
        _code = event.code;
      });
      _startCountdown(event.expiresAt);
    } else if (event is FriendMatchRoomResumed) {
      setState(() {
        _isLoading = false;
        _code = event.code;
      });
      _startCountdown(event.expiresAt);
    } else if (event is FriendMatchMatched) {
      _onMatched(event.matchId, event.opponentName, event.opponentFrame);
    } else if (event is FriendMatchRoomExpired) {
      _showExpiredDialog();
    } else if (event is FriendMatchFailed) {
      setState(() {
        _isLoading = false;
        _errorMessage = event.message;
      });
    }
  }

  void _onMatched(String matchId, String opponentName, String opponentFrame) {
    if (_isMatched) return;
    _isMatched = true;
    _countdownTimer?.cancel();
    _dotsTimer?.cancel();

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
            opponentName: opponentName,
            opponentFrame: opponentFrame,
            isFriendly: true,
          ),
    );
  }

  void _showExpiredDialog() {
    _countdownTimer?.cancel();
    _dotsTimer?.cancel();

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimens.borderRadiusDialog,
          side: const BorderSide(
            color: AppColors.ink,
            width: AppDimens.borderThick,
          ),
        ),
        title: const Text(
          AppStrings.roomExpiredTitle,
          style: AppTextStyles.cardTitle,
        ),
        content: const Text(
          AppStrings.roomExpiredMessage,
          style: AppTextStyles.bodyText,
        ),
        actions: [
          PrimaryButton(
            text: AppStrings.ok,
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _copyCode() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.codeCopied),
        backgroundColor: AppColors.mint,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareCode() {
    if (_code == null) return;
    final text = AppStrings.friendDuelShareText(_code!);
    Share.share(text);
  }

  void _cancelAndExit() {
    _countdownTimer?.cancel();
    _dotsTimer?.cancel();
    _client.cancelRoom(code: _code);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _dotsTimer?.cancel();
    _subscription?.cancel();
    if (!_isMatched) {
      _client.close();
    }
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isWarningTime = _remainingSeconds <= 60;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.ink),
          onPressed: _cancelAndExit,
        ),
        title: const Text(
          AppStrings.friendDuel,
          style: AppTextStyles.screenTitle,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.space16,
          ),
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: AppDimens.space16),
                      Text(
                        AppStrings.creatingRoom,
                        style: AppTextStyles.bodyText,
                      ),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: AppColors.danger,
                          ),
                          const SizedBox(height: AppDimens.space16),
                          Text(
                            _errorMessage!,
                            style: AppTextStyles.bodyText,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppDimens.space24),
                          SecondaryButton(
                            text: AppStrings.cancel,
                            onPressed: _cancelAndExit,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppDimens.space12),

                        // 1. Davet Kodu Kartı
                        Container(
                          padding: const EdgeInsets.all(AppDimens.space24),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppDimens.borderRadiusListCard,
                            border: Border.all(
                              color: AppColors.ink,
                              width: AppDimens.borderThin,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 4),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                AppStrings.yourInviteCode,
                                style: AppTextStyles.sectionLabel.copyWith(
                                  fontSize: 13,
                                  letterSpacing: 1.2,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: AppDimens.space12),

                              // 6 Haneli Kod
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _code ?? '------',
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontFredoka,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 6,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(width: AppDimens.space12),
                                  IconButton(
                                    key: const Key('copy_invite_code_button'),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      color: AppColors.primary,
                                      size: 26,
                                    ),
                                    tooltip: AppStrings.copyCode,
                                    onPressed: _copyCode,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppDimens.space16),

                              // Geri Sayım Sayacı
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 16,
                                    color: isWarningTime
                                        ? AppColors.danger
                                        : AppColors.muted,
                                  ),
                                  const SizedBox(width: AppDimens.space6),
                                  Text(
                                    '${AppStrings.codeValidity} ${_formatDuration(_remainingSeconds)}',
                                    style: AppTextStyles.bodyText.copyWith(
                                      color: isWarningTime
                                          ? AppColors.danger
                                          : AppColors.muted,
                                      fontWeight: isWarningTime
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppDimens.space20),

                        // 2. "Paylaş" Butonu
                        PrimaryButton(
                          key: const Key('share_invite_code_button'),
                          text: AppStrings.shareCode,
                          isLarge: true,
                          onPressed: _shareCode,
                        ),

                        const Spacer(),

                        // 3. Bekleme Göstergesi ve 3 Nokta
                        Center(
                          child: Column(
                            children: [
                              Text(
                                AppStrings.waitingForOpponent,
                                style: AppTextStyles.bodyText.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: AppDimens.space12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(3, (index) {
                                  final isActive = index == _activeDotIndex;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    width: isActive ? 12 : 8,
                                    height: isActive ? 12 : 8,
                                    decoration: BoxDecoration(
                                      color: index == 0
                                          ? AppColors.primary
                                          : index == 1
                                              ? AppColors.bright
                                              : AppColors.mint,
                                      shape: BoxShape.circle,
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        // 4. "Odayı Kapat" Butonu
                        SecondaryButton(
                          text: AppStrings.cancelRoom,
                          onPressed: _cancelAndExit,
                        ),
                        const SizedBox(height: AppDimens.space10),
                      ],
                    ),
        ),
      ),
    );
  }
}

