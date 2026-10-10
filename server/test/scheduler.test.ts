import { describe, expect, it } from 'vitest';
import {
  computeNextAlarm,
  getRoomDurations,
  processDueTimers,
  type TimersSchedule,
} from '../src/scheduler';

describe('Scheduler and Alarm Management', () => {
  describe('getRoomDurations', () => {
    it('FAST_TIMERS false iken standart süreleri döndürür', () => {
      const d = getRoomDurations(false);
      expect(d.answerSeconds).toBe(15);
      expect(d.roundTransitionMs).toBe(3000);
      expect(d.disconnectTimeoutMs).toBe(30000);
      expect(d.connectTimeoutMs).toBe(10000);
      expect(d.cleanupMs).toBe(600000);
    });

    it('FAST_TIMERS true iken hızlandırılmış süreleri döndürür', () => {
      const d = getRoomDurations(true);
      expect(d.answerSeconds).toBe(3);
      expect(d.roundTransitionMs).toBe(500);
      expect(d.disconnectTimeoutMs).toBe(3000);
      expect(d.connectTimeoutMs).toBe(3000);
      expect(d.cleanupMs).toBe(600000);
    });
  });

  describe('computeNextAlarm', () => {
    it('boş takvimde null döner', () => {
      expect(computeNextAlarm({})).toBeNull();
    });

    it('tek zamanlayıcı olduğunda o değeri döner', () => {
      expect(computeNextAlarm({ turnDeadlineMs: 15000 })).toBe(15000);
    });

    it('birden fazla zamanlayıcı olduğunda en yakın (en küçük) değeri döner', () => {
      const schedule: TimersSchedule = {
        turnDeadlineMs: 20000,
        nextRoundAtMs: 25000,
        connectTimeoutAtMs: 12000,
        cleanupAtMs: 600000,
      };
      expect(computeNextAlarm(schedule)).toBe(12000);
    });
  });

  describe('processDueTimers', () => {
    it('hiçbir zamanlayıcının vadesi gelmemişse boş döner', () => {
      const schedule: TimersSchedule = {
        turnDeadlineMs: 20000,
        nextRoundAtMs: 25000,
      };
      const res = processDueTimers(schedule, 10000);
      expect(res.dueActions).toEqual([]);
      expect(res.remainingSchedule).toEqual(schedule);
    });

    it('vadesi gelen zamanlayıcıyı seçer ve takvimden kaldırır', () => {
      const schedule: TimersSchedule = {
        connectTimeoutAtMs: 10000,
        turnDeadlineMs: 25000,
      };
      const res = processDueTimers(schedule, 10000);
      expect(res.dueActions).toEqual(['connectTimeout']);
      expect(res.remainingSchedule).toEqual({ turnDeadlineMs: 25000 });
    });

    it('aynı anda birden fazla zamanlayıcı dolduğunda hepsini işler', () => {
      const schedule: TimersSchedule = {
        turnDeadlineMs: 15000,
        disconnectTimeoutAtMs: 15000,
      };
      const res = processDueTimers(schedule, 15000);
      expect(res.dueActions).toContain('disconnectForfeit');
      expect(res.dueActions).toContain('turnTimeout');
      expect(res.remainingSchedule).toEqual({});
    });
  });
});

