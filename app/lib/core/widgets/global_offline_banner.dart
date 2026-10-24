import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Menülerdeyken bağlantı koptuğunda üstte görünen, içeriği aşağı iten uyarı şeridi.
class GlobalOfflineBanner extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool isChecking;

  const GlobalOfflineBanner({
    super.key,
    this.onRetry,
    this.isChecking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('global_offline_banner'),
      width: double.infinity,
      color: AppColors.dangerSurface,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.dangerSoft,
                width: AppDimens.borderThin,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space8,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 18,
                color: AppColors.dangerText,
              ),
              const SizedBox(width: AppDimens.space8),
              const Expanded(
                child: Text(
                  AppStrings.noInternetBanner,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dangerText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: AppDimens.space8),
                GestureDetector(
                  key: const Key('global_offline_banner_retry'),
                  onTap: isChecking ? null : onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space10,
                      vertical: AppDimens.space4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: AppColors.dangerSoft,
                        width: AppDimens.borderThin,
                      ),
                    ),
                    child: isChecking
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.dangerText,
                            ),
                          )
                        : const Text(
                            AppStrings.retryConnection,
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dangerText,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

