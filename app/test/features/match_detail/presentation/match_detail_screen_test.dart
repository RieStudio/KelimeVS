import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/answer_bubble.dart';
import 'package:app/core/widgets/match_card.dart';
import 'package:app/core/widgets/result_badge.dart';
import 'package:app/features/game/application/match_controller.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/game/application/objection_provider.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/data/local_objection_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/objection/objection.dart';
import 'package:app/features/game/domain/text_filter.dart';
import 'package:app/features/game/presentation/match_end_view.dart';
import 'package:app/features/home/presentation/home_screen.dart';
import 'package:app/features/match_detail/presentation/match_detail_screen.dart';

class CensoringTestFilter implements TextFilter {
  const CensoringTestFilter();
  @override
  String apply(String text) {
    if (text == 'kufur') return '***';
    return text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalObjectionRepository objectionRepo;
  late LocalMatchHistoryRepository historyRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    objectionRepo = LocalObjectionRepository(prefs: prefs);
    historyRepo = LocalMatchHistoryRepository(
      prefs: prefs,
      objectionRepository: objectionRepo,
    );
  });

  Widget createDetailTestWidget({
    required MatchHistoryEntry match,
    TextFilter textFilter = const PassthroughTextFilter(),
  }) {
    return ProviderScope(
      overrides: [
        objectionRepositoryProvider.overrideWithValue(objectionRepo),
        matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
        textFilterProvider.overrideWithValue(textFilter),
      ],
      child: MaterialApp(
        home: MatchDetailScreen(match: match),
      ),
    );
  }

  MatchHistoryEntry createSampleMatch({
    String id = 'test_match_1',
    String? matchId,
    String opponentName = 'Zeynep',
    int myScore = 2,
    int opponentScore = 1,
    MatchResult result = MatchResult.win,
    MatchEndType endType = MatchEndType.normal,
    MatchEndReason? endReason,
    String? forfeitedPlayerId,
    List<RoundRecord>? rounds,
    List<String>? questionTexts,
    bool isFinal = true,
  }) {
    final sampleRounds = rounds ??
        [
          // Tur 1: Kazandım
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Ispanak',
                resultType: AttemptResultType.correct,
                nowMs: 1000,
              ),
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'Pırasa',
                resultType: AttemptResultType.correct,
                nowMs: 2000,
              ),
            ],
          ),
          // Tur 2: Kaybettim
          const RoundRecord(
            questionId: 'q2',
            starterPlayerId: 'bot',
            winnerId: 'bot',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'Almanya',
                resultType: AttemptResultType.correct,
                nowMs: 3000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Amerika',
                resultType: AttemptResultType.wrong,
                nowMs: 4000,
              ),
            ],
          ),
          // Tur 3: Kazandım
          const RoundRecord(
            questionId: 'q3',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Boğa',
                resultType: AttemptResultType.correct,
                nowMs: 5000,
              ),
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'Baykuş',
                resultType: AttemptResultType.correct,
                nowMs: 6000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Bülbül',
                resultType: AttemptResultType.correct,
                nowMs: 7000,
              ),
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'Balık',
                resultType: AttemptResultType.correct,
                nowMs: 8000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Börtlen',
                resultType: AttemptResultType.wrong,
                nowMs: 9000,
              ),
            ],
          ),
        ];

    return MatchHistoryEntry(
      id: id,
      matchId: matchId,
      opponentName: opponentName,
      finishedAtMs: 100000,
      myScore: myScore,
      opponentScore: opponentScore,
      result: result,
      endType: endType,
      endReason: endReason,
      forfeitedPlayerId: forfeitedPlayerId,
      roundRecords: sampleRounds,
      roundQuestionTexts: questionTexts ??
          const ['Kışlık sebzeler', 'G20 ülkeleri', 'B ile başlayan hayvanlar'],
      isFinal: isFinal,
    );
  }

  group('MatchDetailScreen - Özet Kartı ve Üst Bar', () {
    testWidgets('1. Üst bar başlığı ve geri ikonu doğru çizilir', (tester) async {
      final match = createSampleMatch();
      await tester.pumpWidget(createDetailTestWidget(match: match));

      expect(find.text(AppStrings.matchDetail), findsOneWidget);
      expect(find.bySemanticsLabel(AppStrings.back), findsOneWidget);
    });

    testWidgets('2. Özet kartı skor, oyuncu isimleri ve sonucu doğru gösterir', (tester) async {
      final match = createSampleMatch(
        opponentName: 'Zeynep',
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
      );
      await tester.pumpWidget(createDetailTestWidget(match: match));

      expect(find.text(AppStrings.you), findsOneWidget);
      expect(find.text('Zeynep'), findsOneWidget);
      expect(find.text('2 – 1'), findsOneWidget);
      expect(find.text(AppStrings.won), findsAtLeastNWidgets(1));
    });

    testWidgets('3. Terk edilen maçta terk notu görünür', (tester) async {
      final forfeitMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        result: MatchResult.win,
        forfeitedPlayerId: 'bot',
      );
      await tester.pumpWidget(createDetailTestWidget(match: forfeitMatch));

      expect(find.text(AppStrings.opponentLeftMatch), findsOneWidget);
    });

    testWidgets('3b. baglantiKoptu durumunda "Bağlantın koptu" notu görünür', (tester) async {
      final discMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        endReason: MatchEndReason.baglantiKoptu,
        result: MatchResult.lose,
        forfeitedPlayerId: 'me',
      );
      await tester.pumpWidget(createDetailTestWidget(match: discMatch));

      expect(find.text(AppStrings.yourConnectionLost), findsOneWidget);
    });

    testWidgets('3c. rakipBaglantiKoptu durumunda "Rakibin bağlantısı koptu" notu görünür', (tester) async {
      final oppDiscMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        endReason: MatchEndReason.rakipBaglantiKoptu,
        result: MatchResult.win,
        forfeitedPlayerId: 'bot',
      );
      await tester.pumpWidget(createDetailTestWidget(match: oppDiscMatch));

      expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);
    });

    testWidgets('3d. Ben maçı terk ettiğimde "Maçı terk ettin" notu görünür', (tester) async {
      final leaveMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        endReason: MatchEndReason.terk,
        result: MatchResult.lose,
        forfeitedPlayerId: 'me',
      );
      await tester.pumpWidget(createDetailTestWidget(match: leaveMatch));

      expect(find.text(AppStrings.youLeftMatch), findsOneWidget);
    });

    testWidgets('3e. isFinal=false olan baglantiKoptu durumunda "Skor, bağlantı kopmadan önceki duruma göredir." notu görünür', (tester) async {
      final tempMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        endReason: MatchEndReason.baglantiKoptu,
        result: MatchResult.lose,
        forfeitedPlayerId: 'me',
        isFinal: false,
      );
      await tester.pumpWidget(createDetailTestWidget(match: tempMatch));

      expect(find.text(AppStrings.yourConnectionLost), findsOneWidget);
      expect(find.text(AppStrings.scoreBeforeDisconnectNote), findsOneWidget);
    });

    testWidgets('3f. isFinal=true olan baglantiKoptu durumunda "Skor, bağlantı kopmadan önceki duruma göredir." notu GÖRÜNMEZ', (tester) async {
      final finalizedMatch = createSampleMatch(
        endType: MatchEndType.forfeit,
        endReason: MatchEndReason.baglantiKoptu,
        result: MatchResult.lose,
        forfeitedPlayerId: 'me',
        isFinal: true,
      );
      await tester.pumpWidget(createDetailTestWidget(match: finalizedMatch));

      expect(find.text(AppStrings.yourConnectionLost), findsOneWidget);
      expect(find.text(AppStrings.scoreBeforeDisconnectNote), findsNothing);
    });
  });

  group('MatchDetailScreen - Varsayılan Açık Tur ve Kart Açma/Kapama', () {
    testWidgets('4. Kaybedilen son tur varsayılan olarak açık gelir (Tur 2)', (tester) async {
      // Tur 1: Kazandım, Tur 2: Kaybettim, Tur 3: Kazandım -> Tur 2 açık olmalı!
      final match = createSampleMatch();
      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      // Tur 2'nin içeriğindeki 'Amerika' görünür olmalı
      expect(find.text('Amerika'), findsOneWidget);
      // Tur 1'in içeriğindeki 'Ispanak' ve Tur 3'ün içeriğindeki 'Börtlen' kapalı olmalı
      expect(find.text('Ispanak'), findsNothing);
      expect(find.text('Börtlen'), findsNothing);
    });

    testWidgets('5. Hiç kaybedilen tur yoksa son tur varsayılan açık gelir', (tester) async {
      final allWonMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Cevap1',
                resultType: AttemptResultType.correct,
                nowMs: 1000,
              ),
            ],
          ),
          const RoundRecord(
            questionId: 'q2',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'Cevap2',
                resultType: AttemptResultType.correct,
                nowMs: 2000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1', 'Soru 2'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: allWonMatch));
      await tester.pumpAndSettle();

      expect(find.text('Cevap1'), findsNothing);
      expect(find.text('Cevap2'), findsOneWidget);
    });

    testWidgets('6. Tur kartına dokunulduğunda açılır ve kapanır', (tester) async {
      final match = createSampleMatch();
      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      // Başlangıçta Tur 3 kapalı
      expect(find.text('Börtlen'), findsNothing);

      // Tur 3 kartının başlığına dokun
      await tester.tap(find.textContaining('TUR 3'));
      await tester.pumpAndSettle();

      // Şimdi Tur 3 açık ve 'Börtlen' görünür
      expect(find.text('Börtlen'), findsOneWidget);

      // Tekrar dokunup kapat
      await tester.tap(find.textContaining('TUR 3'));
      await tester.pumpAndSettle();

      expect(find.text('Börtlen'), findsNothing);
    });

    testWidgets('7. Berabere ve yarım kalan tur etiketleri üst satırda doğru metinlerle çizilir', (tester) async {
      final neutralMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: null,
            reason: RoundEndReason.exhausted,
            attempts: [],
          ),
          const RoundRecord(
            questionId: 'q2',
            starterPlayerId: 'me',
            winnerId: null,
            reason: RoundEndReason.forfeit,
            attempts: [],
          ),
        ],
        questionTexts: ['Soru 1', 'Soru 2'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: neutralMatch));
      await tester.pumpAndSettle();

      expect(find.textContaining(AppStrings.roundLabelDraw), findsOneWidget);
      expect(find.textContaining(AppStrings.roundLabelIncomplete), findsOneWidget);

      // Tur kartlarında ayrı ResultBadge yoktur; yalnızca üstteki özet kartında 1 adet ResultBadge vardır
      expect(find.byType(ResultBadge), findsOneWidget);
    });

    testWidgets('7b. Terk edilen turda winnerId rakip olsa bile tur etiketi "YARIM KALDI" olur ve maç sonucu "Kaybettin" kalır', (tester) async {
      final forfeitMatch = createSampleMatch(
        result: MatchResult.lose,
        endType: MatchEndType.forfeit,
        forfeitedPlayerId: 'me',
        myScore: 0,
        opponentScore: 1,
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'bot',
            reason: RoundEndReason.forfeit,
            attempts: [],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: forfeitMatch));
      await tester.pumpAndSettle();

      // Tur etiketi YARIM KALDI olmalı ("KAYBETTİN" yazmamalı)
      expect(find.textContaining('TUR 1 · ${AppStrings.roundLabelIncomplete}'), findsOneWidget);
      expect(find.textContaining(AppStrings.roundLabelLost), findsNothing);

      // Üst özet kartında maç sonucu "Kaybettin" ve "Maçı terk ettin" olarak kalmalıdır
      expect(find.text('Kaybettin'), findsOneWidget);
      expect(find.text(AppStrings.youLeftMatch), findsOneWidget);
    });
  });

  group('MatchDetailScreen - Denemeler ve İtiraz Kutusu', () {
    testWidgets('8. Turda hiç deneme yoksa "Bu turda deneme yok" yazar', (tester) async {
      final emptyRoundMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.forfeit,
            attempts: [],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: emptyRoundMatch));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.noAttemptsInRound), findsOneWidget);
    });

    testWidgets('8b. Boş metinli deneme içeren kayıt ekranda balon ve itiraz kutusu üretmez', (tester) async {
      final emptyAttemptMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'bot',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: '   ',
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: '',
                resultType: AttemptResultType.timeout,
                nowMs: 2000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: emptyAttemptMatch));
      await tester.pumpAndSettle();

      // Boş denemeler filtrelendiği için tur boş durumunu göstermelidir
      expect(find.text(AppStrings.noAttemptsInRound), findsOneWidget);
      // Hiçbir balon çizilmemeli
      expect(find.byType(AnswerBubble), findsNothing);
      // İtiraz uyarısı çıkmamalı
      expect(find.textContaining('kabul edilmedi'), findsNothing);
      expect(find.text(AppStrings.appeal), findsNothing);
    });

    testWidgets('8c. Maç Detayı ekranında hem kendi hem rakibin yakın denemeleri (isClose=true) görünür', (tester) async {
      final closeAttemptMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'aude',
                resultType: AttemptResultType.nearMiss,
                nowMs: 1000,
                isClose: true,
                hintShown: true,
              ),
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'ferari',
                resultType: AttemptResultType.wrong,
                nowMs: 2000,
                isClose: true,
                hintShown: false,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: closeAttemptMatch));
      await tester.pumpAndSettle();

      // İki deneme de görünür olmalı
      expect(find.text('aude'), findsOneWidget);
      expect(find.text('ferari'), findsOneWidget);
    });

    testWidgets('9. Rakibin denemeleri TextFilter filtresinden geçer', (tester) async {
      final filteredMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'kufur',
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(
        match: filteredMatch,
        textFilter: const CensoringTestFilter(),
      ));
      await tester.pumpAndSettle();

      // kufur sansürlenmiş olmalı
      expect(find.text('***'), findsOneWidget);
      expect(find.text('kufur'), findsNothing);
    });

    testWidgets('10. Varsayılan seçili son reddedilen cevaptır ve itiraz akışı çalışır', (tester) async {
      final match = createSampleMatch();
      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      // Tur 2 açık ('Amerika' yanlış cevabım)
      expect(find.text('“Amerika” kabul edilmedi. Sence doğru muydu?'), findsOneWidget);
      expect(find.text(AppStrings.appeal), findsOneWidget);

      // "İtiraz et"e tıkla
      await tester.tap(find.text(AppStrings.appeal));
      await tester.pumpAndSettle();

      // UI "İtiraz gönderildi"ye dönmeli
      expect(find.text(AppStrings.objectionSent), findsOneWidget);
      expect(find.text(AppStrings.appeal), findsNothing);

      // Repository'ye kaydedilmiş olmalı
      final saved = await objectionRepo.loadForMatch(match.id);
      expect(saved, hasLength(1));
      expect(saved.first.attemptIndex, 1);
    });

    testWidgets('11. Önceden yapılmış itiraz ekranda "İtiraz gönderildi" olarak açılır', (tester) async {
      final match = createSampleMatch();
      // Önceden itiraz ekle (Tur 2, index 1: 'Amerika')
      await objectionRepo.add(Objection(
        matchId: match.id,
        roundIndex: 1,
        attemptIndex: 1,
        rawInput: 'Amerika',
        createdAtMs: 1000,
      ));

      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.objectionSent), findsOneWidget);
      expect(find.text(AppStrings.appeal), findsNothing);
    });

    testWidgets('12. alreadySaid cevabında "Bu cevap daha önce söylenmişti" yazar ve link olmaz', (tester) async {
      final repeatedMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'bot',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'tekrar_kelime',
                resultType: AttemptResultType.repeated,
                nowMs: 1000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: repeatedMatch));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.alreadySaidNotice), findsOneWidget);
      expect(find.text(AppStrings.appeal), findsNothing);
    });

    testWidgets('13. Kullanıcı başka bir kırmızı cevabına dokununca seçim o cevaba geçer', (tester) async {
      final multiRejectMatch = createSampleMatch(
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'bot',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'red1',
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'red2',
                resultType: AttemptResultType.wrong,
                nowMs: 2000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: multiRejectMatch));
      await tester.pumpAndSettle();

      // Varsayılan olarak sonuncu olan 'red2' seçili
      expect(find.text('“red2” kabul edilmedi. Sence doğru muydu?'), findsOneWidget);

      // 'red1' balonuna dokun
      await tester.tap(find.text('red1'));
      await tester.pumpAndSettle();

      // Şimdi 'red1' seçili olmalı
      expect(find.text('“red1” kabul edilmedi. Sence doğru muydu?'), findsOneWidget);
    });
  });

  group('MatchDetailScreen - Giriş Noktaları Entegrasyonu', () {
    testWidgets('14. HomeScreen üzerinde MatchCard dokunulduğunda MatchDetailScreen açılır', (tester) async {
      final entry = createSampleMatch();
      await historyRepo.add(entry);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
            objectionRepositoryProvider.overrideWithValue(objectionRepo),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MatchCard), findsOneWidget);

      // MatchCard'a tıkla
      await tester.tap(find.byType(MatchCard));
      await tester.pumpAndSettle();

      // MatchDetailScreen açılmış olmalı
      expect(find.byType(MatchDetailScreen), findsOneWidget);
      expect(find.text(AppStrings.matchDetail), findsOneWidget);
    });

    testWidgets('15. MatchEndView "Maç Detayı" butonuna dokunulduğunda MatchDetailScreen açılır', (tester) async {
      final entry = createSampleMatch();
      await historyRepo.add(entry);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
            objectionRepositoryProvider.overrideWithValue(objectionRepo),
            matchControllerProvider.overrideWith(
              () => _FakeMatchController(
                MatchUiState(
                  lastSavedMatch: entry,
                  summary: MatchSummary(
                    scores: {'me': entry.myScore, 'bot': entry.opponentScore},
                    winnerId: entry.result == MatchResult.win ? 'me' : 'bot',
                    roundHistory: entry.roundRecords,
                  ),
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: MatchEndView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchDetail), findsOneWidget);

      // "Maç Detayı" butonuna bas
      await tester.tap(find.text(AppStrings.matchDetail));
      await tester.pumpAndSettle();

      expect(find.byType(MatchDetailScreen), findsOneWidget);
    });
  });
}

class _FakeMatchController extends MatchController {
  final MatchUiState _initialState;

  _FakeMatchController(this._initialState);

  @override
  MatchUiState build() => _initialState;
}
