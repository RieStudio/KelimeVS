import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'solo_match_api_client.dart';

/// Gönderilemeyen solo maç sonuçlarının yerel bekleme kuyruğu arayüzü.
abstract interface class SoloMatchQueueRepository {
  Future<List<SoloMatchSubmission>> getPendingSubmissions();
  Future<void> enqueue(SoloMatchSubmission submission);
  Future<void> remove(String matchId);
  Future<void> clear();
}

/// SharedPreferences tabanlı somut [SoloMatchQueueRepository] uygulaması.
class LocalSoloMatchQueueRepository implements SoloMatchQueueRepository {
  static const String keyPendingSubmissions = 'pending_solo_match_submissions';
  static const int maxQueueSize = 20;
  static const int maxAgeMs = 24 * 60 * 60 * 1000; // 24 saat

  final SharedPreferences? prefs;
  final int Function()? clockNowMs;

  const LocalSoloMatchQueueRepository({
    this.prefs,
    this.clockNowMs,
  });

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  int _nowMs() =>
      clockNowMs != null ? clockNowMs!() : DateTime.now().millisecondsSinceEpoch;

  @override
  Future<List<SoloMatchSubmission>> getPendingSubmissions() async {
    try {
      final p = await _getPrefs();
      final raw = p.getString(keyPendingSubmissions);
      if (raw == null || raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final now = _nowMs();
      final valid = <SoloMatchSubmission>[];
      bool hadExpired = false;

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final sub = SoloMatchSubmission.fromJson(item);
          if (now - sub.submittedAtMs > maxAgeMs) {
            hadExpired = true;
          } else {
            valid.add(sub);
          }
        }
      }

      if (hadExpired) {
        await _saveList(p, valid);
      }

      return valid;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalSoloMatchQueueRepository] getPendingSubmissions error: $e');
      }
      return const [];
    }
  }

  @override
  Future<void> enqueue(SoloMatchSubmission submission) async {
    try {
      final p = await _getPrefs();
      final current = await getPendingSubmissions();

      // 1. Aynı matchId zaten kuyrukta varsa tekrar ekleme
      if (current.any((s) => s.matchId == submission.matchId)) {
        return;
      }

      final list = List<SoloMatchSubmission>.from(current);
      list.add(submission);

      // 2. Maksimum 20 kayıt kuralı: 20'yi aşarsa en eskileri çıkar
      while (list.length > maxQueueSize) {
        list.removeAt(0);
      }

      await _saveList(p, list);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalSoloMatchQueueRepository] enqueue error: $e');
      }
    }
  }

  @override
  Future<void> remove(String matchId) async {
    try {
      final p = await _getPrefs();
      final current = await getPendingSubmissions();
      final updated = current.where((s) => s.matchId != matchId).toList();
      await _saveList(p, updated);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalSoloMatchQueueRepository] remove error: $e');
      }
    }
  }

  @override
  Future<void> clear() async {
    try {
      final p = await _getPrefs();
      await p.remove(keyPendingSubmissions);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalSoloMatchQueueRepository] clear error: $e');
      }
    }
  }

  Future<void> _saveList(SharedPreferences p, List<SoloMatchSubmission> list) async {
    final mapped = list.map((e) => e.toJson()).toList();
    await p.setString(keyPendingSubmissions, jsonEncode(mapped));
  }
}
