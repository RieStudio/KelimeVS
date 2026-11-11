import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/network/network_guard.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/player_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/stat_card.dart';
import '../application/public_profile_provider.dart';
import '../domain/public_profile_model.dart';

/// Başka bir oyuncunun herkese açık profilini açan evrensel rota yardımcısı.
Future<void> openPublicProfile(BuildContext context, String uid) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PublicProfileScreen(uid: uid),
    ),
  );
}

/// Başka bir oyuncunun herkese açık profil ekranı.
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String uid;

  const PublicProfileScreen({
    super.key,
    required this.uid,
  });

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool? _localBlockedState;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final isMe = ref.read(isCurrentUserProvider(widget.uid));
        if (isMe) {
          Navigator.of(context).pop();
        }
      });
    } catch (_) {}
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontNunito,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.ink,
      ),
    );
  }

  Future<void> _handleBlock(BuildContext context, String nickname) async {
    if (!ensureNetworkConnected(context, ref)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: AppDimens.borderRadiusDialog,
            side: const BorderSide(
              color: AppColors.ink,
              width: AppDimens.borderThick,
            ),
          ),
          title: const Text(
            AppStrings.blockDialogTitle,
            style: AppTextStyles.cardTitle,
          ),
          content: Text(
            AppStrings.blockDialogMessage(nickname),
            style: AppTextStyles.bodyText,
          ),
          actions: [
            PrimaryButton(
              text: AppStrings.blockConfirm,
              backgroundColor: AppColors.danger,
              shadowColor: AppColors.dangerDark,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
            const SizedBox(height: AppDimens.space8),
            SecondaryButton(
              text: AppStrings.cancel,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await ref.read(publicProfileServiceProvider).blockUser(widget.uid);
      if (mounted) {
        setState(() {
          _localBlockedState = true;
          _isBusy = false;
        });
        _showSnackBar(AppStrings.profileBlockedSuccess);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        final msg = e is PublicProfileException
            ? e.message
            : AppStrings.profileGenericError;
        _showSnackBar(msg);
      }
    }
  }

  Future<void> _handleUnblock(BuildContext context) async {
    if (!ensureNetworkConnected(context, ref)) return;

    setState(() => _isBusy = true);
    try {
      await ref.read(publicProfileServiceProvider).unblockUser(widget.uid);
      if (mounted) {
        setState(() {
          _localBlockedState = false;
          _isBusy = false;
        });
        _showSnackBar(AppStrings.profileUnblockedSuccess);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        final msg = e is PublicProfileException
            ? e.message
            : AppStrings.unblockGenericError;
        _showSnackBar(msg);
      }
    }
  }

  void _showReportSheet(BuildContext context, String nickname) {
    if (!ensureNetworkConnected(context, ref)) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PublicProfileReportBottomSheet(
        parentContext: context,
        uid: widget.uid,
        nickname: nickname,
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.space12,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: AppStrings.back,
            child: AppIconButton(
              icon: AppIcons.back,
              semanticLabel: AppStrings.back,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          const Expanded(
            child: Text(
              AppStrings.publicProfileTitle,
              style: AppTextStyles.screenTitle,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 44, height: 44),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = ref.watch(isCurrentUserProvider(widget.uid));
    if (isMe) {
      return const SizedBox.shrink();
    }

    final profileAsync = ref.watch(publicProfileProvider(widget.uid));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: profileAsync.when(
          loading: () => Column(
            children: [
              _buildTopBar(context),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ],
          ),
          error: (err, _) {
            final isDeletedOrNotFound = err is PublicProfileException &&
                (err.isNotFound || err.isDeleted);

            if (isDeletedOrNotFound) {
              return Column(
                children: [
                  _buildTopBar(context),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimens.space24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Opacity(
                              opacity: 0.35,
                              child: PlayerAvatar.unknown(
                                size: 88,
                                borderWidth: AppDimens.borderThick,
                              ),
                            ),
                            const SizedBox(height: AppDimens.space20),
                            const Text(
                              AppStrings.profileDeletedTitle,
                              style: AppTextStyles.cardTitle,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDimens.space8),
                            Text(
                              AppStrings.profileDeletedMessage,
                              style: AppTextStyles.bodyText.copyWith(
                                color: AppColors.muted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDimens.space24),
                            SecondaryButton(
                              text: AppStrings.backAction,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final errorMessage = err is PublicProfileException
                ? err.message
                : AppStrings.profileConnectionError;

            return Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimens.space24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            errorMessage,
                            style:
                                AppTextStyles.cardTitle.copyWith(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppDimens.space16),
                          SecondaryButton(
                            text: AppStrings.retry,
                            onPressed: () => ref.invalidate(
                              publicProfileProvider(widget.uid),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          data: (profile) {
            final nickname = profile.nickname.trim().isNotEmpty
                ? profile.nickname.trim()
                : AppStrings.defaultPlayerName;

            final isBlocked = _localBlockedState ?? profile.isBlocked;

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppDimens.space24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context),
                  const SizedBox(height: AppDimens.space24),

                  // Büyük Avatar (Rakip/Diğer oyuncu için PlayerAvatar.opponent)
                  Center(
                    child: PlayerAvatar.opponent(
                      name: nickname,
                      frame: profile.equippedFrame,
                      size: 88,
                      borderWidth: AppDimens.borderThick,
                      includeFramePadding: true,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space16),

                  // Takma Ad Metni
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                    ),
                    child: Center(
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
                  ),

                  // Misafir Rozeti
                  if (profile.isGuest) ...[
                    const SizedBox(height: AppDimens.space8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.mint,
                            width: AppDimens.borderThin,
                          ),
                        ),
                        child: Text(
                          AppStrings.profileGuestBadge,
                          style: AppTextStyles.secondaryText.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: AppDimens.space24),

                  // 3 İstatistik Kartı: Oynanan Maç, Galibiyet, Kazanma
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: StatCard(
                              label: AppStrings.statsPlayed,
                              value: profile.stats.played.toString(),
                            ),
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Expanded(
                            child: StatCard(
                              label: AppStrings.statsWon,
                              value: profile.stats.won.toString(),
                            ),
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Expanded(
                            child: StatCard(
                              label: AppStrings.statsWinRate,
                              value: profile.stats.winRateDisplay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppDimens.space24),

                  // Aksiyon Alanı
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.screenPaddingHorizontal,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isBlocked) ...[
                          // Engellendi Uyarı Kartı
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.space16,
                              vertical: AppDimens.space12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSurface,
                              borderRadius: AppDimens.borderRadiusListCard,
                              border: Border.all(
                                color: AppColors.dangerSoft,
                                width: AppDimens.borderThin,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.block_rounded,
                                  size: 20,
                                  color: AppColors.dangerText,
                                ),
                                const SizedBox(width: AppDimens.space10),
                                Expanded(
                                  child: Text(
                                    AppStrings.profileBlockedBanner,
                                    style: AppTextStyles.bodyText.copyWith(
                                      color: AppColors.dangerText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppDimens.space16),

                          // Engeli Kaldır Butonu
                          Semantics(
                            button: true,
                            label: AppStrings.unblockAction,
                            child: SecondaryButton(
                              text: AppStrings.unblockAction,
                              onPressed: _isBusy
                                  ? null
                                  : () => _handleUnblock(context),
                            ),
                          ),
                          const SizedBox(height: AppDimens.space16),

                          // Bildir Butonu
                          Semantics(
                            button: true,
                            label: AppStrings.reportAction,
                            child: SecondaryButton(
                              text: AppStrings.reportAction,
                              onPressed: _isBusy
                                  ? null
                                  : () => _showReportSheet(context, nickname),
                            ),
                          ),
                        ] else ...[
                          // Engelle Butonu
                          Semantics(
                            button: true,
                            label: AppStrings.blockAction,
                            child: SecondaryButton(
                              text: AppStrings.blockAction,
                              onPressed: _isBusy
                                  ? null
                                  : () => _handleBlock(context, nickname),
                            ),
                          ),
                          const SizedBox(height: AppDimens.space16),

                          // Bildir Butonu
                          Semantics(
                            button: true,
                            label: AppStrings.reportAction,
                            child: SecondaryButton(
                              text: AppStrings.reportAction,
                              onPressed: _isBusy
                                  ? null
                                  : () => _showReportSheet(context, nickname),
                            ),
                          ),
                          const SizedBox(height: AppDimens.space8),

                          // Yardımcı Metin
                          Text(
                            AppStrings.profileBlockHelpText,
                            style: AppTextStyles.secondaryText.copyWith(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PublicProfileReportBottomSheet extends StatefulWidget {
  final BuildContext parentContext;
  final String uid;
  final String nickname;

  const _PublicProfileReportBottomSheet({
    required this.parentContext,
    required this.uid,
    required this.nickname,
  });

  @override
  State<_PublicProfileReportBottomSheet> createState() =>
      _PublicProfileReportBottomSheetState();
}

class _PublicProfileReportBottomSheetState
    extends State<_PublicProfileReportBottomSheet> {
  String _selectedReason = 'inappropriate_nickname';
  bool _isSubmitting = false;

  final _reasons = const [
    (
      key: 'inappropriate_nickname',
      label: AppStrings.reasonInappropriateNickname,
    ),
    (
      key: 'cheating',
      label: AppStrings.reasonCheatingSuspicion,
    ),
    (
      key: 'other',
      label: AppStrings.reasonOther,
    ),
  ];

  Future<void> _submit(WidgetRef ref) async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(publicProfileServiceProvider)
          .reportUser(widget.uid, _selectedReason);
      if (mounted) {
        Navigator.of(context).pop();
        if (widget.parentContext.mounted) {
          ScaffoldMessenger.of(widget.parentContext).showSnackBar(
            const SnackBar(
              content: Text(
                AppStrings.profileReportedSuccess,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: AppColors.ink,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        if (e is PublicProfileException && e.isAlreadyReported) {
          Navigator.of(context).pop();
        }
        final msg = e is PublicProfileException
            ? e.message
            : AppStrings.reportGenericError;
        if (widget.parentContext.mounted) {
          ScaffoldMessenger.of(widget.parentContext).showSnackBar(
            SnackBar(
              content: Text(
                msg,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: AppColors.ink,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.screenPaddingHorizontal,
              vertical: AppDimens.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tutamaç (Handle)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space16),

                // Başlık
                Text(
                  AppStrings.reportDialogTitle,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space6),

                // Alt başlık
                Text(
                  AppStrings.reportUserSubtitle(widget.nickname),
                  style:
                      AppTextStyles.bodyText.copyWith(color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space16),

                // Seçenekler
                ..._reasons.map((r) {
                  final isSelected = _selectedReason == r.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppDimens.space8),
                    child: InkWell(
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() => _selectedReason = r.key),
                      borderRadius: AppDimens.borderRadiusListCard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space16,
                          vertical: AppDimens.space12,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? AppColors.surface : AppColors.card,
                          borderRadius: AppDimens.borderRadiusListCard,
                          border: Border.all(
                            color: isSelected ? AppColors.ink : AppColors.mint,
                            width: isSelected
                                ? AppDimens.borderThick
                                : AppDimens.borderThin,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: AppDimens.space12),
                            Expanded(
                              child: Text(
                                r.label,
                                style: AppTextStyles.bodyText.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: AppDimens.space16),

                // Butonlar: Bildir ve Vazgeç
                PrimaryButton(
                  text: AppStrings.reportAction,
                  onPressed: _isSubmitting ? null : () => _submit(ref),
                ),
                const SizedBox(height: AppDimens.space8),
                SecondaryButton(
                  text: AppStrings.cancel,
                  onPressed:
                      _isSubmitting ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
