import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/utils/date_formatter.dart';

void main() {
  group('formatMatchDate tests', () {
    final now = DateTime(2026, 10, 8, 20, 30); // 8 Ekim 2026, Perşembe

    test('Bugün (aynı takvim günü)', () {
      final earlierToday = DateTime(2026, 10, 8, 0, 5);
      expect(formatMatchDate(earlierToday, now: now), 'Bugün');

      // Gelecek saatler de bugün sayılır
      final laterToday = DateTime(2026, 10, 8, 23, 59);
      expect(formatMatchDate(laterToday, now: now), 'Bugün');
    });

    test('Dün (1 takvim günü önce)', () {
      final yesterday = DateTime(2026, 10, 7, 23, 59);
      expect(formatMatchDate(yesterday, now: now), 'Dün');

      final yesterdayMorning = DateTime(2026, 10, 7, 8, 0);
      expect(formatMatchDate(yesterdayMorning, now: now), 'Dün');
    });

    test('2-6 gün önce', () {
      expect(formatMatchDate(DateTime(2026, 10, 6), now: now), '2 gün önce');
      expect(formatMatchDate(DateTime(2026, 10, 5), now: now), '3 gün önce');
      expect(formatMatchDate(DateTime(2026, 10, 4), now: now), '4 gün önce');
      expect(formatMatchDate(DateTime(2026, 10, 3), now: now), '5 gün önce');
      expect(formatMatchDate(DateTime(2026, 10, 2), now: now), '6 gün önce');
    });

    test('7-13 gün önce (1 hafta önce)', () {
      expect(formatMatchDate(DateTime(2026, 10, 1), now: now), '1 hafta önce');
      expect(formatMatchDate(DateTime(2026, 9, 30), now: now), '1 hafta önce'); // 8 gün
      expect(formatMatchDate(DateTime(2026, 9, 25), now: now), '1 hafta önce'); // 13 gün
    });

    test('14-20 gün önce (2 hafta önce)', () {
      expect(formatMatchDate(DateTime(2026, 9, 24), now: now), '2 hafta önce'); // 14 gün
      expect(formatMatchDate(DateTime(2026, 9, 18), now: now), '2 hafta önce'); // 20 gün
    });

    test('21-27 gün önce (3 hafta önce)', () {
      expect(formatMatchDate(DateTime(2026, 9, 17), now: now), '3 hafta önce'); // 21 gün
      expect(formatMatchDate(DateTime(2026, 9, 11), now: now), '3 hafta önce'); // 27 gün
    });

    test('28+ gün önce (gg.aa.yyyy)', () {
      expect(formatMatchDate(DateTime(2026, 9, 10), now: now), '10.09.2026'); // 28 gün
      expect(formatMatchDate(DateTime(2026, 1, 5), now: now), '05.01.2026');
      expect(formatMatchDate(DateTime(2025, 12, 25), now: now), '25.12.2025');
    });

    test('formatMatchDateMs epoch desteği', () {
      final ms = DateTime(2026, 10, 8, 12, 0).millisecondsSinceEpoch;
      expect(formatMatchDateMs(ms, now: now), 'Bugün');
    });
  });
}

