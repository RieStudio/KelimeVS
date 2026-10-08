// Saf Dart - Flutter, Riverpod veya SharedPreferences bağımlılığı yoktur.

import 'match_history_entry.dart';

abstract interface class MatchHistoryRepository {
  /// En fazla 10 maç kaydı tutar, en yeni kayıt başta döner.
  Future<List<MatchHistoryEntry>> loadRecent();

  /// Yeni maç kaydı ekler. En fazla 10 kayıt sınırını korur.
  Future<void> add(MatchHistoryEntry entry);
}

