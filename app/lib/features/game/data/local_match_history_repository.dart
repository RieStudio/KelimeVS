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
      final entriesWithIndex = decodedList
          .asMap()
          .entries
          .map((item) => (
                index: item.key,
                entry: _MatchHistoryMapper.fromJson(item.value as Map<String, dynamic>),
              ))
          .toList();

      // En yeni başta sırala: finishedAtMs azalan; eşitlikte sonradan eklenen üstte (depodaki index'i küçük olan)
      entriesWithIndex.sort((a, b) {
        final cmp = b.entry.finishedAtMs.compareTo(a.entry.finishedAtMs);
        if (cmp != 0) return cmp;
        return a.index.compareTo(b.index);
      });

      final entries = entriesWithIndex.map((e) => e.entry).toList();
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

    // Aynı id varsa önce çıkar; yeni eklenen başa (index 0) gelir (en son eklenen)
    final rawList = [
      entry,
      ...currentEntries.where((e) => e.id != entry.id),
    ];

    // finishedAtMs azalan; eşitlikte sonradan eklenen üstte (rawList'te index'i küçük olan)
    final rawWithIndex = rawList.asMap().entries.toList();
    rawWithIndex.sort((a, b) {
      final cmp = b.value.finishedAtMs.compareTo(a.value.finishedAtMs);
      if (cmp != 0) return cmp;
      return a.key.compareTo(b.key);
    });

    final sortedList = rawWithIndex.map((e) => e.value).toList();

    // En fazla 10 kayıt tut: 11. maçta listenin sonundaki EN ESKİ kayıt silinir
    final trimmedList = sortedList.length > maxEntries
        ? sortedList.sublist(0, maxEntries)
        : sortedList;

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
      'isClose': attempt.isClose,
      'hintShown': attempt.hintShown,
    };
  }

  static TurnAttempt _turnAttemptFromJson(Map<String, dynamic> json) {
    return TurnAttempt(
      playerId: json['playerId'] as String,
      rawInput: json['rawInput'] as String,
      resultType: AttemptResultType.values.byName(json['resultType'] as String),
      answerId: json['answerId'] as String?,
      nowMs: json['nowMs'] as int,
      isClose: json['isClose'] as bool? ?? false,
      hintShown: json['hintShown'] as bool? ?? false,
    );
  }
}
