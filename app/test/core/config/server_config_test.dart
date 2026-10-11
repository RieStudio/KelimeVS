@Timeout(Duration(seconds: 30))
library;

import 'package:app/core/config/server_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerConfig', () {
    test('varsayılan sunucu adresi https://api.riestudio.com.tr olmalıdır', () {
      expect(ServerConfig.defaultServerUrl, 'https://api.riestudio.com.tr');
      // dart-define verilmemişse serverUrl varsayılana eşittir
      expect(ServerConfig.serverUrl, 'https://api.riestudio.com.tr');
    });

    test('toWebSocketUrl https adresini wss adresine dönüştürür', () {
      expect(
        ServerConfig.toWebSocketUrl('https://api.riestudio.com.tr'),
        'wss://api.riestudio.com.tr',
      );
      expect(
        ServerConfig.toWebSocketUrl('https://api.example.com/'),
        'wss://api.example.com/',
      );
    });

    test('toWebSocketUrl http adresini ws adresine dönüştürür', () {
      expect(
        ServerConfig.toWebSocketUrl('http://127.0.0.1:8787'),
        'ws://127.0.0.1:8787',
      );
      expect(
        ServerConfig.toWebSocketUrl('http://localhost:8787'),
        'ws://localhost:8787',
      );
    });

    test('toWebSocketUrl zaten ws veya wss olan adresleri korur', () {
      expect(
        ServerConfig.toWebSocketUrl('wss://api.riestudio.com.tr'),
        'wss://api.riestudio.com.tr',
      );
      expect(
        ServerConfig.toWebSocketUrl('ws://127.0.0.1:8787'),
        'ws://127.0.0.1:8787',
      );
    });

    test('toWebSocketUrl şema verilmemişse wss varsayar', () {
      expect(
        ServerConfig.toWebSocketUrl('api.riestudio.com.tr'),
        'wss://api.riestudio.com.tr',
      );
    });

    test('joinUrl fazladan ya da eksik taksimleri (slash) düzeltir', () {
      expect(
        ServerConfig.joinUrl('https://example.com/', '/health'),
        'https://example.com/health',
      );
      expect(
        ServerConfig.joinUrl('https://example.com', 'health'),
        'https://example.com/health',
      );
      expect(
        ServerConfig.joinUrl('https://example.com/', 'health'),
        'https://example.com/health',
      );
    });

    test('uç nokta yolları ve tam URL yardımcıları doğru üretilir', () {
      expect(ServerConfig.healthPath, '/health');
      expect(ServerConfig.matchmakingWsPath, '/ws/matchmaking');
      expect(ServerConfig.matchWsPath('m_test_99'), '/ws/match/m_test_99');

      expect(ServerConfig.healthUrl, '${ServerConfig.serverUrl}/health');
      expect(
        ServerConfig.matchmakingWsUrl,
        '${ServerConfig.wsUrl}/ws/matchmaking',
      );
      expect(
        ServerConfig.matchWsUrl('m_123'),
        '${ServerConfig.wsUrl}/ws/match/m_123',
      );
    });
  });
}

