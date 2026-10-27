import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { AttemptTextSanitizer } from '../../src/engine';

interface SanitizerTestCase {
  readonly id: string;
  readonly description?: string;
  readonly input: string;
  readonly expected: string;
}

interface SanitizerFile {
  readonly cases: readonly SanitizerTestCase[];
}

function loadSanitizerVectors(): readonly SanitizerTestCase[] {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/sanitizer.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/sanitizer.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/sanitizer.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      const parsed = JSON.parse(fs.readFileSync(p, 'utf-8')) as SanitizerFile;
      return parsed.cases;
    }
  }
  throw new Error('shared/test-vectors/sanitizer.json bulunamadı');
}

describe('AttemptTextSanitizer (shared/test-vectors/sanitizer.json)', () => {
  const cases = loadSanitizerVectors();

  it('shared test vektörlerinin tamamını yükler', () => {
    expect(cases.length).toBeGreaterThanOrEqual(15);
  });

  for (const tc of cases) {
    it(`[${tc.id}] ${tc.description ?? tc.input}`, () => {
      const actual = AttemptTextSanitizer.sanitize(tc.input);
      expect(actual).toBe(tc.expected);
    });
  }
});

