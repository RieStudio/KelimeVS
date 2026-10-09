// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

import type { Answer, Question } from './models';
import { normalize } from './normalizer';

export type MatchResult =
  | { readonly type: 'correct'; readonly answer: Answer }
  | { readonly type: 'repeated'; readonly answer: Answer }
  | { readonly type: 'wrong' }
  | { readonly type: 'empty' };

export class AnswerMatcher {
  readonly question: Question;
  private readonly aliasIndex: Map<string, Answer> = new Map();

  constructor(question: Question) {
    this.question = question;
    for (const answer of question.answers) {
      // Ana cevap
      if (answer.id.length > 0 && !this.aliasIndex.has(answer.id)) {
        this.aliasIndex.set(answer.id, answer);
      }
      // Alias listesi
      for (const alias of answer.aliases) {
        if (alias.length > 0 && !this.aliasIndex.has(alias)) {
          this.aliasIndex.set(alias, answer);
        }
      }
    }
  }

  /**
   * Girdiyi kontrol eder.
   * Boş girdi -> empty
   * Bulunamazsa -> wrong
   * usedAnswerIds içinde varsa -> repeated
   * İlk kez söyleniyorsa -> correct
   */
  check(input: string, usedAnswerIds: ReadonlySet<string>): MatchResult {
    const normalized = normalize(input);
    if (normalized.length === 0) {
      return { type: 'empty' };
    }

    const answer = this.aliasIndex.get(normalized);
    if (!answer) {
      return { type: 'wrong' };
    }

    if (usedAnswerIds.has(answer.id)) {
      return { type: 'repeated', answer };
    }

    return { type: 'correct', answer };
  }

  /** Henüz söylenmemiş cevap sayısı */
  remaining(usedAnswerIds: ReadonlySet<string>): number {
    let count = 0;
    for (const answer of this.question.answers) {
      if (!usedAnswerIds.has(answer.id)) {
        count++;
      }
    }
    return count;
  }

  /** Tüm cevaplar tükendi mi? */
  isExhausted(usedAnswerIds: ReadonlySet<string>): boolean {
    return this.remaining(usedAnswerIds) === 0;
  }
}

