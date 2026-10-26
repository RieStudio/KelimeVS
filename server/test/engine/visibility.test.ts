import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { visibleAttempts, type AttemptResultType, type RoundRecord, type TurnAttempt } from '../../src/engine';

interface VisibilityVectorCase {
  readonly id: string;
  readonly description: string;
  readonly attempts: readonly {
    readonly playerId: string;
    readonly rawInput: string;
    readonly resultType: AttemptResultType;
    readonly answerId?: string;
    readonly nowMs: number;
    readonly isClose: boolean;
    readonly hintShown: boolean;
  }[];
  readonly viewerId: string;
  readonly roundActive: boolean;
  readonly expectedVisibleIndices: readonly number[];
}

interface VisibilityVector {
  readonly version: number;
  readonly totalCases: number;
  readonly cases: readonly VisibilityVectorCase[];
}

function loadVector(): VisibilityVector {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/visibility.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/visibility.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/visibility.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as VisibilityVector;
    }
  }
  throw new Error('visibility.json bulunamadı');
}

describe('visibleAttempts (shared test vectors)', () => {
  const vector = loadVector();

  it('versiyon 1 olmalı ve en az 20 durum içermeli', () => {
    expect(vector.version).toBe(1);
    expect(vector.cases.length).toBeGreaterThanOrEqual(20);
  });

  for (const tc of vector.cases) {
    it(`[${tc.id}] ${tc.description}`, () => {
      const attempts: TurnAttempt[] = tc.attempts.map((a) => ({
        playerId: a.playerId,
        rawInput: a.rawInput,
        resultType: a.resultType,
        answerId: a.answerId,
        nowMs: a.nowMs,
        isClose: a.isClose,
        hintShown: a.hintShown,
      }));

      const record: RoundRecord = {
        questionId: 'q_test',
        starterPlayerId: 'p1',
        attempts,
        winnerId: null,
        reason: 'timeout',
      };

      const visible = visibleAttempts(record, tc.viewerId, tc.roundActive);
      const actualIndices: number[] = [];
      for (let i = 0; i < attempts.length; i++) {
        if (visible.includes(attempts[i])) {
          actualIndices.push(i);
        }
      }

      expect(actualIndices).toEqual(tc.expectedVisibleIndices);
    });
  }
});

describe('visibleAttempts - repeated and wrong attempt visibility rules', () => {
  const repeatedAttempt: TurnAttempt = {
    playerId: 'p1',
    rawInput: 'ankara',
    resultType: 'repeated',
    answerId: 'ans_ankara',
    nowMs: 1000,
    isClose: false,
    hintShown: false,
  };

  const wrongAttempt: TurnAttempt = {
    playerId: 'p1',
    rawInput: 'yanliscevap',
    resultType: 'wrong',
    nowMs: 1200,
    isClose: false,
    hintShown: false,
  };

  const correctAttempt: TurnAttempt = {
    playerId: 'p2',
    rawInput: 'izmir',
    resultType: 'correct',
    answerId: 'ans_izmir',
    nowMs: 2000,
    isClose: false,
    hintShown: false,
  };

  const round: RoundRecord = {
    questionId: 'q_cities',
    starterPlayerId: 'p1',
    attempts: [repeatedAttempt, wrongAttempt, correctAttempt],
    winnerId: null,
    reason: 'timeout',
  };

  it('aktif turda repeated denemeler yazan oyuncuya da rakibe de gizlidir', () => {
    const visibleForAuthor = visibleAttempts(round, 'p1', true);
    const visibleForOpponent = visibleAttempts(round, 'p2', true);

    expect(visibleForAuthor.some((a) => a.resultType === 'repeated')).toBe(false);
    expect(visibleForOpponent.some((a) => a.resultType === 'repeated')).toBe(false);
  });

  it('aktif turda wrong (yanlış) denemeler kırmızı balon olarak iki oyuncuya da görünür kalır', () => {
    const visibleForAuthor = visibleAttempts(round, 'p1', true);
    const visibleForOpponent = visibleAttempts(round, 'p2', true);

    expect(visibleForAuthor.some((a) => a.resultType === 'wrong')).toBe(true);
    expect(visibleForOpponent.some((a) => a.resultType === 'wrong')).toBe(true);
  });

  it('aktif turda correct denemeler iki oyuncuya da görünür', () => {
    const visibleForAuthor = visibleAttempts(round, 'p1', true);
    const visibleForOpponent = visibleAttempts(round, 'p2', true);

    expect(visibleForAuthor.some((a) => a.resultType === 'correct')).toBe(true);
    expect(visibleForOpponent.some((a) => a.resultType === 'correct')).toBe(true);
  });

  it('tur bittiğinde (roundActive: false) ham kayıttaki repeated dahil tüm denemeler görünür', () => {
    const visibleEndedForAuthor = visibleAttempts(round, 'p1', false);
    const visibleEndedForOpponent = visibleAttempts(round, 'p2', false);

    expect(visibleEndedForAuthor).toHaveLength(3);
    expect(visibleEndedForOpponent).toHaveLength(3);
    expect(visibleEndedForAuthor.some((a) => a.resultType === 'repeated')).toBe(true);
    expect(visibleEndedForOpponent.some((a) => a.resultType === 'repeated')).toBe(true);
  });

  it('visibleAttempts ham round.attempts listesini mutasyona uğratmaz', () => {
    const originalLength = round.attempts.length;
    visibleAttempts(round, 'p1', true);
    expect(round.attempts.length).toBe(originalLength);
    expect(round.attempts[0].resultType).toBe('repeated');
  });
});

