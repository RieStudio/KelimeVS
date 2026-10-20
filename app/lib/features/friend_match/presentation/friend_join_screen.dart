import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/match_session.dart';
import '../../game/presentation/match_screen.dart';
import '../../profile/application/profile_notifier.dart';
import '../data/friend_match_client.dart';

/// "Koda Katıl" ekranı: Arkadaşının paylaştığı 6 haneli kodu girmesini sağlar.
class FriendJoinScreen extends ConsumerStatefulWidget {
  final FriendMatchClient? client;

  const FriendJoinScreen({
    super.key,
    this.client,
  });

  @override
  ConsumerState<FriendJoinScreen> createState() => _FriendJoinScreenState();
}

class _FriendJoinScreenState extends ConsumerState<FriendJoinScreen> {
  late final FriendMatchClient _client;
  StreamSubscription<FriendMatchEvent>? _subscription;

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isMatched = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? FriendMatchClient();
    _subscription = _client.events.listen(_handleEvent);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _handleEvent(FriendMatchEvent event) {
    if (!mounted) return;

    if (event is FriendMatchMatched) {
      _onMatched(event.matchId, event.opponentName);
    } else if (event is FriendMatchFailed) {
      setState(() {
        _isLoading = false;
        _errorMessage = _mapErrorMessage(event.code, event.message);
      });
    }
  }

  String _mapErrorMessage(String code, String defaultMessage) {
    switch (code) {
      case 'room_not_found':
        return AppStrings.roomNotFound;
      case 'room_full':
        return AppStrings.roomFull;
      case 'cannot_join_own_room':
        return AppStrings.cannotJoinOwnRoom;
      case 'room_unavailable':
        return AppStrings.friendRoomUnavailable;
      case 'rate_limited':
        return AppStrings.friendRoomRateLimited;
      case 'lobby_busy':
        return AppStrings.friendRoomLobbyBusy;
      default:
        return defaultMessage;
    }
  }

  void _onMatched(String matchId, String opponentName) {
    if (_isMatched) return;
    _isMatched = true;

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
            isFriendly: true,
          ),
    );
  }

  Future<void> _submitCode() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6 || _isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final profile = ref.read(profileProvider);
    final nickname = (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : null;

    await _client.joinRoom(code, name: nickname);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) return;

    // Yalnızca izin verilen 28 karakteri filtrele
    final clean = data.text!
        .toUpperCase()
        .replaceAll(RegExp(r'[^2-9B-DF-HJ-NP-TV-Z]'), '');

    if (clean.isNotEmpty) {
      final code = clean.length > 6 ? clean.substring(0, 6) : clean;
      _controller.text = code;
      _controller.selection = TextSelection.collapsed(offset: code.length);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    if (!_isMatched) {
      _client.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isValidLength = _controller.text.trim().length == 6;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          AppStrings.joinRoom,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppDimens.space12),

              // Açıklama
              Text(
                AppStrings.enterInviteCodeDescription,
                style: AppTextStyles.bodyText.copyWith(
                  fontSize: 16,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimens.space24),

              // 6 Haneli Giriş Alanı
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space16,
                  vertical: AppDimens.space8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppDimens.borderRadiusListCard,
                  border: Border.all(
                    color: _errorMessage != null ? AppColors.danger : AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.ink,
                      offset: Offset(0, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('friend_code_input_field'),
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFredoka,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6,
                          color: AppColors.ink,
                        ),
                        inputFormatters: [
                          _UppercaseAndCleanFormatter(),
                        ],
                        decoration: InputDecoration(
                          hintText: '------',
                          hintStyle: TextStyle(
                            fontFamily: AppTextStyles.fontFredoka,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 6,
                            color: AppColors.muted.withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) {
                          if (isValidLength) _submitCode();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.content_paste_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      tooltip: 'Yapıştır',
                      onPressed: _pasteFromClipboard,
                    ),
                  ],
                ),
              ),

              // Hata Mesajı
              if (_errorMessage != null) ...[
                const SizedBox(height: AppDimens.space12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space12,
                    vertical: AppDimens.space8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.danger,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: AppDimens.space8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTextStyles.bodyText.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppDimens.space24),

              // "Katıl" Butonu
              PrimaryButton(
                key: const Key('friend_join_button'),
                text: _isLoading ? AppStrings.joiningRoom : AppStrings.joinMatch,
                isLarge: true,
                onPressed: (isValidLength && !_isLoading) ? _submitCode : null,
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Küçük harfleri otomatik büyük harfe çeviren, sesli/karışan harfleri eleyen
/// ve en fazla 6 karakter kabul eden süzgeç.
class _UppercaseAndCleanFormatter extends TextInputFormatter {
  static const _allowed = '23456789BCDFGHJKMNPQRSTVWXYZ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < upper.length; i++) {
      final char = upper[i];
      if (_allowed.contains(char)) {
        buffer.write(char);
      }
      if (buffer.length == 6) break;
    }
    final cleanText = buffer.toString();
    return TextEditingValue(
      text: cleanText,
      selection: TextSelection.collapsed(offset: cleanText.length),
    );
  }
}

