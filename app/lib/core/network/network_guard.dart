import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import 'network_status_provider.dart';
export 'network_status_provider.dart';

/// Ağ gerektiren bir eylem öncesinde bağlantı durumunu doğrular.
///
/// Bağlantı yoksa [context] üzerinde kayan bir hata uyarısı (SnackBar) gösterir ve `false` döner.
/// Bağlantı varsa `true` döner.
bool ensureNetworkConnected(BuildContext context, WidgetRef ref) {
  final isConnected = ref.read(networkStatusProvider).isConnected;
  if (!isConnected) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.noInternetActionError),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
  return true;
}

