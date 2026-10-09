// Saf Dart - Flutter, Riverpod veya SharedPreferences bağımlılığı yoktur.

import 'objection.dart';

abstract interface class ObjectionRepository {
  Future<Set<ObjectionKey>> loadForMatch(String matchId);
  Future<void> add(Objection objection);
  Future<void> cleanupOrphaned(Set<String> validMatchIds);
}

