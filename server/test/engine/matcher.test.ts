import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { AnswerMatcher, isNearMiss, normalize, type Question } from '../../src/engine';

interface MatcherVectorCase {
  readonly id: string;
  readonly description: string;
  readonly question: {
    readonly id: string;
    readonly categoryId: string;
    readonly title: string;
    readonly answers: readonly {
      readonly id: string;
      readonly display: string;
      readonly aliases: readonly string[];
    }[];
  };
  readonly input: string;
  readonly usedAnswerIds: readonly string[];
  readonly expectedResult: 'correct' | 'repeated' | 'wrong' | 'empty';
  readonly expectedAnswerId: string | null;
  readonly expectedIsClose: boolean;
}

interface MatcherVector {
  readonly version: number;
  readonly totalCases: number;
  readonly cases: readonly MatcherVectorCase[];
}

function loadVector(): MatcherVector {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/matcher.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/matcher.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/matcher.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as MatcherVector;
    }
  }
  throw new Error('matcher.json bulunamadı');
}

describe('AnswerMatcher (shared test vectors)', () => {
  const vector = loadVector();

  it('versiyon 1 olmalı ve en az 30 durum içermeli', () => {
    expect(vector.version).toBe(1);
    expect(vector.cases.length).toBeGreaterThanOrEqual(30);
  });

  for (const tc of vector.cases) {
    it(`[${tc.id}] ${tc.description} ("${tc.input}")`, () => {
      const question: Question = {
        id: tc.question.id,
        categoryId: tc.question.categoryId,
        text: tc.question.title,
        answers: tc.question.answers,
      };

      const usedSet = new Set(tc.usedAnswerIds);
      const matcher = new AnswerMatcher(question);
      const matchResult = matcher.check(tc.input, usedSet);

      expect(matchResult.type).toBe(tc.expectedResult);

      const actualAnswerId =
        matchResult.type === 'correct' || matchResult.type === 'repeated'
          ? matchResult.answer.id
          : null;
      expect(actualAnswerId).toBe(tc.expectedAnswerId);

      if (matchResult.type === 'wrong') {
        const normalized = normalize(tc.input);
        const unusedAliases = question.answers
          .filter((a) => !usedSet.has(a.id))
          .map((a) => a.aliases);
        const actualIsClose = isNearMiss(normalized, unusedAliases);
        expect(actualIsClose).toBe(tc.expectedIsClose);
      }
    });
  }
});

