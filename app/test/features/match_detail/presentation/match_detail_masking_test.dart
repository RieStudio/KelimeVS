import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/text_filter/app_text_filter.dart';
import 'package:app/features/game/application/match_history_provider.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/objection_provider.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/data/local_objection_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/match_detail/presentation/match_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalObjectionRepository objectionRepo;
  late LocalMatchHistoryRepository historyRepo;
  late AppTextFilter appTextFilter;

  setUpAll(() {
    File? blocklistFile;
    for (final p in [
      'assets/text_filter/blocklist.json',
      'app/assets/text_filter/blocklist.json',
      '../app/assets/text_filter/blocklist.json',
    ]) {
      final f = File(p);
      if (f.existsSync()) {
        blocklistFile = f;
        break;
      }
    }
    expect(blocklistFile, isNotNull);
    final jsonMap = json.decode(blocklistFile!.readAsStringSync()) as Map<String, dynamic>;
    appTextFilter = AppTextFilter.fromJson(jsonMap);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    objectionRepo = LocalObjectionRepository(prefs: prefs);
    historyRepo = LocalMatchHistoryRepository(
      prefs: prefs,
      objectionRepository: objectionRepo,
    );
  });

  MatchHistoryEntry createMatch({
    required String id,
    required List<RoundRecord> rounds,
    required List<String> questionTexts,
    MatchResult result = MatchResult.win,
  }) {
    return MatchHistoryEntry(
      id: id,
      opponentName: 'Bot Ahmet',
      finishedAtMs: DateTime(2026, 11, 21).millisecondsSinceEpoch,
      myScore: result == MatchResult.win ? 2 : 0,
      opponentScore: result == MatchResult.win ? 0 : 2,
      result: result,
      endType: MatchEndType.normal,
      endReason: MatchEndReason.normal,
      roundRecords: rounds,
      roundQuestionTexts: questionTexts,
      botlaOynandi: true,
      isFinal: true,
    );
  }

  Widget createDetailTestWidget({required MatchHistoryEntry match}) {
    return ProviderScope(
      overrides: [
        objectionRepositoryProvider.overrideWithValue(objectionRepo),
        matchHistoryRepositoryProvider.overrideWithValue(historyRepo),
        textFilterProvider.overrideWithValue(appTextFilter),
      ],
      child: MaterialApp(
        home: MatchDetailScreen(match: match),
      ),
    );
  }

  group('MatchDetailScreen Maskeleme & İtiraz Testleri', () {
    testWidgets('Kullanıcının kendi uygunsuz cevabı balonda maskelenir', (tester) async {
      final match = createMatch(
        id: 'mask_test_1',
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: 'orospu',
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'ankara',
                resultType: AttemptResultType.correct,
                displayText: 'Ankara',
                nowMs: 2000,
              ),
            ],
          ),
        ],
        questionTexts: ['Başkent neresidir?'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      // Tur 1 kartını aç
      await tester.tap(find.textContaining('TUR 1'));
      await tester.pumpAndSettle();

      // Kullanıcının kendi cevabı ekranda maskelenmiş görünmeli
      expect(find.text('o*****'), findsOneWidget);
      expect(find.text('orospu'), findsNothing);
    });

    testWidgets('İtiraz kutusunda maskelenmiş metin görünür, ama itiraz ham metinle kaydedilir', (tester) async {
      const rawBadWord = 'orospu';
      final match = createMatch(
        id: 'mask_test_2',
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'me',
            winnerId: 'me',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'me',
                rawInput: rawBadWord,
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
            ],
          ),
        ],
        questionTexts: ['Soru 1'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: match));
      await tester.pumpAndSettle();

      // Tur 1 kartını aç
      await tester.tap(find.textContaining('TUR 1'));
      await tester.pumpAndSettle();

      // Varsayılan olarak reddedilen son cevap seçilidir ve itiraz kutusu görünür
      final expectedPrompt = AppStrings.objectionPrompt('o*****');
      expect(find.text(expectedPrompt), findsOneWidget);
      expect(find.textContaining(rawBadWord), findsNothing);

      // İtiraz Et butonuna tıkla
      await tester.tap(find.text(AppStrings.appeal));
      await tester.pumpAndSettle();

      // "İtiraz gönderildi" metni görünmeli
      expect(find.text(AppStrings.objectionSent), findsOneWidget);

      // Veritabanına / repoya kaydedilen itiraz ham metinle (rawBadWord) kaydedilmiş olmalıdır!
      final rawSaved = prefs.getString('kelimego_objections');
      expect(rawSaved, isNotNull);
      final list = json.decode(rawSaved!) as List<dynamic>;
      expect(list.length, 1);
      expect(list.first['rawInput'], rawBadWord);
      expect(list.first['matchId'], match.id);
    });

    testWidgets('Eski/tarihi maç geçmişinde hem kullanıcının hem rakibin cevapları maskelenir', (tester) async {
      final historicMatch = createMatch(
        id: 'hist_match_1',
        result: MatchResult.lose,
        rounds: [
          const RoundRecord(
            questionId: 'q1',
            starterPlayerId: 'bot',
            winnerId: 'bot',
            reason: RoundEndReason.timeout,
            attempts: [
              TurnAttempt(
                playerId: 'bot',
                rawInput: 'sik',
                resultType: AttemptResultType.wrong,
                nowMs: 1000,
              ),
              TurnAttempt(
                playerId: 'me',
                rawInput: 'pic',
                resultType: AttemptResultType.wrong,
                nowMs: 2000,
              ),
            ],
          ),
        ],
        questionTexts: ['Tarihi Soru'],
      );

      await tester.pumpWidget(createDetailTestWidget(match: historicMatch));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('TUR 1'));
      await tester.pumpAndSettle();

      // Rakibin uygunsuz cevabı s** olarak maskelenmeli
      expect(find.text('s**'), findsOneWidget);
      expect(find.text('sik'), findsNothing);

      // Kullanıcının uygunsuz cevabı p** olarak maskelenmeli
      expect(find.text('p**'), findsOneWidget);
      expect(find.text('pic'), findsNothing);
    });
  });
}
