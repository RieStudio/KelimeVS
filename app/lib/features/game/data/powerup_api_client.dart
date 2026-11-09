import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
import '../../../core/strings/app_strings.dart';
import '../../online/data/auth_token_provider.dart';

/// Güçlendirici harcama işleminden dönebilen sonuçların mühürlü sınıfı.
sealed class SpendPowerupResult {
  const SpendPowerupResult();
}

/// Harcama başarılı olduğunda dönen sonuç.
class SpendPowerupSuccess extends SpendPowerupResult {
  final int coins;
  final bool alreadySpent;

  const SpendPowerupSuccess({
    required this.coins,
    this.alreadySpent = false,
  });
}

/// Yetersiz jeton durumunda dönen sonuç.
class SpendPowerupNotEnoughCoins extends SpendPowerupResult {
  final int coins;

  const SpendPowerupNotEnoughCoins({required this.coins});
}

/// Kullanıcının hesabı silinmişse (tombstone) dönen sonuç.
class SpendPowerupAccountDeleted extends SpendPowerupResult {
  const SpendPowerupAccountDeleted();
}

/// Geçersiz istek (hatalı matchId, bilinmeyen powerup vb.) durumunda dönen sonuç.
class SpendPowerupBadRequest extends SpendPowerupResult {
  final String message;

  const SpendPowerupBadRequest([this.message = 'Geçersiz istek']);
}

/// Ağ hatası, zaman aşımı (3 sn), 401 veya 5xx durumlarında dönen sonuç.
class SpendPowerupNetworkError extends SpendPowerupResult {
  final String message;
  final Object? error;

  const SpendPowerupNetworkError([
    this.message = AppStrings.powerupTemporaryError,
    this.error,
  ]);
}

/// Bot maçı güçlendirici harcama istemcisi soyut arayüzü.
abstract interface class PowerupApiClient {
  /// Sunucudaki POST /powerups/spend uç noktasını çağırarak jeton harcamasını gerçekleştirir.
  Future<SpendPowerupResult> spend({
    required String matchId,
    required String powerup,
  });
}

/// Kimlik doğrulamalı HTTP isteklerini yürüten somut [PowerupApiClient] uygulaması.
class HttpPowerupApiClient implements PowerupApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  const HttpPowerupApiClient({
    required this.authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  });

  @override
  Future<SpendPowerupResult> spend({
    required String matchId,
    required String powerup,
  }) async {
    final uri = Uri.parse(ServerConfig.powerupsSpendUrl);

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
        jsonBody: {
          'matchId': matchId,
          'powerup': powerup,
        },
        timeout: const Duration(seconds: 3),
      );

      if (response == null) {
        return const SpendPowerupNetworkError();
      }

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        final coins = (decoded['coins'] as num?)?.toInt() ?? 0;
        final alreadySpent = (decoded['alreadySpent'] as bool?) ?? false;
        return SpendPowerupSuccess(
          coins: coins,
          alreadySpent: alreadySpent,
        );
      } else if (response.statusCode == 402) {
        final decoded = response.decodeJsonMap();
        final coins = (decoded['coins'] as num?)?.toInt() ?? 0;
        return SpendPowerupNotEnoughCoins(coins: coins);
      } else if (response.statusCode == 400) {
        String message = 'Geçersiz istek';
        try {
          final decoded = response.decodeJsonMap();
          message = decoded['message'] as String? ?? message;
        } catch (_) {}
        return SpendPowerupBadRequest(message);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const SpendPowerupAccountDeleted();
      } else if (response.statusCode == 401) {
        return const SpendPowerupNetworkError(
          'Oturum süresi doldu veya yetkisiz istek',
        );
      }

      return SpendPowerupNetworkError(
        'Sunucu hatası: ${response.statusCode}',
      );
    } catch (e) {
      return SpendPowerupNetworkError(AppStrings.powerupTemporaryError, e);
    }
  }
}

const _botMatchIdChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Bot maç oturumları için sunucu doğrulama regex'ine (^bot:[A-Za-z0-9_-]{8,64}$)
/// tam uyumlu opak kimlik üretir.
///
/// Varsayılan olarak [math.Random.secure] kullanır. Testler için [random] enjekte edilebilir.
String generateBotMatchId([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  final buffer = StringBuffer('bot:');
  for (var i = 0; i < 24; i++) {
    buffer.write(_botMatchIdChars[rng.nextInt(_botMatchIdChars.length)]);
  }
  return buffer.toString();
}
