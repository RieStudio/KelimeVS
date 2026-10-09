// Faz 4'te Firestore (users/{uid}/matches) ile değiştirilecek

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/history/match_history_entry.dart';
import '../domain/history/match_history_repository.dart';
import '../domain/match/match_events.dart';
import '../domain/match/match_state.dart';
import '../domain/objection/objection_repository.dart';

class LocalMatchHistoryRepository implements MatchHistoryRepository {
  static const String _storageKey = 'kelimego_match_history';
  static const int maxEntries = 10;

  final SharedPreferences? prefs;
  final ObjectionRepository? objectionRepository;

  const LocalMatchHistoryRepository({
    this.prefs,
    this.objectionRepository,
  });

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    final prefs = await _getPrefs();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decodedList = jsonDecode(jsonString);
      final entries = decodedList
          .map((item) => _MatchHistoryMapper.fromJson(item as Map<String, dynamic>))
          .toList();

      // En yeni başta sırala ve en fazla 10 kayıt döndür
      entries.sort((a, b) => b.finishedAtMs.compareTo(a.finishedAtMs));
      if (entries.length > maxEntries) {
        return entries.sublist(0, maxEntries);
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    final prefs = await _getPrefs();
    final currentEntries = await loadRecent();

    // Aynı id varsa önce çıkar, başa ekle
    final updatedList = [
      entry,
      ...currentEntries.where((e) => e.id != entry.id),
    ];

    // En yeni başta sırala ve en fazla 10 kayıt tut
    updatedList.sort((a, b) => b.finishedAtMs.compareTo(a.finishedAtMs));
    final trimmedList = updatedList.length > maxEntries
        ? updatedList.sublist(0, maxEntries)
        : updatedList;

    final encodedString = jsonEncode(
      trimmedList.map((e) => _MatchHistoryMapper.toJson(e)).toList(),
    );
    await prefs.setString(_storageKey, encodedString);

    // 10 maç sınırından düşen maçların itirazlarını temizle
    if (objectionRepository != null) {
      final validIds = trimmedList.map((e) => e.id).toSet();
      await objectionRepository!.cleanupOrphaned(validIds);
    }
  }
}

/// Domain sınıflarına dokunmadan data katmanında JSON serileştirme/haritalama
abstract final class _MatchHistoryMapper {
  static Map<String, dynamic> toJson(MatchHistoryEntry entry) {
    return {
      'id': entry.id,
      'opponentName': entry.opponentName,
      'finishedAtMs': entry.finishedAtMs,
      'myScore': entry.myScore,
      'opponentScore': entry.opponentScore,
      'result': entry.result.name,
      'endType': entry.endType.name,
      'forfeitedPlayerId': entry.forfeitedPlayerId,
      'roundRecords': entry.roundRecords.map(_roundRecordToJson).toList(),
      'roundQuestionTexts': entry.roundQuestionTexts,
    };
  }

  static MatchHistoryEntry fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      id: json['id'] as String,
      opponentName: json['opponentName'] as String,
      finishedAtMs: json['finishedAtMs'] as int,
      myScore: json['myScore'] as int,
      opponentScore: json['opponentScore'] as int,
      result: MatchResult.values.byName(json['result'] as String),
      endType: MatchEndType.values.byName(json['endType'] as String),
      forfeitedPlayerId: json['forfeitedPlayerId'] as String?,
      roundRecords: (json['roundRecords'] as List<dynamic>)
          .map((r) => _roundRecordFromJson(r as Map<String, dynamic>))
          .toList(),
      roundQuestionTexts: (json['roundQuestionTexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  static Map<String, dynamic> _roundRecordToJson(RoundRecord record) {
    return {
      'questionId': record.questionId,
      'starterPlayerId': record.starterPlayerId,
      'winnerId': record.winnerId,
      'reason': record.reason.name,
      'attempts': record.attempts.map(_turnAttemptToJson).toList(),
    };
  }

  static RoundRecord _roundRecordFromJson(Map<String, dynamic> json) {
    return RoundRecord(
      questionId: json['questionId'] as String,
      starterPlayerId: json['starterPlayerId'] as String,
      winnerId: json['winnerId'] as String?,
      reason: RoundEndReason.values.byName(json['reason'] as String),
      attempts: (json['attempts'] as List<dynamic>)
          .map((a) => _turnAttemptFromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  static Map<String, dynamic> _turnAttemptToJson(TurnAttempt attempt) {
    return {
      'playerId': attempt.playerId,
      'rawInput': attempt.rawInput,
      'resultType': attempt.resultType.name,
      'answerId': attempt.answerId,
      'nowMs': attempt.nowMs,
    };
  }

  static TurnAttempt _turnAttemptFromJson(Map<String, dynamic> json) {
    return TurnAttempt(
      playerId: json['playerId'] as String,
      rawInput: json['rawInput'] as String,
      resultType: AttemptResultType.values.byName(json['resultType'] as String),
      answerId: json['answerId'] as String?,
      nowMs: json['nowMs'] as int,
    );
  }
}
