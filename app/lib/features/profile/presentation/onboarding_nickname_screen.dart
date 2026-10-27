import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/kelime_vs_logo.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/domain/auth_link_result.dart';
import '../application/profile_notifier.dart';
import '../domain/nickname_validator.dart';

/// İlk açılışta takma ad belirleme ekranı (Onboarding).
///
/// docs/DESIGN.md ve Faz 5.1 kurallarına uygun olarak:
/// - Zemin `surface`, logo ortalı,
/// - "Hoş Geldin!" ve "KelimeVS’de seni nasıl çağıralım?",
/// - Tek satır giriş alanı (kart zemin, 3 px ink kenarlık, köşe 18),
/// - Anlık doğrulama ve hata mesajı gösterimi,
/// - Karakter sayacı (en fazla 16),
/// - Yalnızca geçerli takma ad girildiğinde aktif olan "Devam" butonu.
class OnboardingNicknameScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingNicknameScreen({super.key, this.onComplete});

  @override
  ConsumerState<OnboardingNicknameScreen> createState() =>
      _OnboardingNicknameScreenState();
}

class _OnboardingNicknameScreenState
    extends ConsumerState<OnboardingNicknameScreen> {
  late final TextEditingController _controller;
  String? _errorMessage;
  bool _isSubmitting = false;
  bool _isGoogleSigningIn = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting || _isGoogleSigningIn) return;

    final validation = NicknameValidator.validate(_controller.text);
    if (!validation.isValid || validation.normalized == null) {
      setState(() {
        _errorMessage = validation.errorMessage;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await ref
        .read(profileProvider.notifier)
        .setNickname(validation.normalized!);

    if (!mounted) return;

    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isSubmitting || _isGoogleSigningIn) return;
    if (!ensureNetworkConnected(context, ref)) return;

    setState(() {
      _isGoogleSigningIn = true;
    });

    try {
      final result =
          await ref.read(authNotifierProvider.notifier).signInWithGoogle();

      if (!mounted) return;

      if (result is AuthLinkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      } else if (result is AuthLinkSuccess) {
        final profile = ref.read(profileProvider);
        if (profile.hasNickname) {
          if (widget.onComplete != null) {
            widget.onComplete!();
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.authGenericError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLength = _controller.text.length;

    final authState = ref.watch(authNotifierProvider);
    final profile = ref.watch(profileProvider);
    final isBusy = _isSubmitting || _isGoogleSigningIn || authState.isLoading;
    final showGoogleNotice = authState.isGoogleLinked && !profile.hasNickname;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.screenPaddingHorizontal,
              vertical: AppDimens.screenPaddingTop,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: KelimeVSLogo()),
                const SizedBox(height: AppDimens.space24),

                Text(
                  AppStrings.welcomeTitle,
                  style: AppTextStyles.screenTitle.copyWith(
                    color: AppColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space8),

                Text(
                  AppStrings.welcomePrompt,
                  style: AppTextStyles.bodyText.copyWith(
                    color: AppColors.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (showGoogleNotice) ...[
                  const SizedBox(height: AppDimens.space16),
                  Container(
                    key: const Key('google_linked_no_profile_notice'),
                    padding: const EdgeInsets.all(AppDimens.space12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusAlertBox,
                      border: Border.all(
                        color: AppColors.mint,
                        width: AppDimens.borderThin,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppDimens.space10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                AppStrings.googleLinkedNoProfileNotice,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontNunito,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                  height: 1.35,
                                ),
                              ),
                              if (authState.linkedEmail != null &&
                                  authState.linkedEmail!.isNotEmpty) ...[
                                const SizedBox(height: AppDimens.space4),
                                Text(
                                  authState.linkedEmail!,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontNunito,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppDimens.space24),

                // Giriş Kutusu (kart zemin, 3 px ink kenarlık, köşe 18)
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
                    onSubmitted: (_) => _submit(),
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

                // Kural ipucu / hata mesajı ve karakter sayacı
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

                // Devam Butonu
                PrimaryButton(
                  text: AppStrings.continueAction,
                  onPressed: _isValid && !isBusy ? _submit : null,
                ),
                const SizedBox(height: AppDimens.space12),

                // Google ile Devam Et Butonu
                SecondaryButton(
                  text: AppStrings.signInWithGoogle,
                  onPressed: isBusy ? null : _handleGoogleSignIn,
                ),
                const SizedBox(height: AppDimens.space8),
                const Text(
                  AppStrings.signInWithGoogleHint,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontNunito,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}
