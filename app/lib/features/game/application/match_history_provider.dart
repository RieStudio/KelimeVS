import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_match_history_repository.dart';
import '../domain/history/match_history_entry.dart';
import '../domain/history/match_history_repository.dart';

final matchHistoryRepositoryProvider = Provider<MatchHistoryRepository>((ref) {
  return const LocalMatchHistoryRepository();
});

final matchHistoryProvider =
    FutureProvider<List<MatchHistoryEntry>>((ref) async {
  final repo = ref.watch(matchHistoryRepositoryProvider);
  return repo.loadRecent();
});

