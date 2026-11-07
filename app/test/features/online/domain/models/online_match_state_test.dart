import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';

void main() {
  group('OnlineMatchState - kalanSureMs Boundary Tests', () {
    OnlineMatchState createState({
      required int serverNowMs,
      required int receivedLocalMs,
      required int deadlineMs,
    }) {
      return OnlineMatchState(
        serverNowMs: serverNowMs,
        receivedLocalMs: receivedLocalMs,
        phase: OnlineMatchPhase.roundActive,
        roundNumber: 1,
        myScore: 0,
        opponentScore: 0,
        turnIsMine: true,
        deadlineMs: deadlineMs,
        myHintsLeft: 3,
        attempts: const [],
        opponentName: 'Rakip',
        opponentConnected: true,
      );
    }

    test('tam 20 saniye (20000 ms) kaldığında tam 20000 ms döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000, // 30000 - 10000 = 20000
      );

      expect(state.kalanSureMs(10000), 20000);
      expect(state.remainingDeadlineMs(10000), 20000);
    });

    test('orta değerde (örn. 10000 ms) tam kalan süreyi döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000,
      );

      // 10 saniye sonra: 30000 - 20000 = 10000
      expect(state.kalanSureMs(20000), 10000);
    });

    test('tam 0 ms kaldığında 0 döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000,
      );

      // Tam deadline anı: localNow = 30000
      expect(state.kalanSureMs(30000), 0);
    });

    test('süre dolduğunda ve negatif zamana geçtiğinde 0 ile clamp edilir (asla negatif dönmez)', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000,
      );

      // Deadline'dan 1 ms sonra (-1)
      expect(state.kalanSureMs(30001), 0);
      // Deadline'dan 5 saniye sonra (-5000)
      expect(state.kalanSureMs(35000), 0);
      // Deadline'dan 1 saat sonra (-3600000)
      expect(state.kalanSureMs(3630000), 0);
    });

    test('20 saniyeden büyük süreler (saat sapması / askıya alma) maxDurationMs (20000 ms) ile clamp edilir', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000,
      );

      // 20001 ms kaldığı iddia edilirse
      expect(state.kalanSureMs(9999), 20000);

      // HATA 2'de görülen devasa süre senaryosu (4,965,000 ms sapma)
      // Telefon uykudan uyandı, localNow çok geride kaldı varsayımı
      expect(state.kalanSureMs(10000 - 4950000), 20000);
    });

    test('sunucu saat sapması (clockOffsetMs) doğru hesaba katılır ve sınırlar korunur', () {
      // Sunucu 5000 ms ileride
      final state = createState(
        serverNowMs: 20000,
        receivedLocalMs: 15000, // clockOffset = +5000
        deadlineMs: 40000,      // sunucu saatine göre 20000 ms sonra
      );

      expect(state.clockOffsetMs, 5000);

      // Başlangıç anı: localNow = 15000 -> estimatedServerNow = 20000 -> kalan 20000 ms
      expect(state.kalanSureMs(15000), 20000);

      // 5 saniye sonra: localNow = 20000 -> estimatedServerNow = 25000 -> kalan 15000 ms
      expect(state.kalanSureMs(20000), 15000);

      // Süre bittiğinde: localNow = 35000 -> estimatedServerNow = 40000 -> kalan 0 ms
      expect(state.kalanSureMs(35000), 0);

      // Süre aşıldığında: localNow = 36000 -> estimatedServerNow = 41000 -> kalan 0 ms
      expect(state.kalanSureMs(36000), 0);

      // Anormal zaman kayması: localNow çok küçükse -> 20000 ile sınırlanır
      expect(state.kalanSureMs(5000), 20000);
    });

    test('özel maxDurationMs verildiğinde o değerle sınırlandırılır', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 30000, // 20000 ms fark
      );

      expect(state.kalanSureMs(10000, maxDurationMs: 10000), 10000);
      expect(state.kalanSureMs(10000, maxDurationMs: 8000), 8000);
    });
  });

  group('OnlineMatchState - nextQuestion parsing tests', () {
    test('roundEnded fazında nextQuestion alanı doğru ayrıştırılır', () {
      final json = {
        'serverNowMs': 10000,
        'phase': 'roundEnded',
        'roundNumber': 1,
        'scores': {'me': 1, 'opponent': 0},
        'nextRoundAtMs': 13500,
        'nextQuestion': {
          'id': 'q_next_2',
          'text': 'Türkiye Coğrafyası',
        },
      };

      final state = OnlineMatchState.fromJson(json);
      expect(state.nextQuestion, isNotNull);
      expect(state.nextQuestion!.id, 'q_next_2');
      expect(state.nextQuestion!.text, 'Türkiye Coğrafyası');
    });

    test('nextQuestion alanı yoksa veya null ise state.nextQuestion null olur (geriye uyumluluk)', () {
      final json = {
        'serverNowMs': 10000,
        'phase': 'roundEnded',
        'roundNumber': 1,
        'scores': {'me': 1, 'opponent': 0},
      };

      final state = OnlineMatchState.fromJson(json);
      expect(state.nextQuestion, isNull);
    });
  });
}
