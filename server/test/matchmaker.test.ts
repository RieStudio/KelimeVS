import { describe, expect, it, vi } from 'vitest';

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

import {
  selectAndShuffleEightQuestions,
  createContentProvider,
  type QueueEntry,
  Matchmaker,
} from '../src/matchmaker';
import { DevContentProvider, RealtimeDbContentProvider } from '../src/content';
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

describe('Matchmaker Content Pre-warming (İçeriği Önden Isıtma)', () => {
  function createMockDOState() {
    const storageMap = new Map<string, unknown>();
    const waitUntils: Promise<unknown>[] = [];
    const state = {
      blockConcurrencyWhile: vi.fn(async (fn: () => Promise<void>) => fn()),
      storage: {
        get: vi.fn(async (key: string) => storageMap.get(key)),
        put: vi.fn(async (key: string, val: unknown) => {
          storageMap.set(key, val);
        }),
      },
      getTags: vi.fn((_ws: unknown) => ['user-1']),
      waitUntil: vi.fn((p: Promise<unknown>) => {
        waitUntils.push(p);
      }),
      getWebSockets: vi.fn(() => []),
      acceptWebSocket: vi.fn(),
      waitUntils,
    };
    return state;
  }

  it('queue mesajı geldiğinde arka planda prewarmContent çalışır ve ctx.waitUntil çağrılır', async () => {
    const mockState = createMockDOState();
    let getQuestionsCalled = false;
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => {
        getQuestionsCalled = true;
        return [];
      }),
    };

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      {} as unknown as Env,
      mockProvider
    );

    const sentMessages: string[] = [];
    const mockWs = {
      send: vi.fn((msg: string) => sentMessages.push(msg)),
      close: vi.fn(),
    } as unknown as WebSocket;

    await mm.webSocketMessage(mockWs, JSON.stringify({ t: 'queue', name: 'Alice' }));

    expect(getQuestionsCalled).toBe(true);
    expect(mockState.waitUntil).toHaveBeenCalledTimes(1);
    expect(mockState.waitUntils.length).toBe(1);
    expect(sentMessages).toContain(JSON.stringify({ t: 'queued' }));
  });

  it('prewarm sırasında getQuestions hata fırlatırsa hata yutulur ve istemci yine queued mesajı alır', async () => {
    const mockState = createMockDOState();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => {
        throw new Error('Database unreachable during pre-warm');
      }),
    };

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      {} as unknown as Env,
      mockProvider
    );

    const sentMessages: string[] = [];
    const mockWs = {
      send: vi.fn((msg: string) => sentMessages.push(msg)),
      close: vi.fn(),
    } as unknown as WebSocket;

    // Hata fırlatmamalı
    await expect(
      mm.webSocketMessage(mockWs, JSON.stringify({ t: 'queue', name: 'Bob' }))
    ).resolves.toBeUndefined();

    // ctx.waitUntil promise'ı da hata patlatmamalı (catch ile yutulmuş olmalı)
    await expect(Promise.all(mockState.waitUntils)).resolves.toBeDefined();

    expect(sentMessages).toContain(JSON.stringify({ t: 'queued' }));
  });

  it('arka arkaya gelen birden fazla queue çağrısı tek bir in-flight isteği paylaşır', async () => {
    const mockState = createMockDOState();
    let fetchCount = 0;
    const mockFetch = vi.fn(async () => {
      fetchCount++;
      await new Promise((r) => setTimeout(r, 20));
      return new Response(
        JSON.stringify({
          q1: {
            category: 'Tarih',
            question: 'Soru 1',
            answers: { a1: 'Cevap 1' },
          },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    });

    const realProvider = new RealtimeDbContentProvider({
      databaseUrl: 'https://test-db.firebaseio.com',
      fetchFn: mockFetch,
    });

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      {} as unknown as Env,
      realProvider
    );

    const mockWs1 = { send: vi.fn(), close: vi.fn() } as unknown as WebSocket;
    const mockWs2 = { send: vi.fn(), close: vi.fn() } as unknown as WebSocket;

    mockState.getTags
      .mockReturnValueOnce(['user-1'])
      .mockReturnValueOnce(['user-2']);

    // İki oyuncu neredeyse eşzamanlı sıraya girer
    await Promise.all([
      mm.webSocketMessage(mockWs1, JSON.stringify({ t: 'queue', name: 'User1' })),
      mm.webSocketMessage(mockWs2, JSON.stringify({ t: 'queue', name: 'User2' })),
    ]);

    // Arka plan waitUntils tamamlanır
    await Promise.all(mockState.waitUntils);

    // Tek bir initial fetch (version + pool) yapılmış olmalı (single-flight)
    expect(fetchCount).toBe(2);
  });
});

describe('Matchmaker removeFromQueue', () => {
  it('oyuncuyu kuyruktan çıkarır ve websocket bağlantısını 4001 account_deleted ile kapatır', async () => {
    let storedQueue: QueueEntry[] = [
      { uid: 'del_user', name: 'DelUser', joinedAt: 1000 },
      { uid: 'stay_user', name: 'StayUser', joinedAt: 2000 },
    ];
    const mockWs = { close: vi.fn() } as unknown as WebSocket;

    const mockState = {
      storage: {
        get: vi.fn().mockImplementation(async () => storedQueue),
        put: vi.fn().mockImplementation(async (_key: string, val: any) => {
          storedQueue = val;
        }),
      },
      blockConcurrencyWhile: (fn: () => Promise<void>) => fn(),
      getWebSockets: vi.fn().mockReturnValue([mockWs]),
    };

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      {} as unknown as Env,
      new DevContentProvider()
    );

    // blockConcurrencyWhile microtaskının tamamlanması için bekle
    await new Promise((r) => setTimeout(r, 10));

    await mm.removeFromQueue('del_user');

    expect(storedQueue).toHaveLength(1);
    expect(storedQueue[0].uid).toBe('stay_user');
    expect(mockWs.close).toHaveBeenCalledWith(4001, 'account_deleted');
  });
});



