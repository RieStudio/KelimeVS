import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { distance, maxAllowedDistance } from '../../src/engine';

interface NearMissVector {
  readonly version: number;
  readonly totalCases: number;
  readonly cases: readonly {
    readonly id: string;
    readonly description: string;
    readonly word1: string;
    readonly word2: string;
    readonly targetLength: number;
    readonly maxAllowedDistance: number;
    readonly distance: number;
    readonly isClose: boolean;
  }[];
}

function loadVector(): NearMissVector {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/near_miss.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/near_miss.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/near_miss.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as NearMissVector;
    }
  }
  throw new Error('near_miss.json bulunamadı');
}

describe('NearMissCalculator (shared test vectors)', () => {
  const vector = loadVector();

  it('versiyon 1 olmalı ve en az 30 durum içermeli', () => {
    expect(vector.version).toBe(1);
    expect(vector.cases.length).toBeGreaterThanOrEqual(30);
  });

  for (const tc of vector.cases) {
    it(`[${tc.id}] ${tc.description} ("${tc.word1}" vs "${tc.word2}")`, () => {
      const actualMaxDist = maxAllowedDistance(tc.targetLength);
      expect(actualMaxDist).toBe(tc.maxAllowedDistance);

      const actualDist = distance(tc.word1, tc.word2);
      expect(actualDist).toBe(tc.distance);

      const actualIsClose = actualDist > 0 && actualDist <= actualMaxDist;
      expect(actualIsClose).toBe(tc.isClose);
    });
  }
});

