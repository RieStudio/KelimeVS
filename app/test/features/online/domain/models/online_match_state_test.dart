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

    test('tam 15 saniye (15000 ms) kaldığında tam 15000 ms döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 25000, // 25000 - 10000 = 15000
      );

      expect(state.kalanSureMs(10000), 15000);
      expect(state.remainingDeadlineMs(10000), 15000);
    });

    test('orta değerde (örn. 7500 ms) tam kalan süreyi döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 25000,
      );

      // 7.5 saniye sonra: 25000 - 17500 = 7500
      expect(state.kalanSureMs(17500), 7500);
    });

    test('tam 0 ms kaldığında 0 döner', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 25000,
      );

      // Tam deadline anı: localNow = 25000
      expect(state.kalanSureMs(25000), 0);
    });

    test('süre dolduğunda ve negatif zamana geçtiğinde 0 ile clamp edilir (asla negatif dönmez)', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 25000,
      );

      // Deadline'dan 1 ms sonra (-1)
      expect(state.kalanSureMs(25001), 0);
      // Deadline'dan 5 saniye sonra (-5000)
      expect(state.kalanSureMs(30000), 0);
      // Deadline'dan 1 saat sonra (-3600000)
      expect(state.kalanSureMs(3625000), 0);
    });

    test('15 saniyeden büyük süreler (saat sapması / askıya alma) maxDurationMs (15000 ms) ile clamp edilir', () {
      final state = createState(
        serverNowMs: 10000,
        receivedLocalMs: 10000,
        deadlineMs: 25000,
      );

      // 15001 ms kaldığı iddia edilirse
      expect(state.kalanSureMs(9999), 15000);

      // HATA 2'de görülen devasa süre senaryosu (4,965,000 ms sapma)
      // Telefon uykudan uyandı, localNow çok geride kaldı varsayımı
      expect(state.kalanSureMs(10000 - 4950000), 15000);
    });

    test('sunucu saat sapması (clockOffsetMs) doğru hesaba katılır ve sınırlar korunur', () {
      // Sunucu 5000 ms ileride
      final state = createState(
        serverNowMs: 20000,
        receivedLocalMs: 15000, // clockOffset = +5000
        deadlineMs: 35000,      // sunucu saatine göre 15000 ms sonra
      );

      expect(state.clockOffsetMs, 5000);

      // Başlangıç anı: localNow = 15000 -> estimatedServerNow = 20000 -> kalan 15000 ms
      expect(state.kalanSureMs(15000), 15000);

      // 5 saniye sonra: localNow = 20000 -> estimatedServerNow = 25000 -> kalan 10000 ms
      expect(state.kalanSureMs(20000), 10000);

      // Süre bittiğinde: localNow = 30000 -> estimatedServerNow = 35000 -> kalan 0 ms
      expect(state.kalanSureMs(30000), 0);

      // Süre aşıldığında: localNow = 31000 -> estimatedServerNow = 36000 -> kalan 0 ms
      expect(state.kalanSureMs(31000), 0);

      // Anormal zaman kayması: localNow çok küçükse -> 15000 ile sınırlanır
      expect(state.kalanSureMs(5000), 15000);
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
}
