import 'dart:async';
import 'dart:io';

import '../../../core/config/server_config.dart';
import '../../../core/network/auth_http_executor.dart';
import '../../online/data/auth_token_provider.dart';
import '../../profile/domain/energy_state.dart';

/// Solo maç sonucunun sunucuya iletilmesi için gerekli istek gövdesi.
class SoloMatchSubmission {
  final String matchId;
  final String outcome; // 'win' | 'loss'
  final int myScore;
  final int oppScore;
  final int correctAnswers;
  final int durationSeconds;
  final String endedBy; // 'normal' | 'forfeit'
  final int submittedAtMs;

  const SoloMatchSubmission({
    required this.matchId,
    required this.outcome,
    required this.myScore,
    required this.oppScore,
    required this.correctAnswers,
    required this.durationSeconds,
    required this.endedBy,
    required this.submittedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'outcome': outcome,
        'myScore': myScore,
        'oppScore': oppScore,
        'correctAnswers': correctAnswers,
        'durationSeconds': durationSeconds,
        'endedBy': endedBy,
        'submittedAtMs': submittedAtMs,
      };

  factory SoloMatchSubmission.fromJson(Map<String, dynamic> json) {
    return SoloMatchSubmission(
      matchId: json['matchId'] as String? ?? '',
      outcome: json['outcome'] as String? ?? 'loss',
      myScore: (json['myScore'] as num?)?.toInt() ?? 0,
      oppScore: (json['oppScore'] as num?)?.toInt() ?? 0,
      correctAnswers: (json['correctAnswers'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      endedBy: json['endedBy'] as String? ?? 'normal',
      submittedAtMs: (json['submittedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Solo maç sonucu bildiriminden dönen yanıt mühürlü hiyerarşisi.
sealed class SubmitSoloMatchResult {
  const SubmitSoloMatchResult();
}

/// Sunucu 200 OK yanıtı döndüğünde.
class SubmitSoloMatchSuccess extends SubmitSoloMatchResult {
  final bool ok;
  final bool counted;
  final bool alreadyProcessed;
  final int coinsAwarded;
  final int coins;
  final EnergyState? energy;
  final List<String> unlockedAchievements;

  const SubmitSoloMatchSuccess({
    required this.ok,
    required this.counted,
    this.alreadyProcessed = false,
    required this.coinsAwarded,
    required this.coins,
    this.energy,
    this.unlockedAchievements = const [],
  });
}

/// Kalıcı hata (400 geçersiz gövde veya 410 silinmiş hesap). Tekrar denenmez.
class SubmitSoloMatchPermanentError extends SubmitSoloMatchResult {
  final int statusCode;
  final String error;
  final String? message;

  const SubmitSoloMatchPermanentError({
    required this.statusCode,
    required this.error,
    this.message,
  });
}

/// Geçici hata (ağ kesintisi, zaman aşımı, 401 veya 5xx). Yerel bekleme kuyruğunda saklanır.
class SubmitSoloMatchTransientError extends SubmitSoloMatchResult {
  final String message;
  final Object? error;

  const SubmitSoloMatchTransientError([
    this.message = 'Geçici bağlantı hatası',
    this.error,
  ]);
}

/// Solo maç sonucu API istemcisi soyut arayüzü.
abstract interface class SoloMatchApiClient {
  Future<SubmitSoloMatchResult> submit(SoloMatchSubmission submission);
}

/// Kimlik doğrulamalı HTTP isteklerini yürüten somut [SoloMatchApiClient] uygulaması.
class HttpSoloMatchApiClient implements SoloMatchApiClient {
  final AuthTokenProvider authTokenProvider;
  final HttpClient Function()? clientFactory;
  final void Function()? onAccountDeleted;

  const HttpSoloMatchApiClient({
    required this.authTokenProvider,
    this.clientFactory,
    this.onAccountDeleted,
  });

  @override
  Future<SubmitSoloMatchResult> submit(SoloMatchSubmission submission) async {
    final uri = Uri.parse(ServerConfig.soloMatchUrl);

    try {
      final response = await AuthHttpExecutor.execute(
        authTokenProvider: authTokenProvider,
        uri: uri,
        method: 'POST',
        clientFactory: clientFactory,
        jsonBody: {
          'matchId': submission.matchId,
          'outcome': submission.outcome,
          'myScore': submission.myScore,
          'oppScore': submission.oppScore,
          'correctAnswers': submission.correctAnswers,
          'durationSeconds': submission.durationSeconds,
          'endedBy': submission.endedBy,
        },
        timeout: const Duration(seconds: 4),
      );

      if (response == null) {
        return const SubmitSoloMatchTransientError();
      }

      if (response.statusCode == 200) {
        final decoded = response.decodeJsonMap();
        final ok = decoded['ok'] == true;
        final counted = decoded['counted'] == true;
        final alreadyProcessed = decoded['alreadyProcessed'] == true;
        final coinsAwarded = (decoded['coinsAwarded'] as num?)?.toInt() ?? 0;
        final coins = (decoded['coins'] as num?)?.toInt() ?? 0;
        final energyJson = decoded['energy'] as Map<String, dynamic>?;
        final energy = energyJson != null ? EnergyState.fromJson(energyJson) : null;
        final rawAchievements = decoded['unlockedAchievements'] as List<dynamic>?;
        final unlocked =
            rawAchievements?.map((e) => e.toString()).toList() ?? const <String>[];

        return SubmitSoloMatchSuccess(
          ok: ok,
          counted: counted,
          alreadyProcessed: alreadyProcessed,
          coinsAwarded: coinsAwarded,
          coins: coins,
          energy: energy,
          unlockedAchievements: unlocked,
        );
      } else if (response.statusCode == 410) {
        onAccountDeleted?.call();
        return const SubmitSoloMatchPermanentError(
          statusCode: 410,
          error: 'account_deleted',
          message: 'Hesap silinmiş',
        );
      } else if (response.statusCode == 400) {
        String error = 'bad_request';
        String? message;
        try {
          final decoded = response.decodeJsonMap();
          error = decoded['error'] as String? ?? error;
          message = decoded['message'] as String?;
        } catch (_) {}
        return SubmitSoloMatchPermanentError(
          statusCode: 400,
          error: error,
          message: message,
        );
      } else if (response.statusCode == 401) {
        return const SubmitSoloMatchTransientError(
          'Oturum süresi doldu veya yetkisiz istek',
        );
      }

      return SubmitSoloMatchTransientError(
        'Sunucu hatası: ${response.statusCode}',
      );
    } catch (e) {
      return SubmitSoloMatchTransientError('Geçici bağlantı hatası', e);
    }
  }
}
