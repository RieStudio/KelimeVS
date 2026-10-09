// Saf JavaScript / TypeScript - Harici bağımlılık yoktur.

import { normalize } from './normalizer';

export interface Answer {
  /** Ana cevabın normalleştirilmiş hâli (kararlı, dahili kimlik) */
  readonly id: string;
  /** Ana cevap metni olduğu gibi */
  readonly display: string;
  /** Normalleştirilmiş alias listesi (ana cevap da dahil) */
  readonly aliases: readonly string[];
}

export interface Question {
  readonly id: string;
  readonly categoryId: string;
  readonly text: string;
  readonly answers: readonly Answer[];
}

/**
 * CMS havuz JSON verisini ayrıştırır.
 * Üst düzeyde "questions_pool" varsa onu, yoksa verinin kendisini havuz kabul eder.
 * "app", "version", "cms_categories" gibi harici alanları yok sayar.
 */
export function parseQuestionsPool(json: unknown): Question[] {
  if (typeof json !== 'object' || json === null) {
    return [];
  }

  const record = json as Record<string, unknown>;
  const pool =
    'questions_pool' in record &&
    typeof record.questions_pool === 'object' &&
    record.questions_pool !== null
      ? (record.questions_pool as Record<string, unknown>)
      : record;

  const questions: Question[] = [];

  for (const [categoryId, categoryData] of Object.entries(pool)) {
    if (typeof categoryData !== 'object' || categoryData === null) continue;

    for (const [questionId, questionData] of Object.entries(
      categoryData as Record<string, unknown>
    )) {
      if (typeof questionData !== 'object' || questionData === null) continue;

      const qObj = questionData as Record<string, unknown>;
      const rawQuestion = qObj.question;
      if (rawQuestion === undefined || rawQuestion === null) continue;

      // Baştaki/sondaki ve ardışık boşlukları temizle
      const cleanText = String(rawQuestion).replace(/\s+/g, ' ').trim();

      const rawAnswers = qObj.acceptable_answers;
      const answers: Answer[] = [];

      if (typeof rawAnswers === 'object' && rawAnswers !== null) {
        for (const [mainAnswerKey, rawAliases] of Object.entries(
          rawAnswers as Record<string, unknown>
        )) {
          const display = String(mainAnswerKey);
          const id = normalize(display);

          const normalizedAliases: string[] = [];

          // Ana cevap da alias indeksine dahil
          if (id.length > 0) {
            normalizedAliases.push(id);
          }

          if (Array.isArray(rawAliases)) {
            for (const aliasItem of rawAliases) {
              const norm = normalize(String(aliasItem));
              if (norm.length > 0 && !normalizedAliases.includes(norm)) {
                normalizedAliases.push(norm);
              }
            }
          }

          answers.push({
            id,
            display,
            aliases: normalizedAliases,
          });
        }
      }

      questions.push({
        id: questionId,
        categoryId,
        text: cleanText,
        answers,
      });
    }
  }

  return questions;
}

