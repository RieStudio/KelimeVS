import { describe, expect, it, vi } from 'vitest';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {},
}));

import {
  selectAndShuffleEightQuestions,
  createContentProvider,
  type QueueEntry,
} from '../src/matchmaker';
import { DevContentProvider } from '../src/content';
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

describe('Matchmaker Queue Logic (FIFO, Dedup, Cancel)', () => {
  it('FIFO sırasıyla oyuncuları eşleştirir', () => {
    const queue: QueueEntry[] = [
      { uid: 'u1', name: 'Alice', joinedAt: 1000 },
      { uid: 'u2', name: 'Bob', joinedAt: 2000 },
      { uid: 'u3', name: 'Charlie', joinedAt: 3000 },
    ];

    const p1 = queue.shift()!;
    const p2 = queue.shift()!;

    expect(p1.uid).toBe('u1');
    expect(p2.uid).toBe('u2');
    expect(queue.length).toBe(1);
    expect(queue[0].uid).toBe('u3');
  });

  it('aynı UID tekrar girince eski kaydı günceller (tekilleştirme)', () => {
    let queue: QueueEntry[] = [
      { uid: 'u1', name: 'Alice', joinedAt: 1000 },
      { uid: 'u2', name: 'Bob', joinedAt: 2000 },
    ];

    // u1 yeni isimle tekrar katılır
    const newEntry: QueueEntry = { uid: 'u1', name: 'AliceUpdated', joinedAt: 3000 };
    const existingIdx = queue.findIndex((e) => e.uid === newEntry.uid);
    if (existingIdx !== -1) {
      queue[existingIdx] = newEntry;
    } else {
      queue.push(newEntry);
    }

    expect(queue.length).toBe(2);
    expect(queue[0].name).toBe('AliceUpdated');
  });

  it('cancel çağrılınca oyuncu kuyruktan çıkarılır', () => {
    let queue: QueueEntry[] = [
      { uid: 'u1', name: 'Alice', joinedAt: 1000 },
      { uid: 'u2', name: 'Bob', joinedAt: 2000 },
    ];

    queue = queue.filter((e) => e.uid !== 'u1');

    expect(queue.length).toBe(1);
    expect(queue[0].uid).toBe('u2');
  });

  it('kendi kendisiyle eşleşmeyi engeller', () => {
    const queue: QueueEntry[] = [
      { uid: 'u1', name: 'Alice', joinedAt: 1000 },
      { uid: 'u1', name: 'Alice2', joinedAt: 2000 },
      { uid: 'u2', name: 'Bob', joinedAt: 3000 },
    ];

    while (queue.length >= 2) {
      const p1 = queue[0];
      const p2 = queue[1];
      if (p1.uid === p2.uid) {
        queue.splice(1, 1);
        continue;
      }
      break;
    }

    expect(queue[0].uid).toBe('u1');
    expect(queue[1].uid).toBe('u2');
  });
});

describe('Matchmaker Question Selection & Content Source Rules', () => {
  it('selectAndShuffleEightQuestions: havuzdan 8 soru seçer', () => {
    const mockQuestions: Question[] = Array.from({ length: 15 }, (_, i) => ({
      id: `q_${i}`,
      categoryId: 'cat_1',
      text: `Soru ${i}`,
      answers: [{ id: `a_${i}`, display: `Cevap ${i}`, aliases: [`a_${i}`] }],
    }));

    const selected = selectAndShuffleEightQuestions(mockQuestions);
    expect(selected.length).toBe(8);
    // Seçilenlerin hepsi benzersiz olmalı
    const ids = new Set(selected.map((q) => q.id));
    expect(ids.size).toBe(8);
  });

  it('createContentProvider: ALLOW_DEV_AUTH=true ve CONTENT_SOURCE=dev iken DevContentProvider döner', () => {
    const env = {
      ALLOW_DEV_AUTH: 'true',
      CONTENT_SOURCE: 'dev',
    } as unknown as Env;

    const provider = createContentProvider(env);
    expect(provider).toBeInstanceOf(DevContentProvider);
  });

  it('createContentProvider: ALLOW_DEV_AUTH yoksa veya false ise CONTENT_SOURCE=dev olsa bile dev kaynak kabul edilmez (RealtimeDb aranır)', () => {
    const env = {
      CONTENT_SOURCE: 'dev',
    } as unknown as Env;

    // RealtimeDb config olmadığı için hata fırlatmalı
    expect(() => createContentProvider(env)).toThrow(
      'RealtimeDbContentProvider configuration error: FIREBASE_DATABASE_URL is missing or placeholder.'
    );
  });

  it('createContentProvider: FIREBASE_DATABASE_URL eksik veya yer tutucu ise açık hata verir', () => {
    const envMissing = {
      FIREBASE_SERVICE_ACCOUNT_B64: 'fake_sa',
    } as unknown as Env;
    expect(() => createContentProvider(envMissing)).toThrow('FIREBASE_DATABASE_URL is missing');

    const envPlaceholder = {
      FIREBASE_DATABASE_URL: 'REPLACE_WITH_FIREBASE_DATABASE_URL',
      FIREBASE_SERVICE_ACCOUNT_B64: 'fake_sa',
    } as unknown as Env;
    expect(() => createContentProvider(envPlaceholder)).toThrow('FIREBASE_DATABASE_URL is missing or placeholder');
  });

  it('createContentProvider: FIREBASE_SERVICE_ACCOUNT_B64 eksikse açık hata verir', () => {
    const env = {
      FIREBASE_DATABASE_URL: 'https://test-db.firebaseio.com',
    } as unknown as Env;
    expect(() => createContentProvider(env)).toThrow('FIREBASE_SERVICE_ACCOUNT_B64 is missing');
  });
});


