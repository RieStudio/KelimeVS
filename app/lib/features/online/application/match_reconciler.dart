import 'dart:async';

import '../../../core/strings/app_strings.dart';
import '../../game/domain/history/match_history_entry.dart';
import '../../game/domain/history/match_history_repository.dart';
import '../../game/domain/match/match_state.dart';
import '../data/online_match_client.dart';
import '../domain/models/online_messages.dart';
import 'online_match_session.dart';

/// Geçici (`isFinal = false`) maç kayıtlarını sunucudan kesin sonuç alarak güncelleyen servis.
class MatchReconciler {
  final MatchHistoryRepository repo;
  final OnlineMatchClient Function() clientFactory;
  final void Function()? onUpdated;
  final void Function(int coins)? onCoinsUpdated;
  final Duration reconcileTimeout;

  bool _isReconciling = false;

  MatchReconciler({
    required this.repo,
    required this.clientFactory,
    this.onUpdated,
    this.onCoinsUpdated,
    this.reconcileTimeout = const Duration(seconds: 5),
  });

  /// Eşzamanlı devam eden bir kesinleştirme olup olmadığını bildirir.
  bool get isReconciling => _isReconciling;

  /// Depodaki tüm `isFinal == false` kayıtları kesinleştirmeyi dener.
  Future<void> reconcile() async {
    if (_isReconciling) return;
    _isReconciling = true;

    try {
      final entries = await repo.loadRecent();
      final pendingEntries = entries
          .where(
            (e) => !e.isFinal && e.matchId != null && e.matchId!.isNotEmpty,
          )
          .toList();

      if (pendingEntries.isEmpty) return;

      for (final entry in pendingEntries) {
        await _reconcileEntry(entry);
      }
    } catch (_) {
      // Başarısızlıkta sessiz kal
    } finally {
      _isReconciling = false;
    }
  }

  Future<void> _reconcileEntry(MatchHistoryEntry entry) async {
    final client = clientFactory();
    final completer = Completer<FinalServerMessage?>();

    StreamSubscription<OnlineMatchEvent>? sub;
    try {
      sub = client.events.listen(
        (event) {
          if (event is OnlineMatchFinal) {
            if (!completer.isCompleted) {
              completer.complete(event.result);
            }
          } else if (event is OnlineMatchVoided ||
              event is OnlineMatchError ||
              event is OnlineMatchDisconnected) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );

      try {
        await client.connect(entry.matchId!);
      } catch (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }

      final finalMsg = await completer.future.timeout(
        reconcileTimeout,
        onTimeout: () => null,
      );

      if (finalMsg != null) {
        final roundRecords = <RoundRecord>[];
        final roundQuestionTexts = <String>[];

        for (var i = 0; i < finalMsg.rounds.length; i++) {
          final onlineRound = finalMsg.rounds[i];
          roundRecords.add(
            OnlineMatchHistoryMapper.mapRoundRecord(onlineRound, i),
          );
          roundQuestionTexts.add(
            entry.questionTextForRound(
              i,
              fallback: AppStrings.defaultQuestionText,
            ),
          );
        }

        final isWinner = finalMsg.winnerIsMe;
        final isForfeit = finalMsg.endedBy == 'forfeit';
        final forfeitedPlayerId =
            isForfeit ? (isWinner ? 'bot' : 'me') : null;

        final MatchEndReason endReason;
        if (isForfeit) {
          endReason = isWinner
              ? MatchEndReason.rakipBaglantiKoptu
              : MatchEndReason.baglantiKoptu;
        } else {
          endReason = MatchEndReason.normal;
        }

        final updatedEntry = MatchHistoryEntry(
          id: entry.id,
          matchId: entry.matchId,
          opponentName: entry.opponentName,
          finishedAtMs: entry.finishedAtMs,
          myScore: finalMsg.myScore,
          opponentScore: finalMsg.opponentScore,
          result: isWinner ? MatchResult.win : MatchResult.lose,
          endType: isForfeit ? MatchEndType.forfeit : MatchEndType.normal,
          endReason: endReason,
          forfeitedPlayerId: forfeitedPlayerId,
          roundRecords: roundRecords,
          roundQuestionTexts: roundQuestionTexts,
          botlaOynandi: entry.botlaOynandi,
          isFinal: true,
        );

        await repo.add(updatedEntry);
        if (finalMsg.coins != null) {
          onCoinsUpdated?.call(finalMsg.coins!);
        }
        onUpdated?.call();
      }
    } catch (_) {
      // Hata durumunda sessiz kal, kayıt geçici olarak kalır
    } finally {
      await sub?.cancel();
      await client.close();
    }
  }
}
