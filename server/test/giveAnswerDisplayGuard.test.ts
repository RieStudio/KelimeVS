import { describe, expect, it } from 'vitest';
import { parseQuestionsPool } from '../src/engine/models';
import { AnswerMatcher } from '../src/engine/matcher';
import { AttemptTextSanitizer } from '../src/engine/sanitizer';
import rawQuestions from '../src/dev/questions.json';

describe('Koruma Testi: TÜM sorular için answer.display eşleşme kontrolü', () => {
  it('her answer.display metni cevap eşleştiriciden geçince KENDİ answer.id değerine eşleşmelidir', () => {
    const questions = parseQuestionsPool(rawQuestions);
    expect(questions.length).toBeGreaterThan(0);

    const mismatches: Array<{
      questionId: string;
      questionText: string;
      display: string;
      expectedAnswerId: string;
      actualResult: unknown;
    }> = [];

    let totalChecked = 0;

    for (const q of questions) {
      const matcher = new AnswerMatcher(q);
      for (const ans of q.answers) {
        totalChecked++;
        const sanitized = AttemptTextSanitizer.sanitize(ans.display);
        const res = matcher.check(sanitized, new Set());
        if (res.type !== 'correct' || res.answer.id !== ans.id) {
          mismatches.push({
            questionId: q.id,
            questionText: q.text,
            display: ans.display,
            expectedAnswerId: ans.id,
            actualResult: res,
          });
        }
      }
    }

    console.log(`[Display Guard] Toplam kontrol edilen cevap: ${totalChecked}`);
    if (mismatches.length > 0) {
      console.warn(`[Display Guard] Eşleşmeyen cevap sayısı: ${mismatches.length}`);
      console.warn('Örnek eşleşmeyenler:', JSON.stringify(mismatches.slice(0, 10), null, 2));
    }

    // Kullanıcı kuralı: "Eşleşmeyenler varsa testi geçirmeye çalışma, listesini raporda ver"
    expect(mismatches).toEqual([]);
  });
});
