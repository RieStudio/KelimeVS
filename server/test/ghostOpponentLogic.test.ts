import { describe, expect, it } from 'vitest';
import type { Question } from '../src/engine/models';
import {
  findQuestionByState,
  findUnusedAnswers,
  getRandomDelayMs,
  parseApiKeyFromDevVars,
  parseFirebaseErrorMessage,
  parseGhostArgs,
  parseSessionCache,
  selectAnswer,
  serializeSessionCache,
  shouldMakeMistake,
  toWebSocketUrl,
} from '../tools/ghost-opponent-logic';

describe('ghost-opponent-logic', () => {
  describe('toWebSocketUrl', () => {
    it('http ve https adreslerini ws ve wss yapar', () => {
      expect(toWebSocketUrl('https://api.riestudio.com.tr')).toBe('wss://api.riestudio.com.tr');
      expect(toWebSocketUrl('https://api.riestudio.com.tr/')).toBe('wss://api.riestudio.com.tr');
      expect(toWebSocketUrl('http://localhost:8787')).toBe('ws://localhost:8787');
      expect(toWebSocketUrl('wss://custom.domain')).toBe('wss://custom.domain');
    });
  });

  describe('parseGhostArgs', () => {
    it('varsayılan argümanları doğru ayrıştırır', () => {
      const cfg = parseGhostArgs([]);
      expect(cfg.mode).toBe('play');
      expect(cfg.serverUrl).toBe('wss://api.riestudio.com.tr');
      expect(cfg.rounds).toBe(1);
      expect(cfg.leaveAfterSeconds).toBe(15);
      expect(cfg.dropAfterSeconds).toBe(15);
      expect(cfg.backAfterSeconds).toBe(5);
      expect(cfg.apiKey).toBeUndefined();
      expect(cfg.fresh).toBe(false);
      expect(cfg.devAuth).toBe(false);
    });

    it('özel bayrakları ve ortam değişkenlerini ayrıştırır', () => {
      const cfg = parseGhostArgs(
        [
          '--mode=drop',
          '--url=http://127.0.0.1:8787',
          '--api-key=cli_key',
          '--rounds=3',
          '--drop-after=10',
          '--back-after=7',
          '--fresh',
          '--dev-auth',
        ],
        { FIREBASE_WEB_API_KEY: 'env_key' }
      );

      expect(cfg.mode).toBe('drop');
      expect(cfg.serverUrl).toBe('ws://127.0.0.1:8787');
      expect(cfg.apiKey).toBe('cli_key');
      expect(cfg.rounds).toBe(3);
      expect(cfg.dropAfterSeconds).toBe(10);
      expect(cfg.backAfterSeconds).toBe(7);
      expect(cfg.fresh).toBe(true);
      expect(cfg.devAuth).toBe(true);
    });

    it('CLI argümanı yoksa ortam değişkenindeki API anahtarını alır', () => {
      const cfg = parseGhostArgs([], { FIREBASE_WEB_API_KEY: 'env_key_only' });
      expect(cfg.apiKey).toBe('env_key_only');
    });
  });

  describe('parseFirebaseErrorMessage', () => {
    it('error.message alanını doğru çeker', () => {
      expect(
        parseFirebaseErrorMessage({
          error: { code: 400, message: 'TOO_MANY_ATTEMPTS_TRY_LATER' },
        })
      ).toBe('TOO_MANY_ATTEMPTS_TRY_LATER');

      expect(
        parseFirebaseErrorMessage({
          error: { code: 400, message: 'OPERATION_NOT_ALLOWED' },
        })
      ).toBe('OPERATION_NOT_ALLOWED');

      expect(
        parseFirebaseErrorMessage({
          error: { code: 400, message: 'API_KEY_INVALID' },
        })
      ).toBe('API_KEY_INVALID');
    });

    it('string formatındaki error alanını çeker', () => {
      expect(parseFirebaseErrorMessage({ error: 'invalid_grant' })).toBe('invalid_grant');
    });

    it('URL parametrelerini veya hassas key alanlarını maskeler', () => {
      const msg = parseFirebaseErrorMessage({
        error: { code: 400, message: 'Invalid URL with key=AIzaSySecret123&test=1' },
      });
      expect(msg).toContain('key=[REDACTED]');
      expect(msg).not.toContain('AIzaSySecret123');
    });

    it('geçersiz veya eksik hata gövdesinde undefined döner', () => {
      expect(parseFirebaseErrorMessage(null)).toBeUndefined();
      expect(parseFirebaseErrorMessage({})).toBeUndefined();
      expect(parseFirebaseErrorMessage({ error: {} })).toBeUndefined();
    });
  });

  describe('parseSessionCache ve serializeSessionCache', () => {
    it('geçerli refreshToken içeren JSON dosyasını ayrıştırır', () => {
      const raw = JSON.stringify({ refreshToken: 'dummy_refresh_token_123' });
      const parsed = parseSessionCache(raw);
      expect(parsed).toBeDefined();
      expect(parsed?.refreshToken).toBe('dummy_refresh_token_123');
    });

    it('bozuk veya geçersiz JSON durumunda undefined döner', () => {
      expect(parseSessionCache('not json')).toBeUndefined();
      expect(parseSessionCache(JSON.stringify({ other: 123 }))).toBeUndefined();
      expect(parseSessionCache(JSON.stringify({ refreshToken: '' }))).toBeUndefined();
    });

    it('serializeSessionCache doğru JSON dizesi üretir', () => {
      const serialized = serializeSessionCache('token_xyz');
      const parsed = JSON.parse(serialized);
      expect(parsed.refreshToken).toBe('token_xyz');
    });
  });

  describe('parseApiKeyFromDevVars', () => {
    it('.dev.vars içeriğinden FIREBASE_WEB_API_KEY değerini okur', () => {
      const content = `
# Yorum satırı
ALLOW_DEV_AUTH=true
FIREBASE_WEB_API_KEY="AIzaSyTestApiKey123"
OTHER=val
`;
      expect(parseApiKeyFromDevVars(content)).toBe('AIzaSyTestApiKey123');
    });

    it('anahtar yoksa undefined döner', () => {
      expect(parseApiKeyFromDevVars('ALLOW_DEV_AUTH=true\n')).toBeUndefined();
    });
  });

  describe('findQuestionByState ve selectAnswer', () => {
    const mockQuestions: Question[] = [
      {
        id: 'q_baskentler',
        categoryId: 'genel',
        text: "Türkiye'nin başkenti neresidir?",
        answers: [
          {
            id: 'ankara',
            display: 'Ankara',
            aliases: ['ankara', 'angara'],
          },
        ],
      },
      {
        id: 'q_renkler',
        categoryId: 'genel',
        text: 'Ana renkler nelerdir?',
        answers: [
          { id: 'kirmizi', display: 'Kırmızı', aliases: ['kirmizi', 'al'] },
          { id: 'mavi', display: 'Mavi', aliases: ['mavi'] },
          { id: 'sari', display: 'Sarı', aliases: ['sari'] },
        ],
      },
    ];

    it('soruyu id ve metin üzerinden bulur', () => {
      const q1 = findQuestionByState(mockQuestions, { id: 'q_baskentler', text: '' });
      expect(q1?.id).toBe('q_baskentler');

      const q2 = findQuestionByState(mockQuestions, { id: 'unknown', text: 'Ana renkler nelerdir?' });
      expect(q2?.id).toBe('q_renkler');

      const q3 = findQuestionByState(mockQuestions, null);
      expect(q3).toBeUndefined();
    });

    it('doğru söylenmiş cevapları eler ve kalan cevabı seçer', () => {
      const q = mockQuestions[1]; // kırmızı, mavi, sarı
      const attempts = [
        { text: 'kirmizi', result: 'correct' },
        { text: 'yesil', result: 'wrong' },
      ];

      const unused = findUnusedAnswers(q, attempts);
      expect(unused.map((a) => a.id)).toEqual(['mavi', 'sari']);

      const answer = selectAnswer(q, attempts);
      expect(answer).toBe('Mavi');
    });

    it('tüm cevaplar tükendiyse null döner', () => {
      const q = mockQuestions[1];
      const attempts = [
        { text: 'al', result: 'correct' }, // kırmızı alias'ı
        { text: 'mavi', result: 'correct' },
        { text: 'sari', result: 'correct' },
      ];

      expect(selectAnswer(q, attempts)).toBeNull();
    });
  });

  describe('shouldMakeMistake ve getRandomDelayMs', () => {
    it('0.20 altındayken yanlış deneme yapar', () => {
      expect(shouldMakeMistake(0.19)).toBe(true);
      expect(shouldMakeMistake(0.20)).toBe(false);
      expect(shouldMakeMistake(0.50)).toBe(false);
    });

    it('rastgele gecikmeyi 2000-6000 ms sınırlarında üretir', () => {
      expect(getRandomDelayMs(2000, 6000, 0)).toBe(2000);
      expect(getRandomDelayMs(2000, 6000, 1)).toBe(6000);
      expect(getRandomDelayMs(2000, 6000, 0.5)).toBe(4000);
    });
  });
});

