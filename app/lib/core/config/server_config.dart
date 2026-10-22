/// Sunucu adresi, WebSocket URL dönüşümü ve uç nokta yapılandırması.
///
/// Varsayılan sunucu adresi [defaultServerUrl]'dir.
/// `--dart-define=SERVER_URL=...` derleme bayrağı ile dinamik olarak ezilebilir.
abstract final class ServerConfig {
  /// Varsayılan sunucu adresi.
  static const String defaultServerUrl = 'https://api.riestudio.com.tr';

  /// Ortam değişkeninden (`--dart-define=SERVER_URL=...`) alınan veya varsayılan sunucu adresi.
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: defaultServerUrl,
  );

  /// HTTP(S) adresini WebSocket (WS/WSS) adresine dönüştürür.
  ///
  /// - `https://example.com` -> `wss://example.com`
  /// - `http://localhost:8787` -> `ws://localhost:8787`
  /// - Zaten `wss://` veya `ws://` ile başlıyorsa aynen döner.
  static String toWebSocketUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('https://')) {
      return 'wss://${trimmed.substring('https://'.length)}';
    } else if (trimmed.startsWith('http://')) {
      return 'ws://${trimmed.substring('http://'.length)}';
    } else if (trimmed.startsWith('wss://') || trimmed.startsWith('ws://')) {
      return trimmed;
    }
    return 'wss://$trimmed';
  }

  /// Sunucunun WebSocket ana adresi.
  static String get wsUrl => toWebSocketUrl(serverUrl);

  /// Sağlık kontrolü yolu.
  static const String healthPath = '/health';

  /// Kullanıcı profili yolu.
  static const String mePath = '/me';

  /// Takma ad güncelleme yolu.
  static const String nicknamePath = '/me/nickname';

  /// Çerçeve kuşanma yolu.
  static const String framePath = '/me/frame';

  /// Mağaza durumu yolu.
  static const String storePath = '/store';

  /// Satın alma yolu.
  static const String purchasePath = '/store/purchase';

  /// Enerji satın alma yolu.
  static const String energyPath = '/store/energy';

  /// Liderlik tablosu yolu.
  static const String leaderboardPath = '/leaderboard';

  /// Eşleştirme WebSocket yolu.
  static const String matchmakingWsPath = '/ws/matchmaking';

  /// Maç WebSocket yolu şablonu.
  static String matchWsPath(String matchId) => '/ws/match/$matchId';

  /// Tam Sağlık Kontrolü HTTP URL'si.
  static String get healthUrl => joinUrl(serverUrl, healthPath);

  /// Tam Profil HTTP URL'si.
  static String get meUrl => joinUrl(serverUrl, mePath);

  /// Tam Takma Ad Güncelleme HTTP URL'si.
  static String get nicknameUrl => joinUrl(serverUrl, nicknamePath);

  /// Tam Çerçeve Güncelleme HTTP URL'si.
  static String get frameUrl => joinUrl(serverUrl, framePath);

  /// Tam Mağaza HTTP URL'si.
  static String get storeUrl => joinUrl(serverUrl, storePath);

  /// Tam Satın Alma HTTP URL'si.
  static String get purchaseUrl => joinUrl(serverUrl, purchasePath);

  /// Tam Enerji Satın Alma HTTP URL'si.
  static String get energyUrl => joinUrl(serverUrl, energyPath);

  /// Tam Liderlik Tablosu HTTP URL'si.
  static String get leaderboardUrl => joinUrl(serverUrl, leaderboardPath);

  /// Tam Eşleştirme WebSocket URL'si.
  static String get matchmakingWsUrl => joinUrl(wsUrl, matchmakingWsPath);

  /// Tam Maç WebSocket URL'si.
  static String matchWsUrl(String matchId) =>
      joinUrl(wsUrl, matchWsPath(matchId));

  /// İki URL parçasını güvenle birleştirir.
  static String joinUrl(String base, String path) {
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$cleanBase$cleanPath';
  }
}
