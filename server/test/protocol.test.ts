import { describe, expect, it } from 'vitest';
import { parseMatchmakerMessage, parseMatchRoomMessage, sanitizePlayerName } from '../src/protocol';

describe('Protocol Parsers and Validators', () => {
  describe('sanitizePlayerName', () => {
    it('boş veya geçersiz isimde varsayılan "Oyuncu" döner', () => {
      expect(sanitizePlayerName('')).toBe('Oyuncu');
      expect(sanitizePlayerName('   ')).toBe('Oyuncu');
      expect(sanitizePlayerName(null)).toBe('Oyuncu');
      expect(sanitizePlayerName(123)).toBe('Oyuncu');
    });

    it('boşlukları temizler ve ardışık boşlukları teke indirir', () => {
      expect(sanitizePlayerName('  Alice   Smith  ')).toBe('Alice Smith');
    });

    it('16 karakterden uzun veya geçersiz isimde "Oyuncu" döner', () => {
      const longName = 'ÇokUzunBirOyuncuİsmiDenemesi';
      expect(sanitizePlayerName(longName)).toBe('Oyuncu');
    });
  });

  describe('parseMatchmakerMessage', () => {
    it('geçerli queue mesajını ayrıştırır', () => {
      const res = parseMatchmakerMessage(JSON.stringify({ t: 'queue', name: 'Alice' }));
      expect(res).toEqual({ t: 'queue', name: 'Alice' });
    });

    it('name belirtilmemişse varsayılan Oyuncu atar', () => {
      const res = parseMatchmakerMessage(JSON.stringify({ t: 'queue' }));
      expect(res).toEqual({ t: 'queue', name: 'Oyuncu' });
    });

    it('geçerli cancel mesajını ayrıştırır', () => {
      const res = parseMatchmakerMessage(JSON.stringify({ t: 'cancel' }));
      expect(res).toEqual({ t: 'cancel' });
    });

    it('bozuk veya bilinmeyen mesajlarda null döner', () => {
      expect(parseMatchmakerMessage('not a json')).toBeNull();
      expect(parseMatchmakerMessage(JSON.stringify({ t: 'unknown' }))).toBeNull();
      expect(parseMatchmakerMessage(JSON.stringify({}))).toBeNull();
      expect(parseMatchmakerMessage(123)).toBeNull();
    });

    it('500 karakterden uzun mesajları reddeder', () => {
      const huge = JSON.stringify({ t: 'queue', name: 'a'.repeat(600) });
      expect(parseMatchmakerMessage(huge)).toBeNull();
    });
  });

  describe('parseMatchRoomMessage', () => {
    it('geçerli submit mesajını ayrıştırır ve sanitize eder', () => {
      const res = parseMatchRoomMessage(JSON.stringify({ t: 'submit', text: '  kırmızı   elma  ' }));
      expect(res).toEqual({ t: 'submit', text: 'kırmızı elma' });
    });

    it('submit metnini en fazla 40 karaktere kırpar', () => {
      const longText = 'a'.repeat(50);
      const res = parseMatchRoomMessage(JSON.stringify({ t: 'submit', text: longText }));
      expect(res).toEqual({ t: 'submit', text: 'a'.repeat(40) });
    });

    it('geçerli leave ve sync mesajlarını ayrıştırır', () => {
      expect(parseMatchRoomMessage(JSON.stringify({ t: 'leave' }))).toEqual({ t: 'leave' });
      expect(parseMatchRoomMessage(JSON.stringify({ t: 'sync' }))).toEqual({ t: 'sync' });
    });

    it('200 bayttan büyük mesajları reddeder', () => {
      const big = JSON.stringify({ t: 'submit', text: 'x'.repeat(250) });
      expect(parseMatchRoomMessage(big)).toBeNull();
    });

    it('bozuk JSON veya bilinmeyen komutlarda null döner', () => {
      expect(parseMatchRoomMessage('{broken')).toBeNull();
      expect(parseMatchRoomMessage(JSON.stringify({ t: 'other' }))).toBeNull();
      expect(parseMatchRoomMessage(JSON.stringify({ t: 'submit' }))).toBeNull(); // text yok
    });
  });
});

