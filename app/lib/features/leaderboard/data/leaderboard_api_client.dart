import 'dart:async';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
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

  @override
  Future<LeaderboardData> fetchLeaderboard() async {
    final uri = Uri.parse(ServerConfig.leaderboardUrl);

    final response = await AuthHttpExecutor.execute(
      authTokenProvider: authTokenProvider,
      uri: uri,
      method: 'GET',
      clientFactory: clientFactory,
    );

    if (response == null) {
      throw const SocketException('Yetkilendirme jetonu alınamadı');
    }

    if (response.statusCode == 200) {
      final decoded = response.decodeJsonMap();
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
  }
}
