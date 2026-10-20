import { describe, expect, it, vi } from 'vitest';
import { DatabaseSync } from 'node:sqlite';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

import { ReportStore } from '../src/reportStore';
import type { Env } from '../src/index';

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  let alarmTime: number | null = null;
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      if (trimmed.toUpperCase().startsWith('SELECT')) {
        const stmt = db.prepare(trimmed);
        const rows = stmt.all(...bindings) as T[];
        return {
          toArray: () => rows,
          one: () => rows[0],
          [Symbol.iterator]: () => rows[Symbol.iterator](),
        };
      } else {
        if (bindings.length > 0) {
          const stmt = db.prepare(trimmed);
          stmt.run(...bindings);
        } else {
          db.exec(trimmed);
        }
        return {
          toArray: () => [],
          one: () => undefined as any,
          [Symbol.iterator]: () => [][Symbol.iterator](),
        };
      }
    },
  };

  return {
    storage: {
      sql,
      async getAlarm() {
        return alarmTime;
      },
      async setAlarm(time: number) {
        alarmTime = time;
      },
      async deleteAlarm() {
        alarmTime = null;
      },
    },
  } as unknown as DurableObjectState;
}

describe('ReportStore Durable Object Tests', () => {
  const mockEnv = {
    MAX_REPORTS_PER_DAY: '3',
  } as unknown as Env;

  it('1. Bildirim başarıyla kaydedilir ve listelenir', async () => {
    const ctx = createMockCtx();
    const store = new ReportStore(ctx, mockEnv);

    const res = await store.addReport({
      reporterUid: 'user_1',
      reportedUid: 'user_2',
      matchId: 'match_100',
      reason: 'inappropriate_nickname',
      reportedNickname: 'KotuOyuncu',
      answers: ['kufur1', 'kufur2'],
    });

    expect(res.ok).toBe(true);

    const list = await store.getReports();
    expect(list.total).toBe(1);
    expect(list.reports[0].reportedNickname).toBe('KotuOyuncu');
    expect(list.reports[0].answers).toEqual(['kufur1', 'kufur2']);
    expect(list.reports[0].reason).toBe('inappropriate_nickname');
  });

  it('2. Aynı maç için mükerrer bildirim engellenir (already_reported)', async () => {
    const ctx = createMockCtx();
    const store = new ReportStore(ctx, mockEnv);

    await store.addReport({
      reporterUid: 'user_1',
      reportedUid: 'user_2',
      matchId: 'match_100',
      reason: 'cheating',
      reportedNickname: 'Hileci',
      answers: [],
    });

    const res2 = await store.addReport({
      reporterUid: 'user_1',
      reportedUid: 'user_2',
      matchId: 'match_100',
      reason: 'other',
      reportedNickname: 'Hileci',
      answers: [],
    });

    expect(res2.ok).toBe(false);
    if (!res2.ok) {
      expect(res2.error).toBe('already_reported');
    }
  });

  it('3. Günlük bildirim üst sınırı aşılınca daily_limit_exceeded döner', async () => {
    const ctx = createMockCtx();
    const store = new ReportStore(ctx, mockEnv); // Limit 3

    for (let i = 1; i <= 3; i++) {
      const res = await store.addReport({
        reporterUid: 'user_spammer',
        reportedUid: `user_target_${i}`,
        matchId: `match_${i}`,
        reason: 'other',
        reportedNickname: 'Hedef',
        answers: [],
      });
      expect(res.ok).toBe(true);
    }

    // 4. bildirim reddedilmeli
    const res4 = await store.addReport({
      reporterUid: 'user_spammer',
      reportedUid: 'user_target_4',
      matchId: 'match_4',
      reason: 'other',
      reportedNickname: 'Hedef',
      answers: [],
    });

    expect(res4.ok).toBe(false);
    if (!res4.ok) {
      expect(res4.error).toBe('daily_limit_exceeded');
    }
  });

  it('4. Özet raporu en çok bildirilen oyuncuları doğru gruplar', async () => {
    const ctx = createMockCtx();
    const store = new ReportStore(ctx, { MAX_REPORTS_PER_DAY: '50' } as unknown as Env);

    // user_bad 2 kez bildirilsin
    await store.addReport({
      reporterUid: 'u1',
      reportedUid: 'user_bad',
      matchId: 'm1',
      reason: 'cheating',
      reportedNickname: 'BadGuy',
      answers: [],
    });
    await store.addReport({
      reporterUid: 'u2',
      reportedUid: 'user_bad',
      matchId: 'm2',
      reason: 'cheating',
      reportedNickname: 'BadGuy',
      answers: [],
    });

    // user_mild 1 kez bildirilsin
    await store.addReport({
      reporterUid: 'u3',
      reportedUid: 'user_mild',
      matchId: 'm3',
      reason: 'other',
      reportedNickname: 'MildGuy',
      answers: [],
    });

    const summary = await store.getSummary();
    expect(summary.length).toBe(2);
    expect(summary[0].reportedUid).toBe('user_bad');
    expect(summary[0].reportCount).toBe(2);
    expect(summary[1].reportedUid).toBe('user_mild');
    expect(summary[1].reportCount).toBe(1);
  });
});

