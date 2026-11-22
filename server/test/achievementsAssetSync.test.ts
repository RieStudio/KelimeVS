import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { ACHIEVEMENT_DEFINITIONS } from '../src/achievements/definitions';

describe('Achievements Asset Synchronization (Single Source of Truth)', () => {
  it('app/assets/achievements/achievements.json sunucu tanımlarıyla birebir eşit olmalıdır', () => {
    const assetPath = path.resolve(
      __dirname,
      '../../app/assets/achievements/achievements.json'
    );

    expect(
      fs.existsSync(assetPath),
      'app/assets/achievements/achievements.json dosyası mevcut değil! Lütfen server/ dizininde "npm run export:achievements" çalıştırın.'
    ).toBe(true);

    const assetContent = JSON.parse(fs.readFileSync(assetPath, 'utf8'));
    const expected = [...ACHIEVEMENT_DEFINITIONS].sort((a, b) => a.order - b.order);

    const errorMessage =
      'Sunucu başarım tanımları (server/src/achievements/definitions.ts) ile uygulama JSON varlığı (app/assets/achievements/achievements.json) uyumsuz!\n' +
      'Dosyayı eşitlemek için lütfen şu komutu çalıştırın:\n' +
      '  cd server && npm run export:achievements';

    expect(assetContent, errorMessage).toEqual(expected);
  });
});
