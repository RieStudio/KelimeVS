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
}

