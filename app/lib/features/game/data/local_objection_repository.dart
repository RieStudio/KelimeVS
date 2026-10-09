// Faz 4'te sunucuya gönderilecek, GDD 4.4

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/objection/objection.dart';
import '../domain/objection/objection_repository.dart';

class LocalObjectionRepository implements ObjectionRepository {
  static const String _storageKey = 'kelimego_objections';

  final SharedPreferences? prefs;

  const LocalObjectionRepository({this.prefs});

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<Set<ObjectionKey>> loadForMatch(String matchId) async {
    final all = await _loadAll();
    return all
        .where((o) => o.matchId == matchId)
        .map((o) => o.key)
        .toSet();
  }

  @override
  Future<void> add(Objection objection) async {
    final all = await _loadAll();

    // Aynı (tur, deneme)'ye ikinci kez itiraz eklenmesini önle
    final exists = all.any((o) =>
        o.matchId == objection.matchId &&
        o.roundIndex == objection.roundIndex &&
        o.attemptIndex == objection.attemptIndex);
    if (exists) return;

    all.add(objection);
    await _saveAll(all);
  }

  @override
  Future<void> cleanupOrphaned(Set<String> validMatchIds) async {
    final all = await _loadAll();
    final filtered = all.where((o) => validMatchIds.contains(o.matchId)).toList();
    if (filtered.length != all.length) {
      await _saveAll(filtered);
    }
  }

  Future<List<Objection>> _loadAll() async {
    final p = await _getPrefs();
    final jsonStr = p.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> decodedList = jsonDecode(jsonStr);
      return decodedList
          .map((item) => _objectionFromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<Objection> objections) async {
    final p = await _getPrefs();
    final encoded = jsonEncode(
      objections.map(_objectionToJson).toList(),
    );
    await p.setString(_storageKey, encoded);
  }

  static Map<String, dynamic> _objectionToJson(Objection o) {
    return {
      'matchId': o.matchId,
      'roundIndex': o.roundIndex,
      'attemptIndex': o.attemptIndex,
      'rawInput': o.rawInput,
      'createdAtMs': o.createdAtMs,
    };
  }

  static Objection _objectionFromJson(Map<String, dynamic> json) {
    return Objection(
      matchId: json['matchId'] as String,
      roundIndex: json['roundIndex'] as int,
      attemptIndex: json['attemptIndex'] as int,
      rawInput: json['rawInput'] as String,
      createdAtMs: json['createdAtMs'] as int,
    );
  }
}

