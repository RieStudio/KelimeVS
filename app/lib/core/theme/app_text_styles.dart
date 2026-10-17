import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTextStyles {
  static const String fontFredoka = 'Fredoka';
  static const String fontNunito = 'Nunito';

  // Logo (Fredoka, 64, 700)
  static const TextStyle logo = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
  );

  // Büyük sonuç / "Kazandın!" (Fredoka, 46, 700)
  static const TextStyle largeResult = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 46,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.15,
  );

  static const TextStyle largeResultDanger = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 46,
    fontWeight: FontWeight.w700,
    color: AppColors.dangerText,
    height: 1.15,
  );

  // Tur sonucu başlığı (Fredoka, 34, 700)
  static const TextStyle roundResultTitle = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.2,
  );

  static const TextStyle roundResultTitleDanger = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.dangerText,
    height: 1.2,
  );

  // Skorlar (Fredoka, 700)
  static const TextStyle scoreLarge = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 52,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
  );

  static const TextStyle scoreMedium = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 42,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
  );

  static const TextStyle scoreSmall = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
  );

  // Maç listesi skoru (Fredoka, 22, 700)
  static const TextStyle scoreCard = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
  );

  // Ekran başlığı (Fredoka, 22, 600)
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.2,
  );

  // Ana buton (Fredoka, 22, 600)
  static const TextStyle primaryButton = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.card,
    height: 1.2,
  );

  // Ana buton büyük / "Hızlı Maç" (Fredoka, 28, 600)
  static const TextStyle primaryButtonLarge = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.card,
    height: 1.15,
  );

  // Ana buton alt yazı (Nunito, 13, 700)
  static const TextStyle primaryButtonSubtitle = TextStyle(
    fontFamily: fontNunito,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.card,
    height: 1.2,
  );

  // İkincil buton (Fredoka, 18, 600)
  static const TextStyle secondaryButton = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.2,
  );

  // Soru metni (Fredoka, 18, 600)
  static const TextStyle questionText = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.3,
  );

  // Kart başlığı (Fredoka, 17, 600)
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.25,
  );

  // Slogan / "Hızlı düşün, doğru yaz!" (Nunito, 17, 700)
  static const TextStyle subtitle = TextStyle(
    fontFamily: fontNunito,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.muted,
    height: 1.3,
  );

  // Cevap balonu (Nunito, 15, 800)
  static const TextStyle answerBubble = TextStyle(
    fontFamily: fontNunito,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.25,
  );

  // Reddedilen cevap balonu (Nunito, 15, 800)
  static const TextStyle answerBubbleRejected = TextStyle(
    fontFamily: fontNunito,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: AppColors.dangerText,
    height: 1.25,
  );

  // Giriş alanı (Nunito, 16, 700)
  static const TextStyle inputField = TextStyle(
    fontFamily: fontNunito,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.25,
  );

  // Oyuncu adı (Nunito, 16, 800)
  static const TextStyle playerName = TextStyle(
    fontFamily: fontNunito,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.25,
  );

  // Avatar baş harfi (Fredoka, 700)
  static const TextStyle avatarInitial = TextStyle(
    fontFamily: fontFredoka,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.0,
  );

  // İkincil metin / tarih (Nunito, 12, 700)
  static const TextStyle secondaryText = TextStyle(
    fontFamily: fontNunito,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.muted,
    height: 1.2,
  );

  // Gövde metni (Nunito, 14, 700)
  static const TextStyle bodyText = TextStyle(
    fontFamily: fontNunito,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.3,
  );

  // Bölüm etiketi (BÜYÜK HARF, Nunito 12, 800, harf aralığı 0.08em)
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: fontNunito,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.96, // 12 * 0.08
    color: AppColors.muted,
    height: 1.2,
  );

  // Sonuç etiketi / ResultBadge (Nunito, 12, 800)
  static const TextStyle resultBadge = TextStyle(
    fontFamily: fontNunito,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: AppColors.card,
    height: 1.1,
  );

  // Alt gezinme etiketi (Nunito, 12, 800)
  static const TextStyle navLabel = TextStyle(
    fontFamily: fontNunito,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.1,
  );

  // Jeton hapı sayısı (Fredoka, 18, 600)
  static const TextStyle coinAmount = TextStyle(
    fontFamily: fontFredoka,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.2,
  );

  // Bağlantı uyarısı (Nunito, 13, 800)
  static const TextStyle connectionBanner = TextStyle(
    fontFamily: fontNunito,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: AppColors.dangerText,
    height: 1.2,
  );

  // Bağlantı geri geldi hapı (Nunito, 13, 800)
  static const TextStyle connectionRestored = TextStyle(
    fontFamily: fontNunito,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.2,
  );
}

