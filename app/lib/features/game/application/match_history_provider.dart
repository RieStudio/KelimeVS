import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_match_history_repository.dart';
import '../domain/history/match_history_entry.dart';
import '../domain/history/match_history_repository.dart';
import 'objection_provider.dart';

final matchHistoryRepositoryProvider = Provider<MatchHistoryRepository>((ref) {
  final objectionRepo = ref.watch(objectionRepositoryProvider);
  return LocalMatchHistoryRepository(objectionRepository: objectionRepo);
});

final matchHistoryProvider =
    FutureProvider<List<MatchHistoryEntry>>((ref) async {
  final repo = ref.watch(matchHistoryRepositoryProvider);
  return repo.loadRecent();
});

