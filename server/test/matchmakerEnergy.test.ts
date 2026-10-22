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
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

function createDummyQuestions(): Question[] {
  return Array.from({ length: 8 }, (_, i) => ({
    id: `q-${i}`,
    categoryId: 'c1',
    text: `Soru ${i}`,
    answers: [{ id: `a-${i}`, display: `Cevap ${i}`, aliases: [`a-${i}`] }],
  }));
}

function createMockDOState() {
  const storageMap = new Map<string, unknown>();
  const socketsMap = new Map<string, WebSocket[]>();
  let currentAlarm: number | null = null;

  const state = {
    blockConcurrencyWhile: vi.fn(async (fn: () => Promise<void>) => fn()),
    storage: {
      get: vi.fn(async (key: string) => storageMap.get(key)),
      put: vi.fn(async (key: string, val: unknown) => {
        storageMap.set(key, val);
      }),
      setAlarm: vi.fn(async (timestamp: number) => {
        currentAlarm = timestamp;
      }),
      getAlarm: vi.fn(async () => currentAlarm),
      deleteAlarm: vi.fn(async () => {
        currentAlarm = null;
      }),
    },
    getTags: vi.fn((ws: any) => ws._tags ?? []),
    waitUntil: vi.fn(),
    getWebSockets: vi.fn((tag?: string) => {
      if (!tag) return [];
      return socketsMap.get(tag) ?? [];
    }),
    acceptWebSocket: vi.fn((ws: any, tags: string[]) => {
      ws._tags = tags;
      const uid = tags[0];
      if (uid) {
        if (!socketsMap.has(uid)) socketsMap.set(uid, []);
        socketsMap.get(uid)!.push(ws);
      }
    }),
    storageMap,
    socketsMap,
    getAlarmTime: () => currentAlarm,
  };
  return state;
}

function createMockWs(uid: string) {
  const sentMessages: string[] = [];
  const ws = {
    _tags: [uid, 'ip:127.0.0.1'],
    send: vi.fn((msg: string) => sentMessages.push(msg)),
    close: vi.fn(),
    sentMessages,
  } as unknown as WebSocket & { sentMessages: string[]; _tags: string[] };
  return ws;
}

describe('Matchmaker Energy Integration & Mixed Matching', () => {
  it('kuyruğa girerken kullanıcının enerjisi yetersizse (0) no_energy hatası gönderir ve 1008 ile kapatır', async () => {
    const mockState = createMockDOState();
    const mockProfileStub = {
      getBlockedUids: vi.fn(async () => []),
      getProfile: vi.fn(async (uid: string) => ({
        uid,
        nickname: 'Alice',
        equippedFrame: 'classic',
        coins: 100,
      })),
      getEnergyState: vi.fn(async () => ({
        enabled: true,
        current: 0,
        max: 5,
        nextEnergyAtMs: Date.now() + 600000,
        regenSeconds: 1200,
        packs: [],
      })),
    };

    const env = {
      ENERGY_ENABLED: 'true',
      ENERGY_COST_PER_MATCH: '1',
      USER_PROFILE: {
        idFromName: vi.fn((uid: string) => uid),
        get: vi.fn(() => mockProfileStub),
      },
    } as unknown as Env;

    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const ws = createMockWs('u1');

    await mm.webSocketMessage(ws, JSON.stringify({ t: 'queue', name: 'Alice' }));

    expect(ws.send).toHaveBeenCalledWith(
      JSON.stringify({
        t: 'error',
        code: 'no_energy',
        message: 'Enerjin bitti',
      })
    );
    expect(ws.close).toHaveBeenCalledWith(1008, 'no_energy');
    // Kuyruğa eklenmemelidir
    expect((mm as any).queue).toHaveLength(0);
  });

  it('Karışık Durum: p1 için enerji açık, p2 için enerji kapalıysa yalnızca p1 den enerji düşer', async () => {
    const mockState = createMockDOState();

    const p1SpendEnergy = vi.fn(async () => ({ success: true, energy: 4 }));
    const p2SpendEnergy = vi.fn(async () => ({ success: true, energy: 4 }));

    const env = {
      ENERGY_ENABLED: 'false',
      ENERGY_TEST_UIDS: 'u1', // Yalnızca u1 için açık
      ENERGY_COST_PER_MATCH: '1',
      USER_PROFILE: {
        idFromName: vi.fn((uid: string) => uid),
        get: vi.fn((uid: string) => ({
          getBlockedUids: vi.fn(async () => []),
          getProfile: vi.fn(async (id: string) => ({
            uid: id,
            nickname: id === 'u1' ? 'Alice' : 'Bob',
            equippedFrame: 'classic',
          })),
          getEnergyState: vi.fn(async () => ({
            enabled: uid === 'u1',
            current: 5,
            max: 5,
            nextEnergyAtMs: null,
            regenSeconds: 1200,
            packs: [],
          })),
          spendEnergy: uid === 'u1' ? p1SpendEnergy : p2SpendEnergy,
          refundEnergy: vi.fn(async () => ({ ok: true, refunded: true, energy: 5 })),
        })),
      },
      MATCH_ROOM: {
        idFromName: vi.fn((id: string) => id),
        get: vi.fn(() => ({
          initMatch: vi.fn(async () => {}),
        })),
      },
    } as unknown as Env;

    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);

    const ws1 = createMockWs('u1');
    mockState.acceptWebSocket(ws1, ws1._tags);
    await mm.webSocketMessage(ws1, JSON.stringify({ t: 'queue', name: 'Alice' }));

    const ws2 = createMockWs('u2');
    mockState.acceptWebSocket(ws2, ws2._tags);
    await mm.webSocketMessage(ws2, JSON.stringify({ t: 'queue', name: 'Bob' }));

    // p1 için spendEnergy çağrılmalı, p2 için çağrılmamalı
    expect(p1SpendEnergy).toHaveBeenCalledTimes(1);
    expect(p2SpendEnergy).not.toHaveBeenCalled();

    // İki oyuncuya da matched mesajı gitmiş olmalı
    expect((ws1 as any).sentMessages.some((m: string) => m.includes('"t":"matched"'))).toBe(true);
    expect((ws2 as any).sentMessages.some((m: string) => m.includes('"t":"matched"'))).toBe(true);
  });

  it('initMatch başarısız olursa her iki oyuncunun enerjisi de iade edilir', async () => {
    const mockState = createMockDOState();

    const p1RefundEnergy = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));
    const p2RefundEnergy = vi.fn(async () => ({ ok: true, refunded: true, energy: 5 }));

    const env = {
      ENERGY_ENABLED: 'true',
      ENERGY_COST_PER_MATCH: '1',
      USER_PROFILE: {
        idFromName: vi.fn((uid: string) => uid),
        get: vi.fn((uid: string) => ({
          getBlockedUids: vi.fn(async () => []),
          getProfile: vi.fn(async (id: string) => ({ uid: id, nickname: id })),
          getEnergyState: vi.fn(async () => ({
            enabled: true,
            current: 5,
            max: 5,
            nextEnergyAtMs: null,
            regenSeconds: 1200,
            packs: [],
          })),
          spendEnergy: vi.fn(async () => ({ success: true, energy: 4 })),
          refundEnergy: uid === 'u1' ? p1RefundEnergy : p2RefundEnergy,
        })),
      },
      MATCH_ROOM: {
        idFromName: vi.fn((id: string) => id),
        get: vi.fn(() => ({
          initMatch: vi.fn(async () => {
            throw new Error('MatchRoom crashed');
          }),
        })),
      },
    } as unknown as Env;

    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);

    const ws1 = createMockWs('u1');
    mockState.acceptWebSocket(ws1, ws1._tags);
    await mm.webSocketMessage(ws1, JSON.stringify({ t: 'queue', name: 'Alice' }));

    const ws2 = createMockWs('u2');
    mockState.acceptWebSocket(ws2, ws2._tags);
    await mm.webSocketMessage(ws2, JSON.stringify({ t: 'queue', name: 'Bob' }));

    // Her iki oyuncuya da refundEnergy çağrılmalı
    expect(p1RefundEnergy).toHaveBeenCalledTimes(1);
    expect(p2RefundEnergy).toHaveBeenCalledTimes(1);
  });
});

