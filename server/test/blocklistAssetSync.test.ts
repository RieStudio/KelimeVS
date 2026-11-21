import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  ALLOW_WORDS,
  EXACT_WORDS,
  CONTAINS_WORDS,
} from '../src/engine/nicknameBlocklist';
import { parseWordList } from '../src/engine/nicknameFilter';

describe('Blocklist Asset Synchronization (Single Source of Truth)', () => {
  it('app/assets/text_filter/blocklist.json sunucu liste dosyalarıyla birebir eşit olmalıdır', () => {
    const assetPath = path.resolve(
      __dirname,
      '../../app/assets/text_filter/blocklist.json'
    );

    expect(
      fs.existsSync(assetPath),
      'app/assets/text_filter/blocklist.json dosyası mevcut değil! Lütfen server/ dizininde "npm run export:blocklist" çalıştırın.'
    ).toBe(true);

    const assetContent = JSON.parse(fs.readFileSync(assetPath, 'utf8'));

    const expectedAllow = parseWordList(ALLOW_WORDS);
    const expectedExact = parseWordList(EXACT_WORDS);
    const expectedContains = parseWordList(CONTAINS_WORDS);

    const errorMessage =
      'Sunucu blok listesi (server/src/engine/nicknameBlocklist/) ile uygulama JSON varlığı (app/assets/text_filter/blocklist.json) uyumsuz!\n' +
      'Listeleri eşitlemek için lütfen şu komutu çalıştırın:\n' +
      '  cd server && npm run export:blocklist';

    expect(assetContent.allow, errorMessage).toEqual(expectedAllow);
    expect(assetContent.exact, errorMessage).toEqual(expectedExact);
    expect(assetContent.contains, errorMessage).toEqual(expectedContains);
  });
});
