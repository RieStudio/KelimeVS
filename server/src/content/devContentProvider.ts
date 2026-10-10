// TODO (4.4): Realtime Database ContentProvider ile değiştirilecek
import type { ContentProvider } from './contentProvider';
import { parseQuestionsPool, type Question } from '../engine';
import rawQuestions from '../dev/questions.json';

export class DevContentProvider implements ContentProvider {
  private cachedQuestions: Question[] | null = null;

  async getQuestions(): Promise<Question[]> {
    if (this.cachedQuestions === null) {
      this.cachedQuestions = parseQuestionsPool(rawQuestions);
    }
    return this.cachedQuestions;
  }
}

