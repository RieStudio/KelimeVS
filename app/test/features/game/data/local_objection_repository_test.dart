import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/features/game/data/local_match_history_repository.dart';
import 'package:app/features/game/data/local_objection_repository.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';
import 'package:app/features/game/domain/objection/objection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalObjectionRepository objectionRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    objectionRepo = LocalObjectionRepository(prefs: prefs);
  });

  group('LocalObjectionRepository', () {
    test('1. Başlangıçta kayıtlı itiraz yoksa boş set döner', () async {
      final objections = await objectionRepo.loadForMatch('match_1');
      expect(objections, isEmpty);
    });

    test('2. İtiraz eklendiğinde loadForMatch ile doğru ObjectionKey döner', () async {
      final obj = Objection(
        matchId: 'match_1',
        roundIndex: 0,
        attemptIndex: 2,
        rawInput: 'elma',
        createdAtMs: 123456789,
      );

      await objectionRepo.add(obj);

      final result = await objectionRepo.loadForMatch('match_1');
      expect(result.length, 1);
      expect(
        result.first,
        equals(const ObjectionKey(matchId: 'match_1', roundIndex: 0, attemptIndex: 2)),
      );
    });

    test('3. Aynı (roundIndex, attemptIndex) için ikinci itiraz eklenmez (tekillik)', () async {
      final obj1 = Objection(
        matchId: 'match_1',
        roundIndex: 1,
        attemptIndex: 3,
        rawInput: 'armut',
        createdAtMs: 1000,
      );
      final obj2 = Objection(
        matchId: 'match_1',
        roundIndex: 1,
        attemptIndex: 3,
        rawInput: 'armut 2',
        createdAtMs: 2000,
      );

      await objectionRepo.add(obj1);
      await objectionRepo.add(obj2);

      final result = await objectionRepo.loadForMatch('match_1');
      expect(result.length, 1);
    });

    test('4. Farklı maçların itirazları birbirine karışmaz', () async {
      await objectionRepo.add(Objection(
        matchId: 'match_A',
        roundIndex: 0,
        attemptIndex: 1,
        rawInput: 'kiraz',
        createdAtMs: 100,
      ));
      await objectionRepo.add(Objection(
        matchId: 'match_B',
        roundIndex: 0,
        attemptIndex: 1,
        rawInput: 'karpuz',
        createdAtMs: 200,
      ));

      final resultA = await objectionRepo.loadForMatch('match_A');
      final resultB = await objectionRepo.loadForMatch('match_B');

      expect(resultA.length, 1);
      expect(resultB.length, 1);
      expect(resultA.first.matchId, 'match_A');
      expect(resultB.first.matchId, 'match_B');
    });

    test('5. cleanupOrphaned geçerli maçlar listesinde olmayan itirazları siler', () async {
      await objectionRepo.add(Objection(
        matchId: 'match_1',
        roundIndex: 0,
        attemptIndex: 0,
        rawInput: 'cevap1',
        createdAtMs: 100,
      ));
      await objectionRepo.add(Objection(
        matchId: 'match_2',
        roundIndex: 0,
        attemptIndex: 0,
        rawInput: 'cevap2',
        createdAtMs: 200,
      ));
      await objectionRepo.add(Objection(
        matchId: 'match_3',
        roundIndex: 0,
        attemptIndex: 0,
        rawInput: 'cevap3',
        createdAtMs: 300,
      ));

      // match_1 listeden düştü (sadece match_2 ve match_3 geçerli)
      await objectionRepo.cleanupOrphaned({'match_2', 'match_3'});

      final res1 = await objectionRepo.loadForMatch('match_1');
      final res2 = await objectionRepo.loadForMatch('match_2');
      final res3 = await objectionRepo.loadForMatch('match_3');

      expect(res1, isEmpty);
      expect(res2, hasLength(1));
      expect(res3, hasLength(1));
    });

    test('6. LocalMatchHistoryRepository 10 maç sınırında eski maçın itirazlarını temizler', () async {
      final historyRepo = LocalMatchHistoryRepository(
        prefs: prefs,
        objectionRepository: objectionRepo,
      );

      // 10 maç ekle
      for (int i = 1; i <= 10; i++) {
        await historyRepo.add(MatchHistoryEntry(
          id: 'match_$i',
          opponentName: 'Rakip $i',
          finishedAtMs: i * 1000,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: const [],
          roundQuestionTexts: const [],
        ));
      }

      // match_1 için itiraz ekle (en eski maç, finishedAtMs: 1000)
      await objectionRepo.add(Objection(
        matchId: 'match_1',
        roundIndex: 0,
        attemptIndex: 0,
        rawInput: 'eski_itiraz',
        createdAtMs: 500,
      ));

      // match_10 için de itiraz ekle
      await objectionRepo.add(Objection(
        matchId: 'match_10',
        roundIndex: 0,
        attemptIndex: 0,
        rawInput: 'yeni_itiraz',
        createdAtMs: 10000,
      ));

      expect(await objectionRepo.loadForMatch('match_1'), hasLength(1));
      expect(await objectionRepo.loadForMatch('match_10'), hasLength(1));

      // 11. maçı ekle (finishedAtMs: 11000). match_1 10 maçlık sınırdan düşer!
      await historyRepo.add(MatchHistoryEntry(
        id: 'match_11',
        opponentName: 'Rakip 11',
        finishedAtMs: 11000,
        myScore: 2,
        opponentScore: 1,
        result: MatchResult.win,
        endType: MatchEndType.normal,
        roundRecords: const [],
        roundQuestionTexts: const [],
      ));

      // match_1'in itirazı temizlenmiş olmalı
      expect(await objectionRepo.loadForMatch('match_1'), isEmpty);
      // match_10 hâlâ listede olduğu için itirazı durmalı
      expect(await objectionRepo.loadForMatch('match_10'), hasLength(1));
    });
  });
}
