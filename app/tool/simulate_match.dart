// Saf Dart betiği - Flutter ve Firebase bağımlılığı yoktur.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';

String _formatTimeLeft(int deadlineMs, int nowMs) {
  final remainingMs = math.max(0, deadlineMs - nowMs);
  final sec = (remainingMs / 1000).round().clamp(0, 99);
  return '${sec.toString().padLeft(2, '0')}s kaldı';
}

String _playerName(String playerId) {
  return playerId == 'p1' ? 'Oyuncu 1' : 'Oyuncu 2';
}

String _reasonText(RoundEndReason reason) {
  return switch (reason) {
    RoundEndReason.timeout => 'süre aşımı',
    RoundEndReason.repeated => 'tekrar cevap',
    RoundEndReason.wrong => 'yanlış cevap',
    RoundEndReason.exhausted => 'cevaplar tükendi',
  };
}

/// Kelimeden OSA mesafesi 1 olan bir yazım hatası türetir (komşu harf takası veya son harf değişimi).
String _makeTypo(String word) {
  if (word.length >= 4) {
    final chars = word.split('');
    // 'paris' -> swap r and i -> 'parsi'
    if (chars.length >= 4 && chars[chars.length - 3] != chars[chars.length - 2]) {
      final idx = chars.length - 3;
      final tmp = chars[idx];
      chars[idx] = chars[idx + 1];
      chars[idx + 1] = tmp;
      return chars.join();
    } else if (chars[0] != chars[1]) {
      final tmp = chars[0];
      chars[0] = chars[1];
      chars[1] = tmp;
      return chars.join();
    } else {
      chars[chars.length - 1] = chars.last == 'e' ? 'a' : 'e';
      return chars.join();
    }
  }
  return '${word}x';
}

void main(List<String> args) {
  int? seed;
  if (args.isNotEmpty) {
    seed = int.tryParse(args[0]);
  }
  final random = seed != null ? math.Random(seed) : math.Random();

  // 1. Soruları questions.json dosyasından oku
  File? questionsFile;
  const candidates = [
    'assets/dev/questions.json',
    'app/assets/dev/questions.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      questionsFile = file;
      break;
    }
  }

  if (questionsFile == null) {
    stderr.writeln('Hata: assets/dev/questions.json dosyası bulunamadı!');
    exit(1);
  }

  final jsonString = questionsFile.readAsStringSync();
  final jsonData = json.decode(jsonString) as Map<String, dynamic>;
  final List<Question> questions = Question.parseQuestionsPool(jsonData);

  if (questions.isEmpty) {
    stderr.writeln('Hata: Soru havuzunda soru bulunamadı!');
    exit(1);
  }

  stdout.writeln('========================================');
  stdout.writeln('     KELİMEGO MAÇ SİMÜLASYONU           ');
  stdout.writeln('========================================');
  stdout.writeln('Yüklenen Soru Sayısı: ${questions.length}');
  stdout.writeln('Kurallar: 3 Karar Turu, 15s Süre, 1 Çok Yakın Hakkı');
  stdout.writeln('----------------------------------------\n');

  final config = const MatchConfig(
    totalDecisiveRounds: 3,
    answerSeconds: 15,
    graceMs: 0,
    nearMissPerRound: 1,
  );

  int nowMs = 1000;
  var engineResult = MatchEngine.start(
    config: config,
    playerIds: ['p1', 'p2'],
    questions: questions,
    random: random,
    nowMs: nowMs,
  );
  var state = engineResult.state;

  while (state.phase != MatchPhase.matchFinished) {
    if (state.phase == MatchPhase.roundEnded) {
      nowMs += 2500; // Turlar arası bekleme
      engineResult = MatchEngine.startNextRound(
        state: state,
        questions: questions,
        random: random,
        nowMs: nowMs,
      );
      state = engineResult.state;
    }

    final currentRoundNum = state.totalRoundsPlayed + 1;
    final currentQuestion = state.currentQuestion!;
    final starterName = _playerName(state.turnPlayerId!);

    stdout.writeln('--- Tur $currentRoundNum: ${currentQuestion.text} (Başlayan: $starterName) ---');

    // Tur içi döngü
    while (state.phase == MatchPhase.roundActive) {
      final activePlayerId = state.turnPlayerId!;
      final activePlayerName = _playerName(activePlayerId);

      // Henüz kullanılmamış cevaplar
      final unusedAnswers = currentQuestion.answers
          .where((a) => !state.usedAnswerIds.contains(a.id))
          .toList();

      if (unusedAnswers.isEmpty) {
        // Beklenmeyen durum koruması
        break;
      }

      // Oyuncuların karar dinamikleri:
      // Oyuncu 2 bazen süre aşsın (12% ihtimal), Oyuncu 1 daha nadir (4%)
      final willTimeout = ((activePlayerId == 'p2' && random.nextDouble() < 0.12) ||
              (activePlayerId == 'p1' && random.nextDouble() < 0.04)) &&
          state.currentRoundAttempts.length >= 3;

      if (willTimeout) {
        nowMs = state.deadlineMs + 500;
        stdout.writeln('[00s kaldı] $activePlayerName: (Süre doldu)');
        engineResult = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
        state = engineResult.state;
        break;
      }

      // Düşünme süresi (2 - 5 saniye)
      final thinkSeconds = 2 + random.nextInt(4);
      nowMs += thinkSeconds * 1000;

      // Oyuncu 2 bazen yazım hatası yapsın (20% ihtimal), Oyuncu 1 daha nadir (10%)
      final nearMissQuota = state.remainingNearMisses[activePlayerId] ?? 0;
      final willMakeTypo = nearMissQuota > 0 &&
          (activePlayerId == 'p2' ? random.nextDouble() < 0.20 : random.nextDouble() < 0.10);

      // Bazen yanlış kelime söylesinler (hakkı kalmadıktan sonra)
      final willFailWrong = !willMakeTypo &&
          nearMissQuota == 0 &&
          (activePlayerId == 'p2' ? random.nextDouble() < 0.08 : random.nextDouble() < 0.04) &&
          state.currentRoundAttempts.length >= 3;

      if (willMakeTypo) {
        // En az 4 harfli uygun bir kelime seçip yazım hatası yap
        final candidate = unusedAnswers.firstWhere(
          (a) => a.display.length >= 4,
          orElse: () => unusedAnswers.first,
        );
        final typo = _makeTypo(candidate.display.toLowerCase());
        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);

        engineResult = MatchEngine.submit(
          state: state,
          playerId: activePlayerId,
          rawInput: typo,
          nowMs: nowMs,
        );
        state = engineResult.state;

        final isNearMissEvent = engineResult.events.any((e) => e is NearMiss);
        if (isNearMissEvent) {
          final remaining = state.remainingNearMisses[activePlayerId] ?? 0;
          stdout.writeln('[$timeStr] $activePlayerName: "$typo" -> Çok yakın! (Kalan hak: $remaining)');

          // Hemen ardından doğru halini yazsın (3 saniye sonra)
          nowMs += 3000;
          final retryTimeStr = _formatTimeLeft(state.deadlineMs, nowMs);
          engineResult = MatchEngine.submit(
            state: state,
            playerId: activePlayerId,
            rawInput: candidate.display,
            nowMs: nowMs,
          );
          state = engineResult.state;
          stdout.writeln('[$retryTimeStr] $activePlayerName: "${candidate.display.toLowerCase()}" -> Doğru!');
        } else {
          // Çok yakın tetiklenmediyse (örn. 3 harf veya başka sebep)
          stdout.writeln('[$timeStr] $activePlayerName: "$typo" -> Yanlış cevap!');
        }
      } else if (willFailWrong) {
        const fakeWrongAnswers = ['atlantis', 'mars', 'samanyolu', 'ejderha', 'bilinmeyen'];
        final wrongWord = fakeWrongAnswers[random.nextInt(fakeWrongAnswers.length)];
        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);

        engineResult = MatchEngine.submit(
          state: state,
          playerId: activePlayerId,
          rawInput: wrongWord,
          nowMs: nowMs,
        );
        state = engineResult.state;
        stdout.writeln('[$timeStr] $activePlayerName: "$wrongWord" -> Yanlış cevap!');
      } else {
        // Normal doğru cevap
        final targetAnswer = unusedAnswers[random.nextInt(unusedAnswers.length)];
        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);

        engineResult = MatchEngine.submit(
          state: state,
          playerId: activePlayerId,
          rawInput: targetAnswer.display,
          nowMs: nowMs,
        );
        state = engineResult.state;

        stdout.writeln('[$timeStr] $activePlayerName: "${targetAnswer.display.toLowerCase()}" -> Doğru!');
      }
    }

    // Tur bitti bilgisi
    final lastRecord = state.roundHistory.last;
    final p1Score = state.scores['p1'] ?? 0;
    final p2Score = state.scores['p2'] ?? 0;

    if (lastRecord.winnerId != null) {
      final roundWinner = _playerName(lastRecord.winnerId!);
      final reason = _reasonText(lastRecord.reason);
      stdout.writeln('Tur $currentRoundNum Bitti: $roundWinner kazandı ($reason). Skor: $p1Score - $p2Score\n');
    } else {
      stdout.writeln('Tur $currentRoundNum Bitti: Berabere bitti (cevaplar tükendi). Skor: $p1Score - $p2Score\n');
    }
  }

  // Maç bitti
  final matchWinner = _playerName(state.winnerId!);
  final p1Final = state.scores['p1'] ?? 0;
  final p2Final = state.scores['p2'] ?? 0;
  stdout.writeln('=== MAÇ BİTTİ: $matchWinner KAZANDI ($p1Final - $p2Final) ===\n');
}
