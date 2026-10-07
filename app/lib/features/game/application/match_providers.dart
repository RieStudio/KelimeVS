import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_question_repository.dart';
import '../data/question_repository.dart';
import '../domain/bot/bot_config.dart';
import '../domain/match/match_config.dart';
import 'match_controller.dart';
import 'match_ui_state.dart';

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return const LocalQuestionRepository();
});

final gameClockProvider = Provider<GameClock>((ref) {
  return StopwatchClock();
});

final randomProvider = Provider<math.Random>((ref) {
  return math.Random();
});

final botConfigProvider = Provider<BotConfig>((ref) {
  return const BotConfig();
});

final matchConfigProvider = Provider<MatchConfig>((ref) {
  return const MatchConfig();
});

final matchControllerProvider =
    NotifierProvider<MatchController, MatchUiState>(() {
  return MatchController();
});

