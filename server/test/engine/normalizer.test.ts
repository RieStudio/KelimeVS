import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { normalize } from '../../src/engine';

interface NormalizerVector {
  readonly version: number;
  readonly totalCases: number;
  readonly cases: readonly {
    readonly id: string;
    readonly input: string;
    readonly expected: string;
  }[];
}

function loadVector(): NormalizerVector {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/normalizer.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/normalizer.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/normalizer.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as NormalizerVector;
    }
  }
  throw new Error('normalizer.json bulunamadı');
}

describe('TextNormalizer (shared test vectors)', () => {
  const vector = loadVector();

  it('versiyon 1 olmalı ve en az 60 durum içermeli', () => {
    expect(vector.version).toBe(1);
    expect(vector.cases.length).toBeGreaterThanOrEqual(60);
  });

  for (const tc of vector.cases) {
    it(`[${tc.id}] normalize("${tc.input}") === "${tc.expected}"`, () => {
      const actual = normalize(tc.input);
      expect(actual).toBe(tc.expected);
    });
  }
});

