import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/profile_notifier.dart';
import '../data/solo_match_api_client.dart';
import '../data/solo_match_queue_repository.dart';

/// Solo maç bekleme kuyruğunu yöneten ve arka planda yeniden deneyen yönetici sınıf.
class SoloMatchQueueManager {
  final SoloMatchQueueRepository repository;
  final SoloMatchApiClient apiClient;
  final Ref ref;

  bool _isProcessing = false;

  SoloMatchQueueManager({
    required this.repository,
    required this.apiClient,
    required this.ref,
  });

  /// Bekleyen solo maç sonuçlarını sırayla sunucuya iletir.
  /// UI'ı asla bloklamaz ve hata fırlatmaz.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queue = await repository.getPendingSubmissions();
      if (queue.isEmpty) return;

      for (final submission in queue) {
        final result = await apiClient.submit(submission);

        if (result is SubmitSoloMatchSuccess) {
          // Başarılı (veya alreadyProcessed) veya counted:false -> kuyruktan kaldır
          await repository.remove(submission.matchId);

          if (result.counted) {
            // Jeton ve enerjiyi sessizce profil durumuna uygula
            await ref.read(profileProvider.notifier).updateCoins(result.coins);
            if (result.energy != null) {
              ref.read(profileProvider.notifier).updateEnergy(result.energy!);
            }
            unawaited(ref.read(profileProvider.notifier).syncWithServer());
          }
        } else if (result is SubmitSoloMatchPermanentError) {
          // 400 geçersiz gövde veya 410 silinmiş hesap -> kuyruktan sil, tekrar deneme
          await repository.remove(submission.matchId);
        } else if (result is SubmitSoloMatchTransientError) {
          // Geçici ağ hatası: kuyrukta kalsın, sunucu/bağlantı düzelince tekrar denensin.
          // Arka arkaya başarısız istek atmamak için döngüyü kes
          break;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SoloMatchQueueManager] processQueue error: $e');
      }
    } finally {
      _isProcessing = false;
    }
  }
}
