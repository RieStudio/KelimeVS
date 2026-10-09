import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_objection_repository.dart';
import '../domain/objection/objection.dart';
import '../domain/objection/objection_repository.dart';

final objectionRepositoryProvider = Provider<ObjectionRepository>((ref) {
  return const LocalObjectionRepository();
});

final matchObjectionsProvider =
    FutureProvider.family<Set<ObjectionKey>, String>((ref, matchId) async {
  final repo = ref.watch(objectionRepositoryProvider);
  return repo.loadForMatch(matchId);
});

