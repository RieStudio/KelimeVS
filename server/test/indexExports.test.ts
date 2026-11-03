import { describe, expect, it, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

import * as workerEntry from '../src/index';

describe('Worker Entry (src/index.ts) Exports Guard', () => {
  const expectedDoClasses = [
    'MatchRoom',
    'Matchmaker',
    'UserProfile',
    'Leaderboard',
    'ReportStore',
  ];

  it('yalnızca default handler ve tanımlı Durable Object sınıflarını dışa aktarmalıdır', () => {
    const exportedKeys = Object.keys(workerEntry);
    const expectedKeys = ['default', ...expectedDoClasses];

    expect(exportedKeys.sort()).toEqual(expectedKeys.sort());
  });

  it('default export bir ExportedHandler (fetch fonksiyonuna sahip) olmalıdır', () => {
    expect(typeof workerEntry.default).toBe('object');
    expect(workerEntry.default).not.toBeNull();
    expect(typeof workerEntry.default.fetch).toBe('function');
  });

  it('tüm named exportlar Durable Object sınıfı (fonksiyon/yapıcı) olmalıdır', () => {
    for (const className of expectedDoClasses) {
      const exportedVal = (workerEntry as Record<string, unknown>)[className];
      expect(typeof exportedVal).toBe('function');
    }
  });

  it('sayısal sabitler, yardımcı fonksiyonlar veya yapılandırma değerleri dışa aktarılmamalıdır', () => {
    const exportedKeys = Object.keys(workerEntry);
    const forbiddenExports = [
      'GUEST_NICKNAME_LOCK_MIN_BUILD',
      'getGuestNicknameLockMinBuild',
      'LEADERBOARD_TOP_LIMIT',
      'DEFAULT_VISUAL_FRAMES_MIN_BUILD',
      'parseClientBuild',
    ];

    for (const forbidden of forbiddenExports) {
      expect(exportedKeys).not.toContain(forbidden);
    }

    for (const key of exportedKeys) {
      if (key === 'default') continue;
      const val = (workerEntry as Record<string, unknown>)[key];
      expect(typeof val).toBe('function');
      expect(typeof val).not.toBe('number');
      expect(typeof val).not.toBe('string');
      expect(typeof val).not.toBe('boolean');
    }
  });

  it('wrangler.jsonc dosyasındaki Durable Object sınıfları ile tam uyumlu olmalıdır', () => {
    const wranglerJsonPath = path.resolve(__dirname, '../wrangler.jsonc');
    const content = fs.readFileSync(wranglerJsonPath, 'utf-8');
    const classRegex = /"class_name":\s*"([^"]+)"/g;
    const configuredClasses: string[] = [];
    let match: RegExpExecArray | null;
    while ((match = classRegex.exec(content)) !== null) {
      if (!configuredClasses.includes(match[1])) {
        configuredClasses.push(match[1]);
      }
    }

    const nonDefaultExports = Object.keys(workerEntry).filter((k) => k !== 'default');
    expect(nonDefaultExports.sort()).toEqual(configuredClasses.sort());
  });
});
