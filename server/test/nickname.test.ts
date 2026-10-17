import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { validateNickname } from '../src/engine/nicknameValidator';
import { PROFANITY_WORDS } from '../src/engine/profanityWords';
import { sanitizePlayerName } from '../src/protocol';

interface NicknameTestCase {
  readonly input: string;
  readonly valid: boolean;
  readonly normalized: string | null;
}

function loadNicknameVectors(): readonly NicknameTestCase[] {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/nickname.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/nickname.json'),
    path.resolve(__dirname, '../../shared/test-vectors/nickname.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as readonly NicknameTestCase[];
    }
  }
  throw new Error('shared/test-vectors/nickname.json bulunamadı');
}

function loadProfanityWords(): readonly string[] {
  const candidates = [
    path.resolve(process.cwd(), '../shared/profanity_words.json'),
    path.resolve(process.cwd(), 'shared/profanity_words.json'),
    path.resolve(__dirname, '../../shared/profanity_words.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as readonly string[];
    }
  }
  throw new Error('shared/profanity_words.json bulunamadı');
}

describe('NicknameValidator and sanitizePlayerName (shared test vectors)', () => {
  const vectors = loadNicknameVectors();
  const profanityList = loadProfanityWords();

  it('shared/profanity_words.json sunucudaki PROFANITY_WORDS ile birebir eşleşmeli', () => {
    expect([...PROFANITY_WORDS]).toEqual([...profanityList]);
  });

  it('en az 25 test vektörü içermeli', () => {
    expect(vectors.length).toBeGreaterThanOrEqual(25);
  });

  for (let i = 0; i < vectors.length; i++) {
    const tc = vectors[i];
    it(`Case #${i + 1}: "${tc.input}" -> valid=${tc.valid}, normalized=${JSON.stringify(tc.normalized)}`, () => {
      const res = validateNickname(tc.input);
      expect(res.isValid).toBe(tc.valid);
      expect(res.normalized).toBe(tc.normalized);

      const sanitized = sanitizePlayerName(tc.input);
      if (tc.valid) {
        expect(sanitized).toBe(tc.normalized);
      } else {
        expect(sanitized).toBe('Oyuncu');
      }
    });
  }
});

