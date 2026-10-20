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

import { Matchmaker } from '../src/matchmaker';
import type { Env } from '../src/index';

function createMockDOState() {
  const storageMap = new Map<string, unknown>();
  const socketsMap = new Map<string, any[]>();

  const state = {
    blockConcurrencyWhile: vi.fn(async (fn: () => Promise<void>) => fn()),
    storage: {
      get: vi.fn(async (key: string) => storageMap.get(key)),
      put: vi.fn(async (key: string, val: unknown) => {
        storageMap.set(key, val);
      }),
    },
    getTags: vi.fn((ws: any) => ws.__tags ?? []),
    getWebSockets: vi.fn((tag?: string) => {
      if (tag) return socketsMap.get(tag) ?? [];
      const all: any[] = [];
      for (const list of socketsMap.values()) all.push(...list);
      return all;
    }),
    acceptWebSocket: vi.fn((ws: any, tags: string[]) => {
      ws.__tags = tags;
      for (const t of tags) {
        if (!socketsMap.has(t)) socketsMap.set(t, []);
        socketsMap.get(t)!.push(ws);
      }
    }),
    waitUntil: vi.fn(),
    storageMap,
  };
  return state;
}

describe('Matchmaker Blocking & Bot Timeout Tests', () => {
  const dummyQuestions = Array.from({ length: 10 }, (_, i) => ({
    id: `q${i}`,
    categoryId: 'cat1',
    text: `Soru ${i}`,
    answers: [{ id: `a${i}`, display: `Cevap ${i}`, aliases: [] }],
  }));

  const mockProvider = {
    source: 'test' as const,
    getQuestions: vi.fn(async () => dummyQuestions),
  };

  it('1. Birbirini engellemiş 2 oyuncu kuyrukta tek kalsa bile eşleştirilmez ve kuyrukta kalır', async () => {
    const mockState = createMockDOState();

    // UserProfile mock: p1, p2'yi engellemiş
    const mockEnv = {
      USER_PROFILE: {
        idFromName: (name: string) => ({ toString: () => name }),
        get: (id: any) => ({
          getBlockedUids: async () => {
            if (id.toString() === 'p1') return ['p2'];
            return [];
          },
        }),
      },
      MATCH_ROOM: {
        idFromName: () => ({ toString: () => 'room_1' }),
        get: () => ({
          initMatch: vi.fn(),
        }),
      },
    } as unknown as Env;

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      mockEnv,
      mockProvider
    );

    const ws1 = { send: vi.fn(), close: vi.fn(), __tags: ['p1'] };
    const ws2 = { send: vi.fn(), close: vi.fn(), __tags: ['p2'] };
    mockState.acceptWebSocket(ws1, ['p1']);
    mockState.acceptWebSocket(ws2, ['p2']);

    await mm.webSocketMessage(ws1 as any, JSON.stringify({ t: 'queue', name: 'Player1' }));
    await mm.webSocketMessage(ws2 as any, JSON.stringify({ t: 'queue', name: 'Player2' }));

    // Eşleşme OLMAMALI, iki oyuncu da kuyrukta beklemeli
    const queue = (await mockState.storage.get('queue')) as any[];
    expect(queue.length).toBe(2);
    expect(queue[0].uid).toBe('p1');
    expect(queue[1].uid).toBe('p2');

    // Hiçbirine matched mesajı gitmemeli
    expect(ws1.send).toHaveBeenCalledWith(JSON.stringify({ t: 'queued' }));
    expect(ws2.send).toHaveBeenCalledWith(JSON.stringify({ t: 'queued' }));
    expect(ws1.send).not.toHaveBeenCalledWith(expect.stringContaining('"t":"matched"'));
    expect(ws2.send).not.toHaveBeenCalledWith(expect.stringContaining('"t":"matched"'));
  });

  it('2. Kuyruktaki tek aday engelli ise oyuncu 10 sn sonra iptal edip bot maçına geçebilir', async () => {
    const mockState = createMockDOState();

    const mockEnv = {
      USER_PROFILE: {
        idFromName: (name: string) => ({ toString: () => name }),
        get: (id: any) => ({
          getBlockedUids: async () => {
            if (id.toString() === 'p1') return ['p2'];
            return [];
          },
        }),
      },
    } as unknown as Env;

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      mockEnv,
      mockProvider
    );

    const ws1 = { send: vi.fn(), close: vi.fn(), __tags: ['p1'] };
    const ws2 = { send: vi.fn(), close: vi.fn(), __tags: ['p2'] };
    mockState.acceptWebSocket(ws1, ['p1']);
    mockState.acceptWebSocket(ws2, ['p2']);

    await mm.webSocketMessage(ws1 as any, JSON.stringify({ t: 'queue', name: 'Player1' }));
    await mm.webSocketMessage(ws2 as any, JSON.stringify({ t: 'queue', name: 'Player2' }));

    // p1 süresi dolup iptal (cancel) gönderdiğinde kuyruktan silinir
    await mm.webSocketMessage(ws1 as any, JSON.stringify({ t: 'cancel' }));

    const queue = (await mockState.storage.get('queue')) as any[];
    expect(queue.length).toBe(1);
    expect(queue[0].uid).toBe('p2'); // p2 kuyrukta kalır
  });

  it('3. Engelli ikili varken engelsiz 3. oyuncu gelirse uygun olanla hemen eşleşir', async () => {
    const mockState = createMockDOState();

    // p1, p2'yi engellemiş. p3 ise engelsiz.
    const mockEnv = {
      USER_PROFILE: {
        idFromName: (name: string) => ({ toString: () => name }),
        get: (id: any) => ({
          getBlockedUids: async () => {
            if (id.toString() === 'p1') return ['p2'];
            return [];
          },
        }),
      },
      MATCH_ROOM: {
        idFromName: () => ({ toString: () => 'room_1' }),
        get: () => ({
          initMatch: vi.fn(),
        }),
      },
    } as unknown as Env;

    const mm = new Matchmaker(
      mockState as unknown as DurableObjectState,
      mockEnv,
      mockProvider
    );

    const ws1 = { send: vi.fn(), close: vi.fn(), __tags: ['p1'] };
    const ws2 = { send: vi.fn(), close: vi.fn(), __tags: ['p2'] };
    const ws3 = { send: vi.fn(), close: vi.fn(), __tags: ['p3'] };
    mockState.acceptWebSocket(ws1, ['p1']);
    mockState.acceptWebSocket(ws2, ['p2']);
    mockState.acceptWebSocket(ws3, ['p3']);

    await mm.webSocketMessage(ws1 as any, JSON.stringify({ t: 'queue', name: 'Player1' }));
    await mm.webSocketMessage(ws2 as any, JSON.stringify({ t: 'queue', name: 'Player2' }));
    // p1 ve p2 eşleşmedi. Şimdi p3 katılıyor:
    await mm.webSocketMessage(ws3 as any, JSON.stringify({ t: 'queue', name: 'Player3' }));

    // p1 ve p3 eşleşmeli!
    expect(ws1.send).toHaveBeenCalledWith(expect.stringContaining('"t":"matched"'));
    expect(ws3.send).toHaveBeenCalledWith(expect.stringContaining('"t":"matched"'));

    // p2 ise kuyrukta kalmaya devam etmeli
    const queue = (await mockState.storage.get('queue')) as any[];
    expect(queue.length).toBe(1);
    expect(queue[0].uid).toBe('p2');
  });
});

