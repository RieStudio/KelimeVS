import { describe, expect, it } from 'vitest';
import { AttemptTextSanitizer, parseQuestionsPool } from '../../src/engine';

describe('AttemptTextSanitizer', () => {
  it('baştaki ve sondaki boşlukları siler', () => {
    expect(AttemptTextSanitizer.sanitize('  elma  ')).toBe('elma');
    expect(AttemptTextSanitizer.sanitize('\t\n armut \r\n')).toBe('armut');
  });

  it('birden fazla ardışık boşluğu tek boşluğa indirir', () => {
    expect(AttemptTextSanitizer.sanitize('kırmızı   elma')).toBe('kırmızı elma');
    expect(AttemptTextSanitizer.sanitize('bir    iki   üç   dört')).toBe('bir iki üç dört');
    expect(AttemptTextSanitizer.sanitize('boşluk \t\t\n ayırma')).toBe('boşluk ayırma');
  });

  it('40 karakterden uzun metinleri 40 karaktere kırpar', () => {
    const longText = 'a'.repeat(50);
    const sanitized = AttemptTextSanitizer.sanitize(longText);
    expect(sanitized.length).toBe(40);
    expect(sanitized).toBe('a'.repeat(40));
  });

  it('boş veya sadece boşluk içeren girdilerde boş metin döner', () => {
    expect(AttemptTextSanitizer.sanitize('')).toBe('');
    expect(AttemptTextSanitizer.sanitize('   ')).toBe('');
    expect(AttemptTextSanitizer.sanitize('\n\t  \r')).toBe('');
  });
});

describe('parseQuestionsPool', () => {
  it('CMS questions_pool yapısını başarıyla Question nesnelerine dönüştürür', () => {
    const raw = {
      questions_pool: {
        genel_kultur: {
          q_123: {
            question: 'G20 Ülkeleri  ',
            acceptable_answers: {
              'Güney Kore': ['güney kore', 'kore'],
              'Suudi Arabistan': ['suudi arabistan', 'arabistan'],
            },
          },
        },
      },
    };

    const questions = parseQuestionsPool(raw);
    expect(questions.length).toBe(1);
    expect(questions[0].id).toBe('q_123');
    expect(questions[0].categoryId).toBe('genel_kultur');
    expect(questions[0].text).toBe('G20 Ülkeleri');
    expect(questions[0].answers.length).toBe(2);
    expect(questions[0].answers[0].id).toBe('guney kore');
    expect(questions[0].answers[0].display).toBe('Güney Kore');
    expect(questions[0].answers[0].aliases).toContain('kore');
  });

  it('düz nesne yapısını da ayrıştırır', () => {
    const raw = {
      genel_kultur: {
        q_456: {
          question: 'Başkentler',
          acceptable_answers: {
            Ankara: ['ankara'],
          },
        },
      },
    };

    const questions = parseQuestionsPool(raw);
    expect(questions.length).toBe(1);
    expect(questions[0].id).toBe('q_456');
  });
});

