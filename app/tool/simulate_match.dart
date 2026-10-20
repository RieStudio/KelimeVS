// Saf Dart betiği - Flutter ve Firebase bağımlılığı yoktur.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

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
    RoundEndReason.exhausted => 'cevaplar tükendi',
    RoundEndReason.forfeit => 'maçı terk etme',
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

/// 4-5 cevaplı yapay sorular (Tükenmeyi ve beraberliği sınamak için)
List<Question> _createSmallPool() {
  const rawData = [
    ('sp_1', 'Mevsimler', ['İlkbahar', 'Yaz mevsimi', 'Sonbahar', 'Kış mevsimi']),
    ('sp_2', 'Dört element', ['Ateş', 'Toprak', 'Hava', 'Su elementi']),
    ('sp_3', 'Ana yönler', ['Kuzey', 'Güney', 'Doğu', 'Batı']),
    ('sp_4', 'Dört büyük halife', ['Ebubekir', 'Ömer', 'Osman', 'Ali']),
    ('sp_5', 'Dört işlem', ['Toplama', 'Çıkarma', 'Çarpma', 'Bölme']),
    ('sp_6', 'İskambil sembolleri', ['Kupa', 'Karo', 'Maça', 'Sinek']),
    ('sp_7', 'Duyu organları', ['Göz', 'Kulak', 'Burun', 'Dil', 'Deri']),
    ('sp_8', 'Okyanuslar', ['Büyük Okyanus', 'Atlas Okyanusu', 'Hint Okyanusu', 'Arktik Okyanusu']),
    ('sp_9', 'Temel tatlar', ['Tatlı', 'Tuzlu', 'Ekşi', 'Acı', 'Umami']),
    ('sp_10', 'Güneşe en yakın gezegenler', ['Merkür', 'Venüs', 'Dünya', 'Mars', 'Jüpiter']),
    ('sp_11', 'Marmara bölgesi illeri', ['İstanbul', 'Bursa', 'Kocaeli', 'Balıkesir', 'Tekirdağ']),
    ('sp_12', 'Ege bölgesi illeri', ['İzmir', 'Aydın', 'Muğla', 'Manisa', 'Denizli']),
    ('sp_13', 'Akdeniz bölgesi illeri', ['Antalya', 'Adana', 'Mersin', 'Hatay', 'Isparta']),
    ('sp_14', 'İç Anadolu illeri', ['Ankara', 'Konya', 'Kayseri', 'Eskişehir', 'Sivas']),
    ('sp_15', 'Karadeniz illeri', ['Trabzon', 'Samsun', 'Ordu', 'Giresun', 'Rize']),
    ('sp_16', 'Güneydoğu Anadolu illeri', ['Gaziantep', 'Diyarbakır', 'Şanlıurfa', 'Mardin', 'Batman']),
    ('sp_17', 'Doğu Anadolu illeri', ['Erzurum', 'Van', 'Malatya', 'Elazığ', 'Ağrı']),
    ('sp_18', 'Müzik notaları', ['Do notası', 'Re notası', 'Mi notası', 'Fa notası', 'Sol notası']),
    ('sp_19', 'Temel renkler', ['Kırmızı', 'Mavi', 'Sarı', 'Yeşil', 'Beyaz']),
    ('sp_20', 'İlk 5 asal sayı', ['İki sayısı', 'Üç sayısı', 'Beş sayısı', 'Yedi sayısı', 'On bir sayısı']),
    ('sp_21', 'El parmakları', ['Başparmak', 'İşaret parmağı', 'Orta parmak', 'Yüzük parmağı', 'Serçe parmak']),
    ('sp_22', 'Evcil hayvanlar', ['Kedi', 'Köpek', 'Kuş', 'Balık', 'Hamster']),
    ('sp_23', 'Çiftlik hayvanları', ['İnek', 'Koyun', 'Keçi', 'At', 'Tavuk']),
    ('sp_24', 'Vahşi hayvanlar', ['Aslan', 'Kaplan', 'Ayı', 'Kurt', 'Fil']),
    ('sp_25', 'Sürüngenler', ['Yılan', 'Kertenkele', 'Timsah', 'Kaplumbağa', 'Bukalemun']),
    ('sp_26', 'Yırtıcı ve uçucu kuşlar', ['Kartal', 'Şahin', 'Güvercin', 'Martı', 'Karga']),
    ('sp_27', 'Orman ağaçları', ['Çam ağacı', 'Meşe ağacı', 'Gürgen ağacı', 'Kavak ağacı', 'Çınar ağacı']),
    ('sp_28', 'Popüler çiçekler', ['Gül çiçeği', 'Papatya', 'Lale çiçeği', 'Karanfil', 'Menekşe']),
    ('sp_29', 'Narenciye meyveleri', ['Portakal', 'Mandalina', 'Limon', 'Greyfurt', 'Turunç']),
    ('sp_30', 'Kış mevsimi meyveleri', ['Elma', 'Armut', 'Ayva', 'Nar', 'Portakal']),
    ('sp_31', 'Yaz mevsimi meyveleri', ['Karpuz', 'Kavun', 'Şeftali', 'Kiraz', 'Çilek']),
    ('sp_32', 'Kuru yemişler', ['Fındık', 'Fıstık', 'Ceviz', 'Badem', 'Kaju']),
    ('sp_33', 'Kuru bakliyatlar', ['Mercimek', 'Nohut', 'Fasulye', 'Bezelye', 'Barbunya']),
    ('sp_34', 'Tahıl ürünleri', ['Buğday', 'Arpa', 'Yulaf', 'Çavdar', 'Mısır']),
    ('sp_35', 'Temel içecekler', ['Su', 'Çay', 'Kahve', 'Ayran', 'Limonata']),
    ('sp_36', 'Sıcak kış içecekleri', ['Çay', 'Kahve', 'Sıcak çikolata', 'Salep', 'Ihlamur']),
    ('sp_37', 'Soğuk meşrubatlar', ['Su', 'Ayran', 'Limonata', 'Meyve suyu', 'Gazoz']),
    ('sp_38', 'Geleneksel çorbalar', ['Mercimek çorbası', 'Tarhana çorbası', 'Yayla çorbası', 'Domates çorbası', 'Ezogelin çorbası']),
    ('sp_39', 'Temel kahvaltılıklar', ['Peynir', 'Zeytin', 'Yumurta', 'Bal', 'Reçel']),
    ('sp_40', 'Şerbetli ve sütlü tatlılar', ['Baklava', 'Sütlaç', 'Kazandibi', 'Künefe', 'Revani']),
    ('sp_41', 'Popüler takım sporları', ['Futbol', 'Basketbol', 'Voleybol', 'Hentbol', 'Ragbi']),
    ('sp_42', 'Su sporları', ['Yüzme', 'Kürek sporu', 'Su topu', 'Yelken sporu', 'Sörf']),
    ('sp_43', 'Kış sporları', ['Kayak', 'Kızak sporu', 'Buz pateni', 'Snowboard', 'Körling']),
    ('sp_44', 'Dövüş sporları', ['Boks sporu', 'Güreş sporu', 'Karate', 'Judo', 'Taekwondo']),
    ('sp_45', 'Temel müzik aletleri', ['Gitar', 'Piyano', 'Keman', 'Bateri', 'Flüt']),
    ('sp_46', 'Telli enstrümanlar', ['Gitar', 'Keman', 'Bağlama', 'Ud enstrümanı', 'Kanun']),
    ('sp_47', 'Üflemeli çalgılar', ['Flüt', 'Klarnet', 'Trompet', 'Saksafon', 'Ney çalgısı']),
    ('sp_48', 'Vurmalı ritim çalgıları', ['Bateri', 'Darbuka', 'Davul', 'Tef çalgısı', 'Bendir']),
    ('sp_49', 'Temel okul dersleri', ['Türkçe dersi', 'Matematik', 'Fen bilimleri', 'Tarih dersi', 'Coğrafya']),
    ('sp_50', 'Yazı ve çizim gereçleri', ['Kurşun kalem', 'Tükenmez kalem', 'Silgi', 'Kalemtıraş', 'Cetvel']),
    ('sp_51', 'Masaüstü kırtasiye ürünleri', ['Defter', 'Kitap', 'Dosya', 'Zımba', 'Makas']),
    ('sp_52', 'Temel bilgisayar bileşenleri', ['İşlemci', 'Ekran kartı', 'Anakart', 'Bellek ram', 'Sabit disk']),
    ('sp_53', 'Bilgisayar çevre birimleri', ['Klavye', 'Fare mouse', 'Monitör', 'Yazıcı', 'Kulaklık']),
    ('sp_54', 'Kara taşıtları', ['Otomobil', 'Otobüs', 'Kamyon', 'Motosiklet', 'Bisiklet']),
    ('sp_55', 'Deniz taşıtları', ['Gemi', 'Vapur', 'Tekne', 'Feribot', 'Sandal']),
    ('sp_56', 'Hava araçları', ['Uçak', 'Helikopter', 'Sıcak hava balonu', 'Zeplin', 'Planör']),
    ('sp_57', 'Raylı toplu taşıma araçları', ['Tren', 'Metro', 'Tramvay', 'Teleferik', 'Füniküler']),
    ('sp_58', 'Günlük giyim ürünleri', ['Gömlek', 'Pantolon', 'Kazak', 'Ceket', 'Etek']),
    ('sp_59', 'Kışlık giysiler', ['Mont', 'Kaban', 'Atkı', 'Bere', 'Eldiven']),
    ('sp_60', 'Ayakkabı modelleri', ['Spor ayakkabı', 'Kışlık bot', 'Çizme', 'Sandalet', 'Terlik']),
  ];

  return rawData.map((item) {
    return Question(
      id: item.$1,
      categoryId: 'small_pool',
      text: item.$2,
      answers: item.$3.map((ans) {
        final norm = TextNormalizer.normalize(ans);
        return Answer(
          id: norm,
          display: ans,
          aliases: [norm],
        );
      }).toList(),
    );
  }).toList();
}

class SimulationStats {
  int timeoutCount = 0;
  int exhaustedCount = 0;
  int forfeitCount = 0;

  int wrongAttemptsCount = 0;
  int repeatedAttemptsCount = 0;
  int ignoredAttemptsCount = 0;
  int nearMissTriggeredCount = 0;

  int totalRoundsPlayed = 0;
  int maxRoundsPlayed = 0;
  int extendedMatchesCount = 0;

  int sweepMatchesCount = 0; // 2-0 biten maçlar
  int threeRoundMatchesCount = 0; // 2-1 biten maçlar

  int invariantViolations = 0;
}

List<String> _checkInvariants(MatchState state, int poolSize) {
  final errors = <String>[];

  // 1. Maç terk edildiyse terk eden kaybetmiş, terk etmeyen kazanmış olmalı
  if (state.endedBy == 'forfeit') {
    if (state.winnerId == null) {
      errors.add('Terk edilen maçta kazanan yok');
    }
    final lastRecord = state.roundHistory.isEmpty ? null : state.roundHistory.last;
    if (lastRecord == null || lastRecord.reason != RoundEndReason.forfeit) {
      errors.add('Terk edilen maçın son tur kaydı forfeit değil: ${lastRecord?.reason}');
    } else if (lastRecord.winnerId != state.winnerId) {
      errors.add('Terk edilen maçta son tur kazananı ile maç kazananı uyuşmuyor: ${lastRecord.winnerId} vs ${state.winnerId}');
    }
  } else {
    // Normal biten maç:
    // Sonuçlanan tur sayısı 2 ya da 3 olmalı
    if (state.decisiveRounds != 2 && state.decisiveRounds != 3) {
      errors.add('Sonuçlanan tur sayısı 2 ya da 3 değil: ${state.decisiveRounds}');
    }
    final wonRoundsCount = state.roundHistory.where((r) => r.winnerId != null).length;
    if (wonRoundsCount != state.decisiveRounds) {
      errors.add('Kazanılan tur kaydı ($wonRoundsCount) ile decisiveRounds (${state.decisiveRounds}) uyuşmuyor');
    }

    // Skorların toplamı sonuçlanan tur sayısına eşit olmalı, kazanan 2 tur kazanmış oyuncu olmalı
    final p1Score = state.scores['p1'] ?? 0;
    final p2Score = state.scores['p2'] ?? 0;
    if (p1Score + p2Score != state.decisiveRounds) {
      errors.add('Skorlar toplamı ($p1Score + $p2Score) sonuçlanan tur sayısına (${state.decisiveRounds}) eşit değil');
    }
    final expectedWinner = p1Score > p2Score ? 'p1' : 'p2';
    if (state.winnerId != expectedWinner) {
      errors.add('Kazanan hatalı: beklenen $expectedWinner, gerçek ${state.winnerId}');
    }
    final winnerScore = state.scores[state.winnerId] ?? 0;
    final loserScore = state.scores[state.opponentOf(state.winnerId!)] ?? 0;
    if (winnerScore != 2) {
      errors.add('Kazanan oyuncunun skoru 2 değil: $winnerScore');
    }
    if (state.decisiveRounds == 2 && loserScore != 0) {
      errors.add('2 sonuçlanan turlu maçta skor 2-0 değil: $winnerScore - $loserScore');
    }
    if (state.decisiveRounds == 3 && loserScore != 1) {
      errors.add('3 sonuçlanan turlu maçta skor 2-1 değil: $winnerScore - $loserScore');
    }
  }

  // Tüm maçlar için kontroller:
  // 2. Tur kaybetmenin TEK sebebi süre aşımı olmalı (veya maç terk edildiyse son tur için forfeit)
  for (int i = 0; i < state.roundHistory.length; i++) {
    final round = state.roundHistory[i];
    if (round.winnerId != null) {
      if (round.reason != RoundEndReason.timeout && round.reason != RoundEndReason.forfeit) {
        errors.add('Tur ${i + 1} kaybetme sebebi geçersiz: ${round.reason}');
      }
    } else {
      if (round.reason != RoundEndReason.exhausted) {
        errors.add('Berabere biten tur ${i + 1} sebebi exhausted değil: ${round.reason}');
      }
    }
  }

  // 3. Bir maçta aynı soru iki kez gelmedi (havuz boyutu tur sayısına yetiyorsa)
  if (poolSize >= state.roundHistory.length) {
    final questionIds = state.roundHistory.map((r) => r.questionId).toList();
    if (questionIds.toSet().length != questionIds.length) {
      errors.add('Aynı maçta soru tekrar etti: $questionIds');
    }
  }

  // 4. Bir turda aynı answerId iki kez kabul edilmedi
  for (int i = 0; i < state.roundHistory.length; i++) {
    final round = state.roundHistory[i];
    final acceptedAnswerIds = round.attempts
        .where((a) => a.resultType == AttemptResultType.correct && a.answerId != null)
        .map((a) => a.answerId!)
        .toList();
    if (acceptedAnswerIds.toSet().length != acceptedAnswerIds.length) {
      errors.add('Tur ${i + 1} içinde aynı answerId iki kez kabul edildi: $acceptedAnswerIds');
    }
  }

  // 5. Aktif turda hiçbir oyuncuya hintShown denemesi ve rakibin isClose denemesi gösterilemez
  for (int i = 0; i < state.roundHistory.length; i++) {
    final round = state.roundHistory[i];
    for (final p in state.playerIds) {
      final opp = state.opponentOf(p);
      final activeVisible = visibleAttempts(round, p, true);
      final hintShownLeaked =
          activeVisible.where((a) => a.hintShown).toList();
      if (hintShownLeaked.isNotEmpty) {
        errors.add(
            'Tur ${i + 1} aktifken $p oyuncusuna hintShown denemesi (${hintShownLeaked.length} adet) gösterildi!');
      }
      final opponentCloseLeaked =
          activeVisible.where((a) => a.playerId == opp && a.isClose).toList();
      if (opponentCloseLeaked.isNotEmpty) {
        errors.add(
            'Tur ${i + 1} aktifken $p oyuncusuna rakibin isClose denemesi (${opponentCloseLeaked.length} adet) gösterildi!');
      }
    }
  }

  return errors;
}

void _playMatch({
  required MatchConfig config,
  required List<Question> questions,
  required math.Random random,
  required int matchNumber,
  required int matchSeed,
  required bool verbose,
  required bool isSmallPool,
  required SimulationStats stats,
}) {
  int nowMs = 1000;
  var engineResult = MatchEngine.start(
    config: config,
    playerIds: ['p1', 'p2'],
    questions: questions,
    random: random,
    nowMs: nowMs,
  );
  var state = engineResult.state;

  // %3 maçta bir oyuncu ortada maçı terk etsin (forfeit)
  final willForfeitThisMatch = random.nextDouble() < 0.03;
  final forfeitRound = 1 + random.nextInt(2); // 1. veya 2. turda
  final forfeitingPlayer = random.nextBool() ? 'p1' : 'p2';
  final forfeitTurn = 1 + random.nextInt(2); // tur içindeki 1. veya 2. sırada
  bool forfeited = false;
  final liveViolations = <String>[];

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

    if (verbose) {
      stdout.writeln('--- Tur $currentRoundNum: ${currentQuestion.text} (Başlayan: $starterName) ---');
    }

    int turnInRound = 0;

    // Tur içi döngü
    while (state.phase == MatchPhase.roundActive) {
      final activePlayerId = state.turnPlayerId!;
      final activePlayerName = _playerName(activePlayerId);
      turnInRound++;

      // Terk etme kontrolü
      if (willForfeitThisMatch && !forfeited && currentRoundNum >= forfeitRound && turnInRound >= forfeitTurn) {
        nowMs += 1000;
        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);
        engineResult = MatchEngine.forfeit(
          state: state,
          playerId: forfeitingPlayer,
          nowMs: nowMs,
        );
        state = engineResult.state;
        stats.forfeitCount++;
        forfeited = true;
        if (verbose) {
          stdout.writeln('[$timeStr] ${_playerName(forfeitingPlayer)}: Maçı terk etti!');
        }
        break;
      }

      final unusedAnswers = currentQuestion.answers
          .where((a) => !state.usedAnswerIds.contains(a.id))
          .toList();

      if (unusedAnswers.isEmpty) {
        break;
      }

      final totalAnswers = currentQuestion.answers.length;
      final remainingRatio = unusedAnswers.length / totalAnswers;
      // Kalan cevap azaldıkça bilme şansı düşer
      final knowChance = (0.35 + 0.60 * remainingRatio).clamp(0.20, 0.95);
      final playerKnows = random.nextDouble() < knowChance;

      // Sırası gelen oyuncu başarısız denemeler yapabilir (yanlış, tekrar, çok yakın)
      final numFailedAttempts = playerKnows
          ? (random.nextDouble() < 0.25 ? 1 + random.nextInt(2) : 0)
          : random.nextInt(3);

      for (int a = 0; a < numFailedAttempts; a++) {
        if (nowMs + 2000 >= state.deadlineMs) {
          break;
        }

        // Anti-abuse testi: %6 ihtimalle 600 ms'den erken gönderip Ignored('tooFast') test et
        final testTooFast = state.lastSubmitTimes[activePlayerId] != null &&
            random.nextDouble() < 0.06;

        if (testTooFast) {
          nowMs += 200;
          final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);
          const spamWord = 'hizli_cevap';
          engineResult = MatchEngine.submit(
            state: state,
            playerId: activePlayerId,
            rawInput: spamWord,
            nowMs: nowMs,
          );
          state = engineResult.state;
          if (engineResult.events.any((e) => e is Ignored)) {
            stats.ignoredAttemptsCount++;
            if (verbose) {
              stdout.writeln('[$timeStr] $activePlayerName: "$spamWord" -> Yok sayıldı (tooFast)!');
            }
          }
          nowMs += 700;
          continue;
        }

        // Normal düşünme / yazma süresi
        nowMs += 700 + random.nextInt(1200);
        if (nowMs >= state.deadlineMs) {
          break;
        }

        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);
        final attemptType = random.nextDouble();

        // 1. Çok Yakın denemesi (%35)
        final nearMissCandidates = unusedAnswers.where((ans) => ans.id.length >= 4).toList();
        if (attemptType < 0.35 && nearMissCandidates.isNotEmpty) {
          final candidate = nearMissCandidates[random.nextInt(nearMissCandidates.length)];
          var typo = _makeTypo(candidate.id);
          if (currentQuestion.answers.any((ans) => ans.aliases.contains(typo))) {
            typo = '${candidate.id}x';
          }

          engineResult = MatchEngine.submit(
            state: state,
            playerId: activePlayerId,
            rawInput: typo,
            nowMs: nowMs,
          );
          state = engineResult.state;

          if (engineResult.events.any((e) => e is NearMiss)) {
            stats.nearMissTriggeredCount++;
            if (verbose) {
              stdout.writeln('[$timeStr] $activePlayerName: "$typo" -> Çok yakın!');
            }
          } else if (engineResult.events.any((e) => e is WrongAnswer)) {
            stats.wrongAttemptsCount++;
            if (verbose) {
              stdout.writeln('[$timeStr] $activePlayerName: "$typo" -> Yanlış cevap (ipucu hakkı bitti)!');
            }
          }
          continue;
        }

        // 2. Tekrar Cevap denemesi (%25)
        if (attemptType < 0.60 && state.usedAnswerIds.isNotEmpty) {
          final repeatedAnswer = currentQuestion.answers.firstWhere(
            (ans) => state.usedAnswerIds.contains(ans.id),
          );

          engineResult = MatchEngine.submit(
            state: state,
            playerId: activePlayerId,
            rawInput: repeatedAnswer.display,
            nowMs: nowMs,
          );
          state = engineResult.state;

          if (engineResult.events.any((e) => e is AlreadySaid)) {
            stats.repeatedAttemptsCount++;
            if (verbose) {
              stdout.writeln('[$timeStr] $activePlayerName: "${repeatedAnswer.display.toLowerCase()}" -> Tekrar cevap!');
            }
          }
          continue;
        }

        // 3. Yanlış Cevap denemesi (%40)
        const fakeWrongWords = [
          'kesinlikle_yanlis_kelime',
          'uydurma_cevap_123',
          'bilinmeyen_yanlis_99',
          'gecersiz_bir_kelime',
        ];
        final wrongWord = fakeWrongWords[random.nextInt(fakeWrongWords.length)];

        engineResult = MatchEngine.submit(
          state: state,
          playerId: activePlayerId,
          rawInput: wrongWord,
          nowMs: nowMs,
        );
        state = engineResult.state;

        if (engineResult.events.any((e) => e is WrongAnswer)) {
          stats.wrongAttemptsCount++;
          if (verbose) {
            stdout.writeln('[$timeStr] $activePlayerName: "$wrongWord" -> Yanlış cevap!');
          }
        }
      }

      // Başarısız denemelerden sonra oyuncunun hamlesi:
      if (playerKnows) {
        nowMs += 700 + random.nextInt(1300);
        if (nowMs >= state.deadlineMs) {
          // Süre yazarken doldu -> timeout
          nowMs = state.deadlineMs + 200;
          if (verbose) {
            stdout.writeln('[00s kaldı] $activePlayerName: (Süre doldu)');
          }
          engineResult = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
          state = engineResult.state;
          break;
        }

        final targetAnswer = unusedAnswers[random.nextInt(unusedAnswers.length)];
        final timeStr = _formatTimeLeft(state.deadlineMs, nowMs);

        engineResult = MatchEngine.submit(
          state: state,
          playerId: activePlayerId,
          rawInput: targetAnswer.display,
          nowMs: nowMs,
        );
        state = engineResult.state;

        if (verbose) {
          stdout.writeln('[$timeStr] $activePlayerName: "${targetAnswer.display.toLowerCase()}" -> Doğru!');
        }
      } else {
        // Oyuncu cevabı bilmiyor -> Süresi dolar
        nowMs = state.deadlineMs + 500;
        if (verbose) {
          stdout.writeln('[00s kaldı] $activePlayerName: (Süre doldu)');
        }
        engineResult = MatchEngine.checkTimeout(state: state, nowMs: nowMs);
        state = engineResult.state;
        break;
      }

      if (state.phase == MatchPhase.roundActive) {
        for (final p in state.playerIds) {
          final opp = state.opponentOf(p);
          final liveVisible = visibleAttempts(state.currentRoundRecord, p, true);
          final hintShownLeaked =
              liveVisible.where((a) => a.hintShown).toList();
          if (hintShownLeaked.isNotEmpty) {
            liveViolations.add(
              'Aktif turda $p oyuncusuna hintShown denemesi sızdı: ${hintShownLeaked.map((a) => a.rawInput).toList()}',
            );
          }
          final leaked =
              liveVisible.where((a) => a.playerId == opp && a.isClose).toList();
          if (leaked.isNotEmpty) {
            liveViolations.add(
              'Aktif turda $p oyuncusuna rakibin isClose denemesi sızdı: ${leaked.map((a) => a.rawInput).toList()}',
            );
          }
        }
      }
    }

    // Tur bittiği andaki istatistikler
    final lastRecord = state.roundHistory.last;
    switch (lastRecord.reason) {
      case RoundEndReason.timeout:
        stats.timeoutCount++;
        break;
      case RoundEndReason.exhausted:
        stats.exhaustedCount++;
        break;
      case RoundEndReason.forfeit:
        break;
    }

    if (verbose) {
      final p1Score = state.scores['p1'] ?? 0;
      final p2Score = state.scores['p2'] ?? 0;
      if (lastRecord.reason == RoundEndReason.forfeit) {
        final roundWinner = _playerName(lastRecord.winnerId!);
        stdout.writeln('Tur $currentRoundNum Bitti: $roundWinner hükmen kazandı (maçı terk etme). Skor: $p1Score - $p2Score\n');
      } else if (lastRecord.winnerId != null) {
        final roundWinner = _playerName(lastRecord.winnerId!);
        final reason = _reasonText(lastRecord.reason);
        stdout.writeln('Tur $currentRoundNum Bitti: $roundWinner kazandı ($reason). Skor: $p1Score - $p2Score\n');
      } else {
        stdout.writeln('Tur $currentRoundNum Bitti: Berabere bitti (cevaplar tükendi). Skor: $p1Score - $p2Score\n');
      }
    }
  }

  // Maç bitti istatistikleri
  final roundsInMatch = state.roundHistory.length;
  stats.totalRoundsPlayed += roundsInMatch;
  stats.maxRoundsPlayed = math.max(stats.maxRoundsPlayed, roundsInMatch);
  if (state.endedBy != 'forfeit') {
    if (state.decisiveRounds == 2) {
      stats.sweepMatchesCount++;
    } else if (state.decisiveRounds == 3) {
      stats.threeRoundMatchesCount++;
    }
    if (roundsInMatch > state.decisiveRounds) {
      stats.extendedMatchesCount++;
    }
  }

  if (verbose) {
    final matchWinner = _playerName(state.winnerId!);
    final p1Final = state.scores['p1'] ?? 0;
    final p2Final = state.scores['p2'] ?? 0;
    if (state.endedBy == 'forfeit') {
      stdout.writeln('=== MAÇ BİTTİ (HÜKMEN): $matchWinner KAZANDI (Rakip terk etti) ===\n');
    } else {
      stdout.writeln('=== MAÇ BİTTİ: $matchWinner KAZANDI ($p1Final - $p2Final) ===\n');
    }
  }

  // Değişmezleri kontrol et
  final violations = [
    ..._checkInvariants(state, questions.length),
    ...liveViolations,
  ];
  if (violations.isNotEmpty) {
    stats.invariantViolations++;
    stdout.writeln('[İHLAL] Maç #$matchNumber (Tohum: $matchSeed):');
    for (final v in violations) {
      stdout.writeln('  - $v');
    }
  }
}

void main(List<String> args) {
  int? baseSeed;
  int matchesCount = 1;
  bool isSmallPool = false;
  int minAnswers = 0;

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--seed=')) {
      baseSeed = int.tryParse(arg.substring('--seed='.length));
    } else if (arg == '--seed' && i + 1 < args.length) {
      baseSeed = int.tryParse(args[++i]);
    } else if (arg.startsWith('--matches=')) {
      matchesCount = int.tryParse(arg.substring('--matches='.length)) ?? 1;
    } else if (arg == '--matches' && i + 1 < args.length) {
      matchesCount = int.tryParse(args[++i]) ?? 1;
    } else if (arg.startsWith('--min-answers=')) {
      minAnswers = int.tryParse(arg.substring('--min-answers='.length)) ?? 0;
    } else if (arg == '--min-answers' && i + 1 < args.length) {
      minAnswers = int.tryParse(args[++i]) ?? 0;
    } else if (arg == '--small-pool') {
      isSmallPool = true;
    } else if (int.tryParse(arg) != null && baseSeed == null) {
      baseSeed = int.tryParse(arg);
    }
  }

  final List<Question> questions;
  if (isSmallPool) {
    questions = _createSmallPool();
  } else {
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
    questions = Question.parseQuestionsPool(jsonData);
  }

  if (questions.isEmpty) {
    stderr.writeln('Hata: Soru havuzunda soru bulunamadı!');
    exit(1);
  }

  final config = MatchConfig(
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 0,
    nearMissPerRound: 1,
    minAnswersPerQuestion: minAnswers,
  );

  final masterRandom = baseSeed != null ? math.Random(baseSeed) : math.Random();
  final stats = SimulationStats();

  if (matchesCount == 1) {
    // Tek maç: Ayrıntılı günlük yazdır
    final matchSeed = baseSeed ?? masterRandom.nextInt(1000000000);
    final matchRandom = math.Random(matchSeed);

    stdout.writeln('========================================');
    stdout.writeln('     KELİMEVS MAÇ SİMÜLASYONU           ');
    stdout.writeln('========================================');
    stdout.writeln('Havuz: ${isSmallPool ? "Küçük Havuz (60 soru)" : "Normal Havuz (140 soru)"}');
    stdout.writeln('Tohum: $matchSeed');
    stdout.writeln('Kurallar: 2 Galibiyet (Best of 3), 15s Süre, 1 Çok Yakın Hakkı');
    stdout.writeln('----------------------------------------\n');

    _playMatch(
      config: config,
      questions: questions,
      random: matchRandom,
      matchNumber: 1,
      matchSeed: matchSeed,
      verbose: true,
      isSmallPool: isSmallPool,
      stats: stats,
    );

    if (stats.invariantViolations == 0) {
      stdout.writeln('Değişmez Kontrolü: BAŞARILI (0 ihlal)\n');
    }
  } else {
    // Çoklu maç: Günlük yazdırma, her maçı farklı tohumla çalıştır ve özet raporla
    for (int m = 1; m <= matchesCount; m++) {
      final matchSeed = masterRandom.nextInt(1000000000);
      final matchRandom = math.Random(matchSeed);

      _playMatch(
        config: config,
        questions: questions,
        random: matchRandom,
        matchNumber: m,
        matchSeed: matchSeed,
        verbose: false,
        isSmallPool: isSmallPool,
        stats: stats,
      );
    }

    final poolDesc = isSmallPool
        ? 'Küçük Havuz (60 yapay soru, 4-5 cevaplı)'
        : 'Normal Havuz (140 soru${minAnswers > 0 ? ", minAnswers: $minAnswers" : ""})';
    final avgRounds = (stats.totalRoundsPlayed / matchesCount).toStringAsFixed(2);
    final sweepPercent = (stats.sweepMatchesCount / matchesCount * 100).toStringAsFixed(1);
    final threeRoundPercent = (stats.threeRoundMatchesCount / matchesCount * 100).toStringAsFixed(1);
    final extPercent = (stats.extendedMatchesCount / matchesCount * 100).toStringAsFixed(1);
    final forfeitPercent = (stats.forfeitCount / matchesCount * 100).toStringAsFixed(1);

    stdout.writeln('============================================================');
    stdout.writeln('              $matchesCount MAÇ SİMÜLASYON ÖZETİ');
    stdout.writeln('============================================================');
    stdout.writeln('Kullanılan Havuz: $poolDesc');
    stdout.writeln('Toplam Maç: $matchesCount');
    stdout.writeln('Toplam Oynanan Tur: ${stats.totalRoundsPlayed}\n');

    stdout.writeln('1. Tur Bitiş Sebepleri:');
    stdout.writeln('   - Süre Aşımı (timeout)     : ${stats.timeoutCount} (%${(stats.timeoutCount / stats.totalRoundsPlayed * 100).toStringAsFixed(1)})');
    stdout.writeln('   - Tükenme (exhausted)       : ${stats.exhaustedCount} (%${(stats.exhaustedCount / stats.totalRoundsPlayed * 100).toStringAsFixed(1)})');
    stdout.writeln('   - Terk Etme (forfeit)       : ${stats.forfeitCount} (%${(stats.forfeitCount / stats.totalRoundsPlayed * 100).toStringAsFixed(1)})\n');

    stdout.writeln('2. Deneme ve İpucu İstatistikleri:');
    stdout.writeln('   - Yanlış Deneme Sayısı      : ${stats.wrongAttemptsCount}');
    stdout.writeln('   - Tekrar Deneme Sayısı      : ${stats.repeatedAttemptsCount}');
    stdout.writeln('   - "Çok Yakın" Tetiklenme    : ${stats.nearMissTriggeredCount}');
    stdout.writeln('   - Yok Sayılan (Ignored)     : ${stats.ignoredAttemptsCount}');
    stdout.writeln('   - Terk Edilen Maç Sayısı    : ${stats.forfeitCount} (%$forfeitPercent)\n');

    stdout.writeln('3. Maç Skoru ve Tur İstatistikleri:');
    stdout.writeln('   - 2-0 Biten Maçlar          : ${stats.sweepMatchesCount} (%$sweepPercent)');
    stdout.writeln('   - 2-1 Biten Maçlar          : ${stats.threeRoundMatchesCount} (%$threeRoundPercent)');
    stdout.writeln('   - Beraberlik Yüzünden Uzayan: ${stats.extendedMatchesCount} (%$extPercent)');
    stdout.writeln('   - Maç Başına Ortalama Tur   : $avgRounds');
    stdout.writeln('   - En Yüksek Tur Sayısı      : ${stats.maxRoundsPlayed}\n');

    stdout.writeln('4. Değişmez (Invariant) Kontrolleri:');
    if (stats.invariantViolations == 0) {
      stdout.writeln('   - İhlal Sayısı: 0 (Tüm değişmezler $matchesCount maçta eksiksiz sağlandı)');
    } else {
      stdout.writeln('   - İhlal Sayısı: ${stats.invariantViolations} (DİKKAT: İhlal tespit edildi!)');
    }
    stdout.writeln('============================================================');
  }
}
