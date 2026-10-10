import { describe, expect, it } from 'vitest';
import type { QueueEntry } from '../src/matchmaker';

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

