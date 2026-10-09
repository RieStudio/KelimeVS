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

