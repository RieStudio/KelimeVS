import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/kelime_vs_logo.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../application/auth_notifier.dart';
import '../domain/auth_link_result.dart';
import '../../profile/application/profile_notifier.dart';

/// Giriş (Karşılama) Ekranı.
///
/// Kullanıcıya iki net seçenek sunar:
/// 1. "Google ile Giriş Yap" (PrimaryButton)
/// 2. "Misafir Olarak Devam Et" (SecondaryButton - anonim giriş başlatır, ad sormaz)
///
/// Misafir kullanıcıların adı sunucu tarafından otomatik M-#### olarak atanır.
class WelcomeScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const WelcomeScreen({super.key, this.onComplete});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _isBusy = false;

  Future<void> _handleGuestSignIn() async {
    if (_isBusy) return;
    if (!ensureNetworkConnected(context, ref)) return;

    setState(() => _isBusy = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInAsGuest();
      if (!mounted) return;

      final profile = ref.read(profileProvider);
      if (profile.hasNickname) {
        widget.onComplete?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.authGenericError)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.authGenericError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isBusy) return;
    if (!ensureNetworkConnected(context, ref)) return;

    setState(() => _isBusy = true);
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
          widget.onComplete?.call();
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
        setState(() => _isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final profile = ref.watch(profileProvider);
    final isBusy = _isBusy || authState.isLoading || profile.isSyncing;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        key: const Key('welcome_screen'),
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
                    AppStrings.slogan,
                    style: AppTextStyles.bodyText.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimens.space32),

                  if (isBusy) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: AppDimens.space20),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 1. Google ile Giriş Yap Butonu (PrimaryButton)
                  PrimaryButton(
                    key: const Key('welcome_google_sign_in_button'),
                    text: AppStrings.signInWithGoogle,
                    onPressed: isBusy ? null : _handleGoogleSignIn,
                  ),
                  const SizedBox(height: AppDimens.space12),

                  // 2. Misafir Olarak Devam Et Butonu (SecondaryButton)
                  SecondaryButton(
                    key: const Key('welcome_guest_sign_in_button'),
                    text: AppStrings.continueAsGuest,
                    onPressed: isBusy ? null : _handleGuestSignIn,
                  ),
                  const SizedBox(height: AppDimens.space20),

                  // 3. Misafir Bilgilendirme Notu
                  Container(
                    key: const Key('welcome_guest_notice_card'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space16,
                      vertical: AppDimens.space12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusAlertBox,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThin,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.ink,
                          offset: Offset(0, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: const Text(
                      AppStrings.guestNoticeInWelcome,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontNunito,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
