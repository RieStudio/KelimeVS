import type { Question } from '../engine';

export interface ContentProvider {
  /** Maçlarda kullanılacak soruları döndürür. */
  getQuestions(): Promise<Question[]>;
}

