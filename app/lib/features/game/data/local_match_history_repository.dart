// Faz 4'te Firestore (users/{uid}/matches) ile değiştirilecek

import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  static String _shortErrorMessage(Object error) {
    final sanitized = error
        .toString()
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'[A-Za-z0-9_-]{32,}'), '[redacted]')
        .trim();
    if (sanitized.length <= 80) return sanitized;
    return '${sanitized.substring(0, 80)}...';
  }

  static MatchHistoryEntry entryFromJson(Map<String, dynamic> json) =>
      _MatchHistoryMapper.fromJson(json);

  @override
  Future<List<MatchHistoryEntry>> loadRecent() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        if (kDebugMode) {
          debugPrint('[history] okundu: 0 kayıt');
        }
        return [];
      }

      final List<dynamic> decodedList = jsonDecode(jsonString) as List<dynamic>;
      final entriesWithIndex = <({int index, MatchHistoryEntry entry})>[];

      for (var i = 0; i < decodedList.length; i++) {
        try {
          final rawItem = decodedList[i];
          if (rawItem is! Map<String, dynamic>) {
            throw const FormatException('Kayıt nesnesi Map değil');
          }
          final parsed = _MatchHistoryMapper.fromJson(rawItem);
          entriesWithIndex.add((index: i, entry: parsed));
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[history] ayrıştırılamayan kayıt atlandı: ${e.runtimeType}',
            );
          }
        }
      }

      // En yeni başta sırala: finishedAtMs azalan; eşitlikte sonradan eklenen üstte (depodaki index'i küçük olan)
      entriesWithIndex.sort((a, b) {
        final cmp = b.entry.finishedAtMs.compareTo(a.entry.finishedAtMs);
        if (cmp != 0) return cmp;
        return a.index.compareTo(b.index);
      });

      final entries = entriesWithIndex.map((e) => e.entry).toList();
      final result = entries.length > maxEntries
          ? entries.sublist(0, maxEntries)
          : entries;

      if (kDebugMode) {
        debugPrint('[history] okundu: ${result.length} kayıt');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[history] okuma HATASI: ${e.runtimeType}: ${_shortErrorMessage(e)}',
        );
      }
      return [];
    }
  }

  @override
  Future<void> add(MatchHistoryEntry entry) async {
    try {
      final prefs = await _getPrefs();
      final currentEntries = await loadRecent();

      // Aynı id veya matchId varsa önce çıkar; yeni/güncellenen kayıt başa (index 0) gelir
      final rawList = [
        entry,
        ...currentEntries.where((e) {
          if (e.id == entry.id) return false;
          if (entry.matchId != null &&
              e.matchId != null &&
              e.matchId == entry.matchId) {
            return false;
          }
          return true;
        }),
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

      if (kDebugMode) {
        final byteCount = utf8.encode(encodedString).length;
        debugPrint(
          '[history] yazıldı: toplam ${trimmedList.length} kayıt, $byteCount bayt',
        );
      }

      // 10 maç sınırından düşen maçların itirazlarını temizle
      if (objectionRepository != null) {
        try {
          final validIds = trimmedList.map((e) => e.id).toSet();
          await objectionRepository!.cleanupOrphaned(validIds);
        } catch (_) {
          // İtiraz temizleme hatası maç kaydını bozmamalı
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[history] yazma HATASI: ${e.runtimeType}: ${_shortErrorMessage(e)}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_storageKey);
      if (kDebugMode) {
        debugPrint('[history] temizlendi');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[history] temizleme HATASI: ${e.runtimeType}: ${_shortErrorMessage(e)}',
        );
      }
    }
  }
}

/// Domain sınıflarına dokunmadan data katmanında JSON serileştirme/haritalama
abstract final class _MatchHistoryMapper {
  static Map<String, dynamic> toJson(MatchHistoryEntry entry) {
    return {
      'id': entry.id,
      'matchId': entry.matchId,
      'opponentName': entry.opponentName,
      'finishedAtMs': entry.finishedAtMs,
      'myScore': entry.myScore,
      'opponentScore': entry.opponentScore,
      'result': entry.result.name,
      'endType': entry.endType.name,
      'endReason': entry.endReason.name,
      'forfeitedPlayerId': entry.forfeitedPlayerId,
      'roundRecords': entry.roundRecords.map(_roundRecordToJson).toList(),
      'roundQuestionTexts': entry.roundQuestionTexts,
      'botlaOynandi': entry.botlaOynandi,
      'isFinal': entry.isFinal,
      'isFriendly': entry.isFriendly,
      'opponentFrame': entry.opponentFrame,
    };
  }

  static MatchHistoryEntry fromJson(Map<String, dynamic> json) {
    final result = MatchResult.values.byName(json['result'] as String);
    final endType = MatchEndType.values.byName(json['endType'] as String);
    final MatchEndReason endReason;
    if (json['endReason'] != null) {
      endReason = MatchEndReason.values.byName(json['endReason'] as String);
    } else {
      endReason = endType == MatchEndType.forfeit
          ? (result == MatchResult.win
              ? MatchEndReason.rakipTerk
              : MatchEndReason.terk)
          : MatchEndReason.normal;
    }

    return MatchHistoryEntry(
      id: json['id'] as String,
      matchId: json['matchId'] as String?,
      opponentName: json['opponentName'] as String,
      finishedAtMs: json['finishedAtMs'] as int,
      myScore: json['myScore'] as int,
      opponentScore: json['opponentScore'] as int,
      result: result,
      endType: endType,
      endReason: endReason,
      forfeitedPlayerId: json['forfeitedPlayerId'] as String?,
      roundRecords: (json['roundRecords'] as List<dynamic>)
          .map((r) => _roundRecordFromJson(r as Map<String, dynamic>))
          .toList(),
      roundQuestionTexts: (json['roundQuestionTexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      botlaOynandi: json['botlaOynandi'] as bool? ?? false,
      isFinal: json['isFinal'] as bool? ?? true,
      isFriendly: json['isFriendly'] as bool? ?? false,
      opponentFrame: json['opponentFrame'] as String? ?? 'classic',
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
      if (attempt.displayText != null) 'displayText': attempt.displayText,
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
      displayText: json['displayText'] as String?,
      nowMs: json['nowMs'] as int,
      isClose: json['isClose'] as bool? ?? false,
      hintShown: json['hintShown'] as bool? ?? false,
    );
  }
}
