import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../online/data/auth_token_provider.dart';
import '../domain/models/leaderboard_models.dart';

abstract interface class LeaderboardApiClient {
  Future<LeaderboardData> fetchLeaderboard();
}

class HttpLeaderboardApiClient implements LeaderboardApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  const HttpLeaderboardApiClient({
    required this.authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  });

  HttpClient _createClient(Duration timeout) {
    if (clientFactory != null) return clientFactory!();
    return HttpClient()..connectionTimeout = timeout;
  }

  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    final token = await authTokenProvider.getIdToken();
    if (token == null) {
      throw const SocketException('Yetkilendirme jetonu alınamadı');
    }

    final uri = Uri.parse(ServerConfig.leaderboardUrl);
    final client = _createClient(const Duration(seconds: 8));

    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        return LeaderboardData.fromJson(decoded);
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        throw HttpException(
          'Hesap silinmiş (410)',
          uri: uri,
        );
      } else {
        throw HttpException(
          'Sunucu hatası: ${response.statusCode}',
          uri: uri,
        );
      }
    } finally {
      client.close();
    }
  }
}

