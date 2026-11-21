import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ALLOW_WORDS,
  EXACT_WORDS,
  CONTAINS_WORDS,
} from '../src/engine/nicknameBlocklist/index.js';
import { parseWordList } from '../src/engine/nicknameFilter.js';
import { maskInappropriateText } from '../src/engine/textMasker.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDir = path.resolve(__dirname, '../..');
const appAssetsDir = path.resolve(rootDir, 'app/assets/text_filter');
const sharedVectorsDir = path.resolve(rootDir, 'shared/test-vectors');

// 1. Export blocklist JSON for Flutter client
if (!fs.existsSync(appAssetsDir)) {
  fs.mkdirSync(appAssetsDir, { recursive: true });
}

const blocklistPayload = {
  version: 1,
  generatedAt: '2026-11-21T00:00:00.000Z',
  description:
    'KelimeVS profanity & inappropriate content blocklists for client-side TextFilter (single source of truth: server/src/engine/nicknameBlocklist/)',
  allow: parseWordList(ALLOW_WORDS),
  exact: parseWordList(EXACT_WORDS),
  contains: parseWordList(CONTAINS_WORDS),
};

const blocklistPath = path.join(appAssetsDir, 'blocklist.json');
fs.writeFileSync(blocklistPath, JSON.stringify(blocklistPayload, null, 2) + '\n', 'utf8');
console.log(`✓ blocklist.json exported to: ${blocklistPath}`);
console.log(`  - contains: ${blocklistPayload.contains.length} words`);
console.log(`  - exact: ${blocklistPayload.exact.length} words`);
console.log(`  - allow: ${blocklistPayload.allow.length} words`);

// 2. Export shared test vectors for textMasker parity
const testInputs = [
  // Tek sözcükler
  'orospu',
  'Orospu',
  'OROSPU',
  'sik',
  'SiK',
  'bok',
  'pic',
  'piç',
  'got',
  'göt',
  'mal',
  'aptal',
  'serefsiz',
  'Şerefsiz',
  'şerefsiz',
  'İbne',
  'ıbne',
  'amcik',
  'yarrak',

  // Rakam ve noktalama ekli
  'orospu123',
  'sik99',
  'pic123',
  'orospu!',
  '!orospu',
  'orospu,',

  // Cümle içi ve masum sözcükler
  'sen bir orospusun',
  'ben, orospu değilim.',
  'tamam ben geliyorum',
  'bu cok guzel bir oyun',
  'Merhaba! Nasılsın?',
  'Elma, armut, muz.',
  'sen s i k misin',
  'b o k yeme',

  // Aralıklı tek harfler
  's i k',
  's  i  k',
  'o r o s p u',
  'o.r.o.s.p.u',
  'o_r_o_s_p_u',
  's_i_k',
  'p.i.c',

  // Masum tek harfler / bağlaçlar
  'o ve a',
  'a b c d e',

  // Leetspeak ve semboller
  '0r0spu',
  '51k15',
  '5!k!5',
  's!k',
  'p1c',
  'p!c',

  // Sayısal muafiyetler (trivia cevapları)
  '31',
  '13',
  '1993',
  '3.1',
  '3 1',
  'Apollo 13',
  'Windows 3 1',
  '1923',
  '10/10',
  '1923-1938',

  // Exact köklerin masum kelime içinde geçmesi (muaf olmalı)
  'damla',
  'kamil',
  'amiral',
  'tamam',
  'fizik',
  'müzik',
  'boks',
  'boksör',

  // Allow listesi
  'kemal',
  'siklamen',
  'kasik',
  'fistik',
  'lastik',
  'finnigan',

  // Tam genişlikli (Fullwidth) ve Aksanlı girdiler
  'ｏｒｏｓｐｕ',
  'ｓｉｋ',
  'bök',
  'kâğıt',

  // Boş ve özel durumlar
  '',
  '   ',
  'a',
  '1',
];

const vectorCases = testInputs.map((input) => ({
  input,
  expected: maskInappropriateText(input),
}));

const vectorsPayload = {
  version: 1,
  description:
    'Test vectors for KelimeVS in-game text masker parity between TypeScript server and Dart client',
  totalCases: vectorCases.length,
  cases: vectorCases,
};

const vectorsPath = path.join(sharedVectorsDir, 'text_masker.json');
fs.writeFileSync(vectorsPath, JSON.stringify(vectorsPayload, null, 2) + '\n', 'utf8');
console.log(`✓ text_masker.json exported to: ${vectorsPath} (${vectorCases.length} cases)`);
