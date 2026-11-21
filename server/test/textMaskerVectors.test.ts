import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { maskInappropriateText } from '../src/engine/textMasker';

describe('TextMasker Shared Test Vectors Parity (Server Side)', () => {
  it('shared/test-vectors/text_masker.json vektörlerinin tamamı sunucu maskeleyicisiyle eşleşir', () => {
    const vectorPath = path.resolve(
      __dirname,
      '../../shared/test-vectors/text_masker.json'
    );

    expect(
      fs.existsSync(vectorPath),
      'shared/test-vectors/text_masker.json bulunamadı! Lütfen server/ dizininde "npm run export:blocklist" çalıştırın.'
    ).toBe(true);

    const vectorData = JSON.parse(fs.readFileSync(vectorPath, 'utf8'));
    expect(vectorData.cases.length).toBeGreaterThan(50);

    for (const testCase of vectorData.cases) {
      const actual = maskInappropriateText(testCase.input);
      expect(
        actual,
        `Vektör uyumsuzluğu! Girdi: "${testCase.input}". Vektörleri güncellemek için "cd server && npm run export:blocklist" çalıştırın.`
      ).toBe(testCase.expected);
    }
  });
});
