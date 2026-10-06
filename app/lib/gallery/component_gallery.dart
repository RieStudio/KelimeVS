import 'package:flutter/material.dart';
import '../core/icons/app_icons.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_widgets.dart';

/// Geliştirme sürecinde tasarım altyapısını ve tüm bileşenleri
/// canlı olarak incelemek için kullanılan galeri ekranı.
class ComponentGallery extends StatelessWidget {
  const ComponentGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          AppStrings.componentGallery,
          style: AppTextStyles.screenTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.screenPaddingHorizontal,
            vertical: AppDimens.screenPaddingTop,
          ),
          children: [
            // 1. BÖLÜM ETİKETLERİ
            const SectionLabel('Bölüm Etiketleri (Türkçe İ / I Desteği)'),
            const SizedBox(height: AppDimens.space10),
            const SectionLabel(AppStrings.recentMatches),
            const SizedBox(height: AppDimens.space6),
            const SectionLabel('İkinci Tur / İtiraz Detayları'),
            const SizedBox(height: AppDimens.space24),

            // 2. RENK JETONLARI
            const SectionLabel('Renk Jetonları (DESIGN.md Bölüm 2)'),
            const SizedBox(height: AppDimens.space10),
            Wrap(
              spacing: AppDimens.space8,
              runSpacing: AppDimens.space8,
              children: const [
                _ColorChip(name: 'ink', color: AppColors.ink, textColor: AppColors.card),
                _ColorChip(name: 'primary', color: AppColors.primary, textColor: AppColors.card),
                _ColorChip(name: 'bright', color: AppColors.bright, textColor: AppColors.ink),
                _ColorChip(name: 'mint', color: AppColors.mint, textColor: AppColors.ink),
                _ColorChip(name: 'surface', color: AppColors.surface, textColor: AppColors.ink, hasBorder: true),
                _ColorChip(name: 'card', color: AppColors.card, textColor: AppColors.ink, hasBorder: true),
                _ColorChip(name: 'muted', color: AppColors.muted, textColor: AppColors.card),
                _ColorChip(name: 'coin', color: AppColors.coin, textColor: AppColors.ink),
                _ColorChip(name: 'danger', color: AppColors.danger, textColor: AppColors.card),
                _ColorChip(name: 'dangerDark', color: AppColors.dangerDark, textColor: AppColors.card),
                _ColorChip(name: 'dangerText', color: AppColors.dangerText, textColor: AppColors.card),
                _ColorChip(name: 'dangerSoft', color: AppColors.dangerSoft, textColor: AppColors.ink),
                _ColorChip(name: 'dangerSurface', color: AppColors.dangerSurface, textColor: AppColors.ink, hasBorder: true),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // 3. TİPOGRAFİ
            const SectionLabel('Tipografi Örnekleri (Fredoka & Nunito)'),
            const SizedBox(height: AppDimens.space10),
            Container(
              padding: const EdgeInsets.all(AppDimens.space16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusQuestionCard,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppDimens.borderThin,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('46 Kazandın!', style: AppTextStyles.largeResult),
                  SizedBox(height: AppDimens.space8),
                  Text('34 Tur Sonucu', style: AppTextStyles.roundResultTitle),
                  SizedBox(height: AppDimens.space8),
                  Text('22 Ekran Başlığı', style: AppTextStyles.screenTitle),
                  SizedBox(height: AppDimens.space8),
                  Text('18 Soru Metni: B ile başlayan hayvanlar', style: AppTextStyles.questionText),
                  SizedBox(height: AppDimens.space8),
                  Text('17 Hızlı düşün, doğru yaz!', style: AppTextStyles.subtitle),
                  SizedBox(height: AppDimens.space8),
                  Text('16 Oyuncu Adı', style: AppTextStyles.playerName),
                  SizedBox(height: AppDimens.space8),
                  Text('15 Cevap Balonu Metni', style: AppTextStyles.answerBubble),
                  SizedBox(height: AppDimens.space8),
                  Text('12 İkincil Metin / Tarih: Dün 14:30', style: AppTextStyles.secondaryText),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space24),

            // 4. BUTONLAR
            const SectionLabel('Butonlar (Sert Gölge & Basılma Efekti)'),
            const SizedBox(height: AppDimens.space10),
            PrimaryButton(
              text: AppStrings.quickMatch,
              subtitle: AppStrings.quickMatchSubtitle,
              isLarge: true,
              onPressed: () {},
            ),
            const SizedBox(height: AppDimens.space14),
            PrimaryButton(
              text: AppStrings.playAgain,
              onPressed: () {},
            ),
            const SizedBox(height: AppDimens.space14),
            SecondaryButton(
              text: AppStrings.playWithFriend,
              onPressed: () {},
            ),
            const SizedBox(height: AppDimens.space14),
            SecondaryButton(
              text: AppStrings.cancel,
              onPressed: () {},
            ),
            const SizedBox(height: AppDimens.space24),

            // 5. İKON BUTONLAR
            const SectionLabel('İkon Butonlar (44x44 Görsel, 48x48 Dokunma Alanı)'),
            const SizedBox(height: AppDimens.space10),
            Row(
              children: [
                AppIconButton(
                  icon: AppIcons.settings,
                  semanticLabel: 'Ayarlar',
                  onTap: () {},
                ),
                const SizedBox(width: AppDimens.space12),
                AppIconButton(
                  icon: AppIcons.close,
                  semanticLabel: 'Kapat',
                  onTap: () {},
                ),
                const SizedBox(width: AppDimens.space12),
                AppIconButton(
                  icon: AppIcons.back,
                  semanticLabel: 'Geri',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // 6. AVATARLAR
            const SectionLabel('Avatarlar (Kendi / Rakip / Bilinmeyen)'),
            const SizedBox(height: AppDimens.space10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Column(
                  children: [
                    PlayerAvatar.selfHome(name: 'Arif'),
                    SizedBox(height: AppDimens.space6),
                    Text('Kendi (Ev)', style: AppTextStyles.secondaryText),
                  ],
                ),
                Column(
                  children: [
                    PlayerAvatar.selfMatch(name: 'Arif'),
                    SizedBox(height: AppDimens.space6),
                    Text('Kendi (Maç)', style: AppTextStyles.secondaryText),
                  ],
                ),
                Column(
                  children: [
                    PlayerAvatar.opponent(name: 'Zeynep'),
                    SizedBox(height: AppDimens.space6),
                    Text('Rakip', style: AppTextStyles.secondaryText),
                  ],
                ),
                Column(
                  children: [
                    PlayerAvatar.unknown(size: AppDimens.avatarHome),
                    SizedBox(height: AppDimens.space6),
                    Text('Bilinmeyen', style: AppTextStyles.secondaryText),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
            const Center(
              child: Column(
                children: [
                  PlayerAvatar.unknown(size: AppDimens.avatarSearch),
                  SizedBox(height: AppDimens.space6),
                  Text('Arama Ekranı (92dp)', style: AppTextStyles.secondaryText),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space24),

            // 7. SONUÇ ETİKETLERİ
            const SectionLabel('Sonuç Etiketleri (Sabit 88dp Genişlik)'),
            const SizedBox(height: AppDimens.space10),
            Row(
              children: const [
                ResultBadge.won(),
                SizedBox(width: AppDimens.space16),
                ResultBadge.lost(),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // 8. İKONLAR
            const SectionLabel('İkon Seti (DESIGN.md Bölüm 5)'),
            const SizedBox(height: AppDimens.space10),
            Wrap(
              spacing: AppDimens.space16,
              runSpacing: AppDimens.space16,
              children: const [
                _IconItem(icon: AppIcons.home, label: 'Ev'),
                _IconItem(icon: AppIcons.leaderboard, label: 'Sıralama'),
                _IconItem(icon: AppIcons.shop, label: 'Mağaza'),
                _IconItem(icon: AppIcons.profile, label: 'Profil'),
                _IconItem(icon: AppIcons.settings, label: 'Ayarlar'),
                _IconItem(icon: AppIcons.close, label: 'Kapat'),
                _IconItem(icon: AppIcons.back, label: 'Geri'),
                _IconItem(icon: AppIcons.arrowSend, label: 'Gönder'),
                _IconItem(icon: AppIcons.arrowList, label: 'Liste'),
                _IconItem(icon: AppIcons.check, label: 'Onay'),
                _IconItem(icon: AppIcons.trophy, label: 'Kupa'),
              ],
            ),
            const SizedBox(height: AppDimens.space24),
          ],
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final String name;
  final Color color;
  final Color textColor;
  final bool hasBorder;

  const _ColorChip({
    required this.name,
    required this.color,
    required this.textColor,
    this.hasBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space10,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppDimens.borderRadiusBadge,
        border: hasBorder
            ? Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              )
            : null,
      ),
      child: Text(
        name,
        style: AppTextStyles.secondaryText.copyWith(color: textColor),
      ),
    );
  }
}

class _IconItem extends StatelessWidget {
  final AppIconData icon;
  final String label;

  const _IconItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusIconBtn,
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 24),
          const SizedBox(height: AppDimens.space4),
          Text(
            label,
            style: AppTextStyles.secondaryText,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

