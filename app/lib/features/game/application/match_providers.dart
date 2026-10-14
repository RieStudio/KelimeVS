import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../online/application/match_reconciler.dart';
import '../../online/application/online_match_session.dart';
import '../../online/data/matchmaking_client.dart';
import '../../online/data/online_match_client.dart';
import '../data/local_question_repository.dart';
import '../data/question_repository.dart';
import '../domain/bot/bot_config.dart';
import '../domain/match/match_config.dart';
import '../domain/text_filter.dart';
import 'match_controller.dart';
import 'match_history_provider.dart';
import 'match_session.dart';
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

final textFilterProvider = Provider<TextFilter>((ref) {
  return const PassthroughTextFilter();
});

final onlineMatchmakingEnabledProvider = Provider<bool>((ref) {
  return AppConfig.onlineMatchmakingEnabled;
});

final matchmakingClientFactoryProvider =
    Provider<MatchmakingClient Function()>((ref) {
  return () => MatchmakingClient();
});

final onlineMatchClientFactoryProvider =
    Provider<OnlineMatchClient Function()>((ref) {
  return () => OnlineMatchClient();
});

final matchControllerProvider =
    NotifierProvider<MatchController, MatchUiState>(() {
  return MatchController();
});

final onlineMatchSessionProvider =
    NotifierProvider<OnlineMatchSession, MatchUiState>(() {
  return OnlineMatchSession();
});

class ActiveMatchSessionModeNotifier extends Notifier<MatchSessionMode> {
  @override
  MatchSessionMode build() => MatchSessionMode.bot;

  void setMode(MatchSessionMode mode) {
    state = mode;
  }
}

final activeMatchSessionModeProvider =
    NotifierProvider<ActiveMatchSessionModeNotifier, MatchSessionMode>(() {
  return ActiveMatchSessionModeNotifier();
});

final activeMatchUiStateProvider = Provider<MatchUiState>((ref) {
  final mode = ref.watch(activeMatchSessionModeProvider);
  if (mode == MatchSessionMode.online) {
    return ref.watch(onlineMatchSessionProvider);
  }
  return ref.watch(matchControllerProvider);
});

final activeMatchSessionProvider = Provider<MatchSession>((ref) {
  final mode = ref.watch(activeMatchSessionModeProvider);
  if (mode == MatchSessionMode.online) {
    return ref.watch(onlineMatchSessionProvider.notifier);
  }
  return ref.watch(matchControllerProvider.notifier);
});

final matchReconcilerProvider = Provider<MatchReconciler>((ref) {
  final repo = ref.watch(matchHistoryRepositoryProvider);
  final clientFactory = ref.watch(onlineMatchClientFactoryProvider);
  return MatchReconciler(
    repo: repo,
    clientFactory: clientFactory,
    onUpdated: () => ref.invalidate(matchHistoryProvider),
  );
});


