import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/icons/app_icons.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_widgets.dart';
import '../features/dev/match_test_page.dart';
import '../features/dev/online_test_page.dart';
import '../features/dev/question_test_page.dart';
import '../features/game/application/match_providers.dart';
import '../features/game/presentation/match_screen.dart';
import '../features/online/application/network_diagnostics.dart';
import '../features/online/application/server_connection_test.dart';
import '../features/achievements/application/achievement_notification_service.dart';
import '../features/achievements/domain/achievement_ui_manifest.dart';
import '../features/achievements/presentation/achievement_notification_card.dart';
import '../features/game/application/match_ui_state.dart';
import '../features/match_request/application/match_requests_providers.dart';
import '../features/match_request/domain/match_request_models.dart';
import '../features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import '../features/match_request/presentation/widgets/match_request_toast.dart';
import '../features/match_request/presentation/widgets/outgoing_match_request_chip.dart';

/// Geliştirme sürecinde tasarım altyapısını ve tüm bileşenleri
/// canlı olarak incelemek için kullanılan galeri ekranı.
class ComponentGallery extends StatelessWidget {
  final String? authError;
  final ServerConnectionTest? serverConnectionTest;
  final NetworkDiagnostics? networkDiagnostics;

  const ComponentGallery({
    super.key,
    this.authError,
    this.serverConnectionTest,
    this.networkDiagnostics,
  });

  String get _currentUid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? AppStrings.authNoUser;
    } catch (_) {
      return AppStrings.authNoUser;
    }
  }

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
            // BAĞLANTI / HATA BİLGİSİ (Hata varsa sade hata kutusu)
            if (authError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimens.space12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSurface,
                  borderRadius: AppDimens.borderRadiusAlertBox,
                  border: Border.all(
                    color: AppColors.dangerSoft,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Text(
                  '${AppStrings.authErrorPrefix}$authError',
                  style: AppTextStyles.secondaryText.copyWith(
                    color: AppColors.dangerDark,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space16),
            ],

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

            // 3.1 TÜRKÇE TİPOGRAFİ TESTİ (Fredoka Glif Kontrolü)
            const SectionLabel('Türkçe Tipografi Testi (Fredoka & Nunito Glifleri)'),
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
                children: [
                  const Text(
                    'Fredoka Bold (w700):',
                    style: AppTextStyles.sectionLabel,
                  ),
                  const SizedBox(height: AppDimens.space6),
                  const Text(
                    'ş Ş ç Ç ğ Ğ ı İ ö Ö ü Ü',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  const Text(
                    'Fredoka SemiBold (w600):',
                    style: AppTextStyles.sectionLabel,
                  ),
                  const SizedBox(height: AppDimens.space6),
                  const Text(
                    'ş Ş ç Ç ğ Ğ ı İ ö Ö ü Ü',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFredoka,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space12),
                  const Text(
                    'Nunito Bold (Referans Karşılaştırma):',
                    style: AppTextStyles.sectionLabel,
                  ),
                  const SizedBox(height: AppDimens.space6),
                  const Text(
                    'ş Ş ç Ç ğ Ğ ı İ ö Ö ü Ü',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontNunito,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space16),
                  const Text(
                    'Buton Glifleri Doğrulama:',
                    style: AppTextStyles.sectionLabel,
                  ),
                  const SizedBox(height: AppDimens.space10),
                  SecondaryButton(
                    text: AppStrings.changeNickname,
                    onPressed: () {},
                  ),
                  const SizedBox(height: AppDimens.space10),
                  SecondaryButton.danger(
                    text: AppStrings.signOut,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space24),

            // 5. BUTONLAR
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
              text: AppStrings.rematchAction,
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

            // 6b. GÖRSEL VE PROSEDÜREL ÇERÇEVELER
            const FrameGallerySection(),
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

            // 9. DEBUG (Geliştirme Amaçlı: Firebase UID ve Soru Testi)
            if (kDebugMode) ...[
              const SectionLabel('Geliştirici / Hata Ayıklama (Debug)'),
              const SizedBox(height: AppDimens.space10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space14,
                  vertical: AppDimens.space10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppDimens.borderRadiusBadge,
                  border: Border.all(
                    color: AppColors.mint,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Text(
                  '${AppStrings.firebaseUidPrefix}$_currentUid',
                  style: AppTextStyles.secondaryText.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.space14),
              SecondaryButton(
                text: AppStrings.questionTest,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QuestionTestPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppDimens.space10),
              SecondaryButton(
                text: AppStrings.matchTest,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MatchTestPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppDimens.space10),
              Consumer(
                builder: (context, ref, _) => SecondaryButton(
                  text: AppStrings.matchScreen,
                  onPressed: () {
                    ref.read(matchControllerProvider.notifier).startMatch();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MatchScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppDimens.space10),
              SecondaryButton(
                text: AppStrings.onlineTestButton,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OnlineTestPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppDimens.space10),
              ServerTestDebugWidget(testService: serverConnectionTest),
              const SizedBox(height: AppDimens.space10),
              NetworkDiagnosticsDebugWidget(
                diagnosticsService: networkDiagnostics,
              ),
            // 4. KELİMEVS LOGO
            const SectionLabel('KelimeVS Logo (Konuşma Balonlu)'),
            const SizedBox(height: AppDimens.space10),
            Container(
              padding: const EdgeInsets.all(AppDimens.space16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppDimens.borderRadiusQuestionCard,
                border: Border.all(
                  color: AppColors.mint,
                  width: AppDimens.borderThin,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LogoPreviewCard(
                    label: 'Ana Sayfa Boyutu (64 dp):',
                    logo: KelimeVSLogo(fontSize: 64),
                  ),
                  SizedBox(height: AppDimens.space16),
                  _LogoPreviewCard(
                    label: 'Orta Boyut (52 dp):',
                    logo: KelimeVSLogo(fontSize: 52),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space24),

              const SizedBox(height: AppDimens.space24),
            ],

            // 10. ENERJİ ROZETİ (EnergyIcon - Farklı Boyutlar)
            const SectionLabel('Enerji Rozeti (EnergyIcon - Farklı Boyutlar)'),
            const SizedBox(height: AppDimens.space10),
            Wrap(
              spacing: AppDimens.space16,
              runSpacing: AppDimens.space16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: const [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 26),
                    SizedBox(height: 4),
                    Text('26dp (Kapsül)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 36),
                    SizedBox(height: 4),
                    Text('36dp (Orta)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 44),
                    SizedBox(height: 4),
                    Text('44dp (Sayaç)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 48),
                    SizedBox(height: 4),
                    Text('48dp (Kart)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 64),
                    SizedBox(height: 4),
                    Text('64dp (Modal)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EnergyIcon(size: 44, opacity: 0.25),
                    SizedBox(height: 4),
                    Text('44dp (Boş)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // 11. JETON İKONU (CoinIcon - Farklı Boyutlar)
            const SectionLabel('Jeton İkonu (CoinIcon - Farklı Boyutlar)'),
            const SizedBox(height: AppDimens.space10),
            Wrap(
              spacing: AppDimens.space16,
              runSpacing: AppDimens.space16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: const [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 16),
                    SizedBox(height: 4),
                    Text('16dp (Küçük)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 24),
                    SizedBox(height: 4),
                    Text('24dp (Kapsül)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 32),
                    SizedBox(height: 4),
                    Text('32dp (Ödül)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 48),
                    SizedBox(height: 4),
                    Text('48dp (Orta)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 72),
                    SizedBox(height: 4),
                    Text('72dp (Mağaza)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinIcon(size: 32, opacity: 0.5),
                    SizedBox(height: 4),
                    Text('32dp (Soluk)', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space24),

            // 12. BİLDİRİMLER (Banner, Çip, Tost & Başarım Bildirimleri)
            const SectionLabel('Bildirimler (Banner, Çip, Tost & Başarım Bildirimleri)'),
            const SizedBox(height: AppDimens.space10),
            const NotificationsGallerySection(),
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

/// Geliştirici modu için sunucu bağlantı testini çalıştıran ve
/// aşama sonuçlarını gösteren bileşen.
class ServerTestDebugWidget extends StatefulWidget {
  final ServerConnectionTest? testService;

  const ServerTestDebugWidget({
    super.key,
    this.testService,
  });

  @override
  State<ServerTestDebugWidget> createState() => _ServerTestDebugWidgetState();
}

class _ServerTestDebugWidgetState extends State<ServerTestDebugWidget> {
  bool _isRunning = false;
  ServerConnectionTestReport? _report;

  Future<void> _runTest() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _report = null;
    });

    try {
      final service = widget.testService ?? ServerConnectionTest();
      final report = await service.run();
      if (mounted) {
        setState(() {
          _report = report;
          _isRunning = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SecondaryButton(
          text: _isRunning
              ? AppStrings.serverTestRunning
              : AppStrings.serverTestButton,
          onPressed: _isRunning ? null : _runTest,
        ),
        if (_report != null) ...[
          const SizedBox(height: AppDimens.space10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDimens.space12),
            decoration: BoxDecoration(
              color: _report!.isOverallSuccess
                  ? AppColors.card
                  : AppColors.dangerSurface,
              borderRadius: AppDimens.borderRadiusCardLarge,
              border: Border.all(
                color: _report!.isOverallSuccess
                  ? AppColors.ink
                  : AppColors.dangerDark,
                width: AppDimens.borderThin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final step in _report!.steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimens.space4,
                    ),
                    child: Text(
                      '${step.stepName}: ${step.isSuccess ? 'Tamam' : 'HATA (${step.errorMessage})'} (${step.durationMs} ms)',
                      style: AppTextStyles.secondaryText.copyWith(
                        color: step.isSuccess
                            ? AppColors.ink
                            : AppColors.dangerDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: AppDimens.space8),
                Text(
                  _report!.isOverallSuccess
                      ? '${AppStrings.serverTestSuccessSummary} (${_report!.totalDurationMs} ms)'
                      : '${AppStrings.serverTestFailedSummary}: ${_report!.failureMessage ?? ''}',
                  style: AppTextStyles.secondaryText.copyWith(
                    color: _report!.isOverallSuccess
                        ? AppColors.ink
                        : AppColors.dangerDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Geliştirici modu için ağ tanılama testini çalıştıran ve
/// hedef sonuçlarını gösteren bileşen.
class NetworkDiagnosticsDebugWidget extends StatefulWidget {
  final NetworkDiagnostics? diagnosticsService;

  const NetworkDiagnosticsDebugWidget({
    super.key,
    this.diagnosticsService,
  });

  @override
  State<NetworkDiagnosticsDebugWidget> createState() =>
      _NetworkDiagnosticsDebugWidgetState();
}

class _NetworkDiagnosticsDebugWidgetState
    extends State<NetworkDiagnosticsDebugWidget> {
  bool _isRunning = false;
  NetworkDiagnosticsReport? _report;

  Future<void> _runDiagnostics() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _report = null;
    });

    try {
      final service = widget.diagnosticsService ?? const NetworkDiagnostics();
      final report = await service.run();
      if (mounted) {
        setState(() {
          _report = report;
          _isRunning = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SecondaryButton(
          text: _isRunning
              ? AppStrings.networkDiagnosticsRunning
              : AppStrings.networkDiagnosticsButton,
          onPressed: _isRunning ? null : _runDiagnostics,
        ),
        if (_report != null) ...[
          const SizedBox(height: AppDimens.space10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDimens.space12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppDimens.borderRadiusCardLarge,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.networkDiagnosticsTitle,
                  style: AppTextStyles.secondaryText.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                for (final result in _report!.results)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimens.space4,
                    ),
                    child: Text(
                      result.summaryLine,
                      style: AppTextStyles.secondaryText.copyWith(
                        color: result.isSuccess
                            ? AppColors.ink
                            : AppColors.dangerDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: AppDimens.space8),
                Text(
                  'Toplam süre: ${_report!.totalDurationMs} ms',
                  style: AppTextStyles.secondaryText.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LogoPreviewCard extends StatelessWidget {
  final String label;
  final Widget logo;

  const _LogoPreviewCard({
    required this.label,
    required this.logo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTextStyles.secondaryText.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.space12),
          Center(child: logo),
        ],
      ),
    );
  }
}

class FrameGallerySection extends StatefulWidget {
  const FrameGallerySection({super.key});

  @override
  State<FrameGallerySection> createState() => FrameGallerySectionState();
}

class FrameGallerySectionState extends State<FrameGallerySection> {
  bool _showDebugRedRing = false;

  Widget _buildAvatarWithGuide({
    required String frameId,
    required double size,
  }) {
    final avatar = PlayerAvatar.selfMatch(
      name: 'A',
      frame: frameId,
      size: size,
    );

    if (!_showDebugRedRing) return avatar;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        avatar,
        IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.redAccent,
                width: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionLabel('Çerçeve Galerisi (36, 44, 72, 88, 104 dp)'),
            ),
            const Text(
              'Kılavuz',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            Switch(
              key: const ValueKey('debug_frame_red_ring_switch'),
              value: _showDebugRedRing,
              activeTrackColor: Colors.redAccent.withValues(alpha: 0.5),
              activeThumbColor: Colors.redAccent,
              onChanged: (val) {
                setState(() {
                  _showDebugRedRing = val;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final frame in [
                ('classic', 'Klasik'),
                ('vine', 'Sarmaşık'),
                ('silver_engraved', 'Gümüş'),
                ('bronze_engraved', 'Bronz'),
                ('gold_leaf', 'Altın'),
                ('emerald', 'Zümrüt'),
                ('sakura', 'Kiraz Çiçeği'),
                ('ice', 'Buz'),
                ('gear', 'Dişli'),
                ('nazar', 'Nazar Boncuğu'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      Text(
                        frame.$2,
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      const Text('104 dp', style: AppTextStyles.secondaryText),
                      const SizedBox(height: 4),
                      _buildAvatarWithGuide(frameId: frame.$1, size: 104),
                      const SizedBox(height: 8),
                      const Text('88 dp', style: AppTextStyles.secondaryText),
                      const SizedBox(height: 4),
                      _buildAvatarWithGuide(frameId: frame.$1, size: 88),
                      const SizedBox(height: 8),
                      const Text('72 dp', style: AppTextStyles.secondaryText),
                      const SizedBox(height: 4),
                      _buildAvatarWithGuide(frameId: frame.$1, size: 72),
                      const SizedBox(height: 8),
                      const Text('44 dp', style: AppTextStyles.secondaryText),
                      const SizedBox(height: 4),
                      _buildAvatarWithGuide(frameId: frame.$1, size: 44),
                      const SizedBox(height: 8),
                      const Text('36 dp', style: AppTextStyles.secondaryText),
                      const SizedBox(height: 4),
                      _buildAvatarWithGuide(frameId: frame.$1, size: 36),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Geliştirici galerisinde projedeki tüm bildirim, banner, çip, tost ve
/// başarım bildirimlerini canlı ve statik olarak sergileyen bölüm.
class NotificationsGallerySection extends StatelessWidget {
  const NotificationsGallerySection({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context);
      return const _NotificationsGallerySectionContent();
    } catch (_) {
      return const ProviderScope(
        child: _NotificationsGallerySectionContent(),
      );
    }
  }
}

class _NotificationsGallerySectionContent extends ConsumerStatefulWidget {
  const _NotificationsGallerySectionContent();

  @override
  ConsumerState<_NotificationsGallerySectionContent> createState() =>
      _NotificationsGallerySectionContentState();
}

class _NotificationsGallerySectionContentState
    extends ConsumerState<_NotificationsGallerySectionContent> {
  // ConnectionBanner durumları
  ConnectionStatus _connectionStatus = ConnectionStatus.reconnecting;
  bool _opponentConnected = true;

  // Başarım bildirim seçimi
  String _selectedAchievementId = 'first_match';

  // Son etkileşim metni
  String? _lastActionNote;

  void _setNote(String note) {
    setState(() {
      _lastActionNote = note;
    });
  }

  Widget _buildStatusChip({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.card : AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildToastItem(
    BuildContext context, {
    required String label,
    required String message,
    required bool isDanger,
    required String iconCode,
  }) {
    final iconCfg = matchRequestToastIconForCode(iconCode);
    return InkWell(
      onTap: () {
        ref.read(matchRequestToastProvider.notifier).showToast(
              message,
              isDanger: isDanger,
              iconAsset: iconCfg?.assetPath,
              iconColor: iconCfg?.color,
            );
        _setNote('Tost global overlay üzerinde tetiklendi: $label');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          MatchRequestToastWidget(
            message: message,
            isDanger: isDanger,
            iconAsset: iconCfg?.assetPath,
            iconColor: iconCfg?.color,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final achievementState = ref.watch(achievementNotificationProvider);
    final selectedItem = AchievementUiManifest.get(_selectedAchievementId) ??
        AchievementUiManifest.items.values.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lastActionNote != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space12,
              vertical: AppDimens.space8,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppDimens.borderRadiusBadge,
              border: Border.all(
                color: AppColors.bright,
                width: AppDimens.borderThin,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.ink),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Text(
                    _lastActionNote!,
                    style: AppTextStyles.secondaryText.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.space14),
        ],

        // a) Gelen Maç İsteği Bildirim Bandı
        Text(
          'a) Gelen Maç İsteği Bandı (IncomingMatchRequestBanner)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space6),
        IncomingMatchRequestBanner(
          request: IncomingMatchRequest(
            id: 'gallery_in_1',
            fromUid: 'u_gallery_1',
            fromNickname: 'Ahmet',
            fromFrame: 'emerald',
            type: MatchRequestType.friendly,
            origin: MatchRequestOrigin.profile,
            expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
          ),
          enableCountdownTicker: false,
          onAccept: () => _setNote('Gelen istek kabul edildi (örnek tetikleyici)'),
          onDecline: () => _setNote('Gelen istek reddedildi (örnek tetikleyici)'),
        ),
        const SizedBox(height: AppDimens.space16),

        // b) Giden Maç İsteği Bilgi Çipi
        Text(
          'b) Giden Maç İsteği Çipi (OutgoingMatchRequestChip)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space6),
        Center(
          child: OutgoingMatchRequestChip(
            request: OutgoingMatchRequest(
              id: 'gallery_out_1',
              toUid: 'u_gallery_2',
              toNickname: 'Zeynep',
              type: MatchRequestType.friendly,
              origin: MatchRequestOrigin.profile,
              expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
            ),
            enablePeriodicTicker: false,
            onCancel: () => _setNote('Giden istek iptal edildi'),
          ),
        ),
        const SizedBox(height: AppDimens.space16),

        // c) Maç İsteği Tostları
        Text(
          'c) Maç İsteği Tostları (MatchRequestToastWidget - Tüm Varyantlar)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space4),
        const Text(
          'Tostlara dokunarak global overlay üzerinde canlı olarak görebilirsiniz:',
          style: AppTextStyles.secondaryText,
        ),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space8,
          children: [
            _buildToastItem(
              context,
              label: 'Reddedildi',
              message: AppStrings.matchRequestDeclinedToast,
              isDanger: true,
              iconCode: 'declined',
            ),
            _buildToastItem(
              context,
              label: 'Zaman Aşımı',
              message: AppStrings.matchRequestExpiredToast,
              isDanger: false,
              iconCode: 'expired',
            ),
            _buildToastItem(
              context,
              label: 'Müsait Değil',
              message: AppStrings.matchRequestUnavailableToast,
              isDanger: false,
              iconCode: 'unavailable',
            ),
            _buildToastItem(
              context,
              label: 'Kabul Edilemedi',
              message: AppStrings.matchRequestUnavailableForAcceptToast,
              isDanger: false,
              iconCode: 'unavailable',
            ),
            _buildToastItem(
              context,
              label: 'Çevrimdışı',
              message: AppStrings.matchRequestOfflineToast,
              isDanger: false,
              iconCode: 'offline',
            ),
            _buildToastItem(
              context,
              label: 'İstekler Kapalı',
              message: AppStrings.matchRequestDisabledToast,
              isDanger: false,
              iconCode: 'requests_disabled',
            ),
            _buildToastItem(
              context,
              label: 'Bekleme Süresi (45s)',
              message: AppStrings.matchRequestCooldownToast(45),
              isDanger: false,
              iconCode: 'cooldown_active',
            ),
            _buildToastItem(
              context,
              label: 'İstek Sıklığı',
              message: AppStrings.matchRequestRateLimitedToast,
              isDanger: false,
              iconCode: 'rate_limited',
            ),
            _buildToastItem(
              context,
              label: 'Gönderilemedi',
              message: AppStrings.matchRequestInvalidToast,
              isDanger: false,
              iconCode: 'invalid',
            ),
            _buildToastItem(
              context,
              label: 'Rakip Enerjisi Yok',
              message: AppStrings.matchRequestOpponentNoEnergyToast,
              isDanger: false,
              iconCode: 'opponent_no_energy',
            ),
            _buildToastItem(
              context,
              label: 'Kabul Edildi / Başladı',
              message: 'İstek kabul edildi!',
              isDanger: false,
              iconCode: 'accepted',
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),

        // d) Bağlantı Uyarısı ve Küresel Ağ Bandı
        Text(
          'd) Bağlantı Bandı (ConnectionBanner & GlobalOfflineBanner)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space6,
          children: [
            _buildStatusChip(
              title: 'Yeniden Bağlanıyor',
              isSelected: _connectionStatus == ConnectionStatus.reconnecting &&
                  _opponentConnected,
              onTap: () => setState(() {
                _connectionStatus = ConnectionStatus.reconnecting;
                _opponentConnected = true;
              }),
            ),
            _buildStatusChip(
              title: 'Kalıcı Koptu (Disconnected)',
              isSelected: _connectionStatus ==
                      ConnectionStatus.permanentDisconnected &&
                  _opponentConnected,
              onTap: () => setState(() {
                _connectionStatus = ConnectionStatus.permanentDisconnected;
                _opponentConnected = true;
              }),
            ),
            _buildStatusChip(
              title: 'Tekrar Bağlandı (Pill)',
              isSelected: _connectionStatus == ConnectionStatus.connected &&
                  _opponentConnected,
              onTap: () => setState(() {
                _connectionStatus = ConnectionStatus.connected;
                _opponentConnected = true;
              }),
            ),
            _buildStatusChip(
              title: 'Rakip Koptu',
              isSelected: !_opponentConnected,
              onTap: () => setState(() {
                _connectionStatus = ConnectionStatus.connected;
                _opponentConnected = false;
              }),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThin,
            ),
          ),
          child: ClipRRect(
            borderRadius: AppDimens.borderRadiusListCard,
            child: Stack(
              children: [
                const Center(
                  child: Text(
                    'Oyun Ekranı Alanı',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ConnectionBanner(
                    status: _connectionStatus,
                    opponentConnected: _opponentConnected,
                    debounceDuration: Duration.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.space10),
        const Text(
          'Uygulama Geneli Çevrimdışı Bandı (GlobalOfflineBanner):',
          style: AppTextStyles.secondaryText,
        ),
        const SizedBox(height: AppDimens.space6),
        GlobalOfflineBanner(
          isChecking: false,
          onRetry: () => _setNote('Ağ yeniden kontrol ediliyor'),
        ),
        const SizedBox(height: AppDimens.space16),

        // e) Başarım Bildirimi
        Text(
          'e) Başarım Bildirimi (AchievementNotificationCard & Global Overlay)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space4),
        const Text(
          'Kart Önizlemesi (3px çerçeve, 4px gölge, sol taşan -6° SVG, 58px sol boşluk):',
          style: AppTextStyles.secondaryText,
        ),
        const SizedBox(height: AppDimens.space8),
        AchievementNotificationCard(
          item: selectedItem,
          onDismiss: () => _setNote('Önizleme kartına dokunuldu'),
        ),
        const SizedBox(height: AppDimens.space12),
        const Text(
          '11 Başarım Seçimi (Dokunarak seçin ve tetikleyin):',
          style: AppTextStyles.secondaryText,
        ),
        const SizedBox(height: AppDimens.space6),
        Wrap(
          spacing: AppDimens.space6,
          runSpacing: AppDimens.space6,
          children: [
            for (final item in AchievementUiManifest.items.values)
              ChoiceChip(
                label: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _selectedAchievementId == item.id
                        ? AppColors.card
                        : AppColors.ink,
                  ),
                ),
                selected: _selectedAchievementId == item.id,
                selectedColor: AppColors.ink,
                backgroundColor: AppColors.card,
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedAchievementId = item.id;
                    });
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: AppDimens.space10),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space8,
          children: [
            SecondaryButton(
              text: 'Seçili Başarımı Göster (Hemen)',
              onPressed: () {
                ref
                    .read(achievementNotificationProvider.notifier)
                    .show(_selectedAchievementId, initialDelay: Duration.zero);
                _setNote('Başarım bildirimi gönderildi: ${selectedItem.title}');
              },
            ),
            SecondaryButton(
              text: 'Seçili Başarımı Göster (600ms gecikmeli)',
              onPressed: () {
                ref.read(achievementNotificationProvider.notifier).show(
                      _selectedAchievementId,
                      initialDelay: const Duration(milliseconds: 600),
                    );
                _setNote(
                  '600ms gecikmeli başarım gönderildi: ${selectedItem.title}',
                );
              },
            ),
            PrimaryButton(
              text: "3'lü Seri Başarım Göster (FIFO Kuyruk Testi)",
              onPressed: () {
                ref.read(achievementNotificationProvider.notifier).showAll(
                  ['streak_3', 'matches_10', 'first_win'],
                  initialDelay: Duration.zero,
                );
                _setNote(
                  "3'lü seri başarım sıraya alındı (streak_3 -> matches_10 -> first_win)",
                );
              },
            ),
            SecondaryButton(
              text: 'Bekleyen Kuyruğu Temizle',
              onPressed: () {
                ref.read(achievementNotificationProvider.notifier).clearQueue();
                _setNote('Bekleyen başarım kuyruğu temizlendi');
              },
            ),
          ],
        ),
        if (achievementState.currentItem != null) ...[
          const SizedBox(height: AppDimens.space8),
          Text(
            'Aktif Gösterilen: ${achievementState.currentItem!.title} | Kuyrukta Kalan: ${ref.read(achievementNotificationProvider.notifier).queueLength}',
            style: AppTextStyles.secondaryText.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: AppDimens.space16),

        // f) Diğer Bildirimler (SnackBarlar)
        Text(
          'f) Sistem Uyarıları (Kayan SnackBar Çeşitleri)',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space8,
          children: [
            SecondaryButton(
              text: 'Bilgi SnackBar Göster',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profil başarıyla güncellendi.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            SecondaryButton(
              text: 'Hata SnackBar Göster',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(AppStrings.noInternetActionError),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),

        // Bölüm Özeti
        Container(
          padding: const EdgeInsets.all(AppDimens.space14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusListCard,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Listelenen Bildirim Türleri Özeti:',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFredoka,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: AppDimens.space6),
              Text(
                '1. Gelen Maç İsteği Bildirim Bandı (IncomingMatchRequestBanner): Üstten kayan davet bandı (Kabul / Red).\n'
                '2. Giden Maç İsteği Bilgi Çipi (OutgoingMatchRequestChip): Geri sayımlı kompakt bekleme çipi (İptal).\n'
                '3. Maç İsteği Tostları (MatchRequestToastWidget): 10 farklı durum ikonu ve renk varyantıyla hızlı geri bildirim.\n'
                '4. Bağlantı Uyarı Şeridi (ConnectionBanner): Kopma, yeniden bağlanma ve 1.5 sn "Bağlandı" hapı.\n'
                '5. Küresel Çevrimdışı Bandı (GlobalOfflineBanner): Ağ kesintisinde tüm ekranların üstünde sabit bant.\n'
                '6. Başarım Bildirimi (AchievementNotificationCard): Üstten hafif yaylanarak inen, -6° rozetli, 4000 ms süreli ve FIFO kuyruklu bildirim.\n'
                '7. Kayan Sistem Uyarıları (Floating SnackBar): Hızlı işlem sonuçları ve kullanıcı bilgilendirmeleri.',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontNunito,
                  fontSize: 12,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

