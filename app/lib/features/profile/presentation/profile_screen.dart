import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../application/profile_notifier.dart';
import '../domain/nickname_validator.dart';

/// Faz 5.1: Profil Ekranı
///
/// Başlık: "Profil"
/// Avatar: 88 px selfHome avatarı.
/// Takma ad görünümü ve "Adı Değiştir" eylemi.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showChangeNicknameDialog(BuildContext context, WidgetRef ref, String currentNickname) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _ChangeNicknameDialog(
          currentNickname: currentNickname,
          onSave: (newNickname) async {
            await ref
                .read(profileProvider.notifier)
                .setNickname(newNickname);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final nickname = (profile.nickname != null && profile.nickname!.trim().isNotEmpty)
        ? profile.nickname!.trim()
        : AppStrings.defaultPlayerName;

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.space12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst Çubuk
              Row(
                children: [
                  if (canPop)
                    AppIconButton(
                      icon: AppIcons.back,
                      semanticLabel: AppStrings.back,
                      onTap: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 44, height: 44),
                  Expanded(
                    child: Text(
                      AppStrings.profileTitle,
                      style: AppTextStyles.screenTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 44, height: 44), // Dengelemek için
                ],
              ),
              const SizedBox(height: AppDimens.space24),

              // Büyük Avatar
              Center(
                child: PlayerAvatar.selfHome(
                  name: nickname,
                  size: 88,
                  borderWidth: AppDimens.borderThick,
                ),
              ),
              const SizedBox(height: AppDimens.space16),

              // Takma Ad Metni
              Center(
                child: Text(
                  nickname,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFredoka,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppDimens.space24),

              // Adı Değiştir Butonu
              SecondaryButton(
                text: AppStrings.changeNickname,
                onPressed: () => _showChangeNicknameDialog(context, ref, nickname),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeNicknameDialog extends StatefulWidget {
  final String currentNickname;
  final Future<void> Function(String) onSave;

  const _ChangeNicknameDialog({
    required this.currentNickname,
    required this.onSave,
  });

  @override
  State<_ChangeNicknameDialog> createState() => _ChangeNicknameDialogState();
}

class _ChangeNicknameDialogState extends State<_ChangeNicknameDialog> {
  late final TextEditingController _controller;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentNickname);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _errorMessage = null;
      } else {
        final result = NicknameValidator.validate(value);
        _errorMessage = result.isValid ? null : result.errorMessage;
      }
    });
  }

  bool get _isValid {
    final text = _controller.text.trim();
    if (text.isEmpty) return false;
    return NicknameValidator.validate(text).isValid;
  }

  Future<void> _handleSave() async {
    if (!_isValid || _isSaving) return;

    final validation = NicknameValidator.validate(_controller.text);
    if (!validation.isValid || validation.normalized == null) {
      setState(() {
        _errorMessage = validation.errorMessage;
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSave(validation.normalized!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLength = _controller.text.length;

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppDimens.borderRadiusDialog,
        side: const BorderSide(
          color: AppColors.ink,
          width: AppDimens.borderThick,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppDimens.space20),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.newNicknamePrompt,
              style: AppTextStyles.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space16),

            // Giriş Alanı
            Container(
              height: AppDimens.inputHeight,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusInput,
                border: Border.all(
                  color: _errorMessage != null
                      ? AppColors.dangerSoft
                      : AppColors.ink,
                  width: AppDimens.borderThick,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space16,
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _controller,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _handleSave(),
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 16,
                style: AppTextStyles.inputField,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: AppStrings.nicknameHint,
                  hintStyle: TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.space6),

            // Kural ipucu / hata mesajı ve sayaç
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _errorMessage ?? AppStrings.nicknameRuleHint,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _errorMessage != null
                          ? AppColors.dangerText
                          : AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.space8),
                Text(
                  '$currentLength/16',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // Butonlar: Kaydet ve Vazgeç
            PrimaryButton(
              text: AppStrings.save,
              onPressed: _isValid && !_isSaving ? _handleSave : null,
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
