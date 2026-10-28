// TODO: ekonomi kararı

/// Uygulama yapılandırması ve geçici sabitler.
abstract final class AppConfig {
  /// Maç kazanma jeton ödülü (geçici sabit).
  static const int matchWinCoinReward = 30;

  /// Maç kaybetme jeton ödülü (geçici sabit).
  static const int matchLoseCoinReward = 10;

  // TODO: İleride Firebase Remote Config'e bağlanacak
  /// Çevrimiçi eşleştirmenin aktif olup olmadığı (kur-bırak düğmesi).
  /// `--dart-define=ONLINE_MATCHMAKING=false` ile kapatılabilir.
  static const bool onlineMatchmakingEnabled = bool.fromEnvironment(
    'ONLINE_MATCHMAKING',
    defaultValue: true,
  );

  /// Gizlilik Politikası web sayfası adresi.
  static const String privacyPolicyUrl =
      'https://riestudio.com.tr/privacy/kelimevs';

  /// Destek ve iletişim e-posta adresi.
  static const String supportEmail = 'contact@riestudio.com.tr';

  /// Destek e-postası varsayılan konu başlığı.
  static const String supportSubject = 'KelimeVS Destek';
}

