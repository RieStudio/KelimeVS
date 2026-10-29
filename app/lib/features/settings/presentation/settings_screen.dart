import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../gallery/component_gallery.dart';

/// Provider for retrieving application package information asynchronously.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerWidget {
  /// Whether developer options (e.g. ComponentGallery) should be displayed.
  /// Defaults to [kDebugMode], but can be explicitly controlled in widget tests.
  final bool isDebug;

  /// Optional custom URL launcher for dependency injection in tests.
  final Future<bool> Function(Uri url)? urlLauncher;

  const SettingsScreen({
    super.key,
    this.isDebug = kDebugMode,
    this.urlLauncher,
  });

  Future<bool> _launchUrl(Uri url) async {
    if (urlLauncher != null) {
      return await urlLauncher!(url);
    }
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showLinkError(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.linkOpenError),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(packageInfoProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Üst Başlık Çubuğu
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
                vertical: AppDimens.space12,
              ),
              child: Row(
                children: [
                  AppIconButton(
                    key: const Key('settings_back_button'),
                    icon: AppIcons.back,
                    semanticLabel: AppStrings.back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  const Expanded(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppStrings.settingsTitle,
                        style: AppTextStyles.screenTitle,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Ayarlar Listesi
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.screenPaddingHorizontal,
                  vertical: AppDimens.space8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Yasal ve Bilgilendirme Grubu
                    const Text(
                      AppStrings.settingsSectionLegal,
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: AppDimens.space8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppDimens.borderRadiusListCard,
                        border: Border.all(
                          color: AppColors.mint,
                          width: AppDimens.borderThin,
                        ),
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            key: const Key('settings_privacy_policy'),
                            icon: Icons.shield_outlined,
                            title: AppStrings.privacyPolicy,
                            trailing: const Icon(
                              Icons.open_in_new,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            onTap: () async {
                              if (!ensureNetworkConnected(context, ref)) return;
                              final uri = Uri.parse(AppConfig.privacyPolicyUrl);
                              try {
                                final ok = await _launchUrl(uri);
                                if (!ok && context.mounted) {
                                  _showLinkError(context);
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  _showLinkError(context);
                                }
                              }
                            },
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.surface,
                          ),
                          _SettingsTile(
                            key: const Key('settings_licenses'),
                            icon: Icons.description_outlined,
                            title: AppStrings.thirdPartyLicenses,
                            trailing: const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.muted,
                            ),
                            onTap: () {
                              final info = versionAsync.asData?.value;
                              showLicensePage(
                                context: context,
                                applicationName: 'KelimeVS',
                                applicationVersion: info != null
                                    ? 'v${info.version} (${info.buildNumber})'
                                    : null,
                                applicationLegalese: AppStrings.copyright,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppDimens.space24),

                    // 2. Destek Grubu
                    const Text(
                      AppStrings.settingsSectionSupport,
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: AppDimens.space8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppDimens.borderRadiusListCard,
                        border: Border.all(
                          color: AppColors.mint,
                          width: AppDimens.borderThin,
                        ),
                      ),
                      child: _SettingsTile(
                        key: const Key('settings_contact_support'),
                        icon: Icons.mail_outline_rounded,
                        title: AppStrings.contactSupport,
                        subtitle: AppConfig.supportEmail,
                        trailing: const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.muted,
                        ),
                        onTap: () async {
                          if (!ensureNetworkConnected(context, ref)) return;
                          final uri = Uri(
                            scheme: 'mailto',
                            path: AppConfig.supportEmail,
                            queryParameters: {
                              'subject': AppConfig.supportSubject,
                            },
                          );
                          try {
                            final ok = await _launchUrl(uri);
                            if (!ok && context.mounted) {
                              _showLinkError(context);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              _showLinkError(context);
                            }
                          }
                        },
                      ),
                    ),

                    // 3. Geliştirici Grubu (Yalnızca isDebug == true)
                    if (isDebug) ...[
                      const SizedBox(height: AppDimens.space24),
                      const Text(
                        AppStrings.settingsSectionDeveloper,
                        style: AppTextStyles.sectionLabel,
                      ),
                      const SizedBox(height: AppDimens.space8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: AppDimens.borderRadiusListCard,
                          border: Border.all(
                            color: AppColors.mint,
                            width: AppDimens.borderThin,
                          ),
                        ),
                        child: _SettingsTile(
                          key: const Key('settings_dev_gallery'),
                          icon: Icons.palette_outlined,
                          title: AppStrings.devComponentGallery,
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: AppColors.muted,
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ComponentGallery(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: AppDimens.space32),

                    // 4. Alt Bilgi / Sürüm Gösterimi
                    versionAsync.when(
                      data: (info) => Center(
                        child: Text(
                          AppStrings.appVersionFooter(
                            info.version,
                            info.buildNumber,
                          ),
                          style: AppTextStyles.secondaryText,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      loading: () => const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, _) => Center(
                        child: Text(
                          AppStrings.appVersionFooter('1.0.0', '8'),
                          style: AppTextStyles.secondaryText,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space6),
                    const Center(
                      child: _RieStudioFooterLogo(),
                    ),
                    const SizedBox(height: AppDimens.space24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDimens.borderRadiusListCard,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.space16,
            vertical: AppDimens.space12,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 20,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.playerName.copyWith(
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        subtitle!,
                        style: AppTextStyles.secondaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _RieStudioFooterLogo extends StatelessWidget {
  /// RieStudio alt bilgi (footer) logosunun ekrandaki dikey yüksekliği (dp).
  static const double footerLogoHeight = 15.0;

  const _RieStudioFooterLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.copyright,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              AppStrings.copyrightPrefix,
              style: AppTextStyles.secondaryText,
            ),
            const SizedBox(width: AppDimens.space6),
            Image.asset(
              'assets/images/riestudio_logo_black_trimmed.png',
              height: footerLogoHeight,
              fit: BoxFit.contain,
              semanticLabel: AppStrings.companyName,
              cacheHeight: 160,
              errorBuilder: (context, error, stackTrace) => Text(
                AppStrings.companyName,
                style: AppTextStyles.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
