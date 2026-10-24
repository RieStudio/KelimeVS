import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_status_provider.dart';
import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import 'primary_button.dart';

/// Açılışta aktif internet bağlantısı bulunmadığında gösterilen tam ekran çevrimdışı sayfası.
class OfflineSplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onRetry;
  final bool isChecking;

  const OfflineSplashScreen({
    super.key,
    required this.onRetry,
    this.isChecking = false,
  });

  @override
  ConsumerState<OfflineSplashScreen> createState() =>
      _OfflineSplashScreenState();
}

class _OfflineSplashScreenState extends ConsumerState<OfflineSplashScreen> {
  late final BannerSuppressionNotifier _suppressionNotifier;

  @override
  void initState() {
    super.initState();
    _suppressionNotifier = ref.read(bannerSuppressionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressionNotifier.suppress();
      }
    });
  }

  @override
  void dispose() {
    _suppressionNotifier.unsuppress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('offline_splash_screen'),
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
          ),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // 1. İkon Rozeti
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.dangerSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.dangerSoft,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: AppColors.danger,
                  ),
                ),
              ),

              const SizedBox(height: AppDimens.space24),

              // 2. Başlık
              Text(
                AppStrings.noInternetTitle,
                style: AppTextStyles.screenTitle.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppDimens.space12),

              // 3. Açıklama
              Text(
                AppStrings.noInternetMessage,
                style: AppTextStyles.bodyText.copyWith(
                  color: AppColors.muted,
                  fontSize: 15,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 3),

              // 4. Tekrar Dene Butonu
              PrimaryButton(
                key: const Key('offline_splash_retry_button'),
                text: AppStrings.retryConnection,
                onPressed: widget.isChecking ? null : widget.onRetry,
              ),

              const SizedBox(height: AppDimens.space24),
            ],
          ),
        ),
      ),
    );
  }
}
