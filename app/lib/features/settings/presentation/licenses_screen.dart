import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';

/// Paket adı ve bu pakete ait tüm lisans metinlerini tutan model.
@immutable
class PackageLicenses {
  final String name;
  final List<String> licenseTexts;

  const PackageLicenses({
    required this.name,
    required this.licenseTexts,
  });
}

/// Flutter [LicenseRegistry.licenses] akışını okuyup paketlere göre gruplayan yardımcı fonksiyon.
Future<List<PackageLicenses>> loadLicensesFromRegistry() async {
  final Map<String, List<String>> packageMap = {};

  await for (final LicenseEntry entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs
        .map((p) {
          if (p.indent == LicenseParagraph.centeredIndent) {
            return p.text;
          } else if (p.indent > 0) {
            return '${'  ' * p.indent}${p.text}';
          }
          return p.text;
        })
        .join('\n\n');

    for (final package in entry.packages) {
      packageMap.putIfAbsent(package, () => []).add(text);
    }
  }

  final sortedPackages = packageMap.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return sortedPackages
      .map(
        (name) => PackageLicenses(
          name: name,
          licenseTexts: packageMap[name]!,
        ),
      )
      .toList();
}

/// Oyunun tasarım sistemine (koyu çerçeve, ink, kart gölgesi) tam uyumlu,
/// "Powered by Flutter" veya hazır framework sayfasına bağımlı olmayan lisans listesi ekranı.
class LicensesScreen extends StatefulWidget {
  final String? applicationName;
  final String? applicationVersion;
  final String? applicationLegalese;
  final Future<List<PackageLicenses>> Function()? licensesLoader;

  const LicensesScreen({
    super.key,
    this.applicationName,
    this.applicationVersion,
    this.applicationLegalese,
    this.licensesLoader,
  });

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final Future<List<PackageLicenses>> _licensesFuture;

  @override
  void initState() {
    super.initState();
    final loader = widget.licensesLoader ?? loadLicensesFromRegistry;
    _licensesFuture = loader();
  }

  @override
  Widget build(BuildContext context) {
    final hasAppInfo = widget.applicationName != null ||
        widget.applicationVersion != null ||
        widget.applicationLegalese != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    key: const Key('licenses_back_button'),
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
                        AppStrings.licensesTitle,
                        style: AppTextStyles.screenTitle,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Uygulama Bilgisi Başlık Alanı (varsa) - Sade, çerçevesiz ve ortalı düz metin
            if (hasAppInfo)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.screenPaddingHorizontal,
                  vertical: AppDimens.space12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.applicationName != null)
                      Text(
                        widget.applicationName!,
                        style: AppTextStyles.cardTitle,
                        textAlign: TextAlign.center,
                      ),
                    if (widget.applicationVersion != null) ...[
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        widget.applicationVersion!,
                        style: AppTextStyles.secondaryText,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (widget.applicationLegalese != null) ...[
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        widget.applicationLegalese!,
                        style: AppTextStyles.secondaryText.copyWith(
                          color: AppColors.muted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),

            // Lisans Listesi / Yükleniyor / Boş Durum
            Expanded(
              child: FutureBuilder<List<PackageLicenses>>(
                future: _licensesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  final packages = snapshot.data ?? const [];
                  if (packages.isEmpty) {
                    return const Center(
                      child: Text(
                        AppStrings.noLicensesFound,
                        style: AppTextStyles.cardTitle,
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                      vertical: AppDimens.space8,
                    ),
                    itemCount: packages.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppDimens.space8),
                    itemBuilder: (context, index) {
                      final item = packages[index];
                      return _PackageLicenseTile(
                        packageLicenses: item,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PackageLicenseDetailScreen(
                                packageLicenses: item,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageLicenseTile extends StatelessWidget {
  final PackageLicenses packageLicenses;
  final VoidCallback onTap;

  const _PackageLicenseTile({
    required this.packageLicenses,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.ink,
          width: AppDimens.borderThin,
        ),
        boxShadow: AppDimens.shadowQuestionCard,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppDimens.borderRadiusListCard,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        packageLicenses.name,
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: AppDimens.space4),
                      Text(
                        AppStrings.licenseCount(
                          packageLicenses.licenseTexts.length,
                        ),
                        style: AppTextStyles.secondaryText.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seçilen bir paketin tüm lisans metinlerini tam metin (kısaltmasız) gösteren detay ekranı.
class PackageLicenseDetailScreen extends StatelessWidget {
  final PackageLicenses packageLicenses;

  const PackageLicenseDetailScreen({
    super.key,
    required this.packageLicenses,
  });

  @override
  Widget build(BuildContext context) {
    final licenses = packageLicenses.licenseTexts;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    key: const Key('license_detail_back_button'),
                    icon: AppIcons.back,
                    semanticLabel: AppStrings.back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        packageLicenses.name,
                        style: AppTextStyles.screenTitle,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lisans Metinleri Listesi
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppDimens.screenPaddingHorizontal),
                itemCount: licenses.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppDimens.space16),
                itemBuilder: (context, index) {
                  final text = licenses[index];
                  return Container(
                    padding: const EdgeInsets.all(AppDimens.space16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppDimens.borderRadiusListCard,
                      border: Border.all(
                        color: AppColors.ink,
                        width: AppDimens.borderThin,
                      ),
                      boxShadow: AppDimens.shadowQuestionCard,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (licenses.length > 1) ...[
                          Text(
                            'Lisans ${index + 1}',
                            style: AppTextStyles.subtitle,
                          ),
                          const SizedBox(height: AppDimens.space8),
                        ],
                        SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.0,
                            height: 1.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

