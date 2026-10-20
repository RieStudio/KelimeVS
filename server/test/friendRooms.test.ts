import { describe, it, expect, vi, beforeEach } from 'vitest';

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
  FRIEND_CODE_ALPHABET,
  generateFriendCode,
  sanitizeFriendCode,
  parseMatchmakerMessage,
} from '../src/protocol';
import { Matchmaker } from '../src/matchmaker';
import { MatchRoom } from '../src/matchRoom';
import type { Question } from '../src/engine';
import type { Env } from '../src/index';

// 8 geçerli soru
const mockQuestions: any[] = [
  { id: 'q1', text: 'Soru 1', answers: [{ text: 'elma', points: 1 }] },
  { id: 'q2', text: 'Soru 2', answers: [{ text: 'armut', points: 1 }] },
  { id: 'q3', text: 'Soru 3', answers: [{ text: 'kiraz', points: 1 }] },
  { id: 'q4', text: 'Soru 4', answers: [{ text: 'muz', points: 1 }] },
  { id: 'q5', text: 'Soru 5', answers: [{ text: 'çilek', points: 1 }] },
  { id: 'q6', text: 'Soru 6', answers: [{ text: 'karpuz', points: 1 }] },
  { id: 'q7', text: 'Soru 7', answers: [{ text: 'kavun', points: 1 }] },
  { id: 'q8', text: 'Soru 8', answers: [{ text: 'incir', points: 1 }] },
];

function createMockContentProvider() {
  return {
    getQuestions: vi.fn(async () => mockQuestions),
  };
}

class FakeWebSocket {
  public sent: string[] = [];
  public closed = false;
  public closeCode?: number;
  public closeReason?: string;
  private attachment: any = null;

  send(data: string) {
    this.sent.push(data);
  }

  close(code?: number, reason?: string) {
    this.closed = true;
    this.closeCode = code;
    this.closeReason = reason;
  }

  serializeAttachment(att: any) {
    this.attachment = att;
  }

  deserializeAttachment() {
    return this.attachment;
  }

  getLastMessage(): any {
    if (this.sent.length === 0) return null;
    return JSON.parse(this.sent[this.sent.length - 1]);
  }
}

function createMockMatchmakerState() {
  const store = new Map<string, any>();
  const sockets = new Map<string, FakeWebSocket[]>();

  const state = {
    storage: {
      get: vi.fn(async (key: string) => store.get(key)),
      put: vi.fn(async (key: string, val: any) => store.set(key, val)),
      delete: vi.fn(async (key: string) => store.delete(key)),
      deleteAll: vi.fn(async () => store.clear()),
      setAlarm: vi.fn(async (_time: number) => {}),
    },
    blockConcurrencyWhile: vi.fn(async (cb: () => Promise<void>) => {
      await cb();
    }),
    acceptWebSocket: vi.fn((_ws: any, tags: string[]) => {
      const uid = tags[0];
      const ws = new FakeWebSocket();
      const list = sockets.get(uid) ?? [];
      list.push(ws);
      sockets.set(uid, list);
    }),
    getWebSockets: vi.fn((tag?: string) => {
      if (!tag) {
        const all: FakeWebSocket[] = [];
        for (const list of sockets.values()) all.push(...list);
        return all;
      }
      return sockets.get(tag) ?? [];
    }),
    getTags: vi.fn((ws: any) => {
      for (const [uid, list] of sockets.entries()) {
        if (list.includes(ws)) return [uid, 'ip:127.0.0.1'];
      }
      return ['unknown', 'ip:127.0.0.1'];
    }),
  };

  return { state, store, sockets };
}

describe('Arkadaş Düellosu - Kod Alfabesi ve Üretimi', () => {
  it('1. Alfabe tam olarak 28 karakterdir ve sesli harfler (A, E, I, O, U) ile karıştırılan karakterler (0, 1, L) yer almaz', () => {
    expect(FRIEND_CODE_ALPHABET.length).toBe(28);
    // Sesli harfler olmamalı
    for (const vowel of ['A', 'E', 'I', 'O', 'U']) {
      expect(FRIEND_CODE_ALPHABET).not.toContain(vowel);
    }
    // Karışan karakterler olmamalı
    for (const char of ['0', '1', 'L']) {
      expect(FRIEND_CODE_ALPHABET).not.toContain(char);
    }
    // 2-9 rakamları olmalı
    for (let d = 2; d <= 9; d++) {
      expect(FRIEND_CODE_ALPHABET).toContain(String(d));
    }
  });

  it('2. generateFriendCode 6 karakterli geçerli bir kod üretir', () => {
    for (let i = 0; i < 50; i++) {
      const code = generateFriendCode();
      expect(code.length).toBe(6);
      expect(sanitizeFriendCode(code)).toBe(code);
    }
  });

  it('3. sanitizeFriendCode geçersiz veya yasaklı karakterleri reddeder', () => {
    expect(sanitizeFriendCode('234567')).toBe('234567');
    expect(sanitizeFriendCode('bcdfgh')).toBe('BCDFGH');
    expect(sanitizeFriendCode('BCDFG0')).toBeNull(); // 0 yasak
    expect(sanitizeFriendCode('BCDFGA')).toBeNull(); // A yasak
    expect(sanitizeFriendCode('BCDFGE')).toBeNull(); // E yasak
    expect(sanitizeFriendCode('BCDFGI')).toBeNull(); // I yasak
    expect(sanitizeFriendCode('BCDFGO')).toBeNull(); // O yasak
    expect(sanitizeFriendCode('BCDFGU')).toBeNull(); // U yasak
    expect(sanitizeFriendCode('BCDFGL')).toBeNull(); // L yasak
    expect(sanitizeFriendCode('123456')).toBeNull(); // 1 yasak
    expect(sanitizeFriendCode('ABC')).toBeNull(); // uzunluk 6 olmalı
  });
});

describe('Arkadaş Düellosu - Matchmaker Lobi Yönetimi', () => {
  let mockMatchRoomStub: any;
  let mockUserProfileStub: any;
  let mockEnv: any;

  beforeEach(() => {
    mockMatchRoomStub = {
      initMatch: vi.fn(async () => {}),
    };
    mockUserProfileStub = {
      getProfile: vi.fn(async (uid: string) => ({ nickname: `User_${uid}`, coins: 100 })),
      getBlockedUids: vi.fn(async () => []),
      isDeleted: vi.fn(async () => false),
    };

    mockEnv = {
      MATCH_ROOM: {
        get: vi.fn(() => mockMatchRoomStub),
        idFromName: vi.fn((name: string) => ({ toString: () => name })),
      },
      USER_PROFILE: {
        get: vi.fn(() => mockUserProfileStub),
        idFromName: vi.fn((name: string) => ({ toString: () => name })),
      },
      FAST_TIMERS: 'true',
    } as unknown as Env;
  });

  it('4. create_room başarılı şekilde oda kurar ve 6 haneli kod döner', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const ws = new FakeWebSocket();
    sockets.set('user_host', [ws]);

    await matchmaker.webSocketMessage(ws as any, JSON.stringify({ t: 'create_room' }));

    const res = ws.getLastMessage();
    expect(res).not.toBeNull();
    expect(res.t).toBe('room_created');
    expect(res.code.length).toBe(6);
    expect(res.expiresAt).toBeGreaterThan(Date.now());
  });

  it('5. Kurucunun soketi koptuğunda (WhatsApp geçişi) oda silinmez; resume_room ile odaya devam eder (Grace Period)', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const wsHost1 = new FakeWebSocket();
    sockets.set('user_host', [wsHost1]);

    await matchmaker.webSocketMessage(wsHost1 as any, JSON.stringify({ t: 'create_room' }));
    const createdMsg = wsHost1.getLastMessage();
    const roomCode = createdMsg.code;

    // Kurucu arka plana geçer, soket kapanır
    await matchmaker.webSocketClose(wsHost1 as any, 1000, 'background', true);

    // Yeni soket açılır (uygulamaya dönüş)
    const wsHost2 = new FakeWebSocket();
    sockets.set('user_host', [wsHost2]);

    await matchmaker.webSocketMessage(
      wsHost2 as any,
      JSON.stringify({ t: 'resume_room', code: roomCode })
    );

    const resumedMsg = wsHost2.getLastMessage();
    expect(resumedMsg).not.toBeNull();
    expect(resumedMsg.t).toBe('room_resumed');
    expect(resumedMsg.code).toBe(roomCode);
  });

  it('6. Kurucu arka plandayken katılan oyuncu kodu girerse maç kurulur, kurucu dönünce matched alır', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    // 1. Kurucu odayı kurar
    const wsHost1 = new FakeWebSocket();
    sockets.set('user_host', [wsHost1]);
    await matchmaker.webSocketMessage(wsHost1 as any, JSON.stringify({ t: 'create_room' }));
    const roomCode = wsHost1.getLastMessage().code;

    // 2. Kurucu WhatsApp'a geçer, kurucunun soketi kapanır/temizlenir
    sockets.set('user_host', []);

    // 3. Katılan oyuncu koda katılır
    const wsGuest = new FakeWebSocket();
    sockets.set('user_guest', [wsGuest]);
    await matchmaker.webSocketMessage(
      wsGuest as any,
      JSON.stringify({ t: 'join_room', code: roomCode })
    );

    // Katılan derhal matched alır
    const guestMsg = wsGuest.getLastMessage();
    expect(guestMsg.t).toBe('matched');
    expect(guestMsg.isFriendly).toBe(true);

    // 4. Kurucu WhatsApp'tan döner ve resume_room çağırır
    const wsHost2 = new FakeWebSocket();
    sockets.set('user_host', [wsHost2]);
    await matchmaker.webSocketMessage(
      wsHost2 as any,
      JSON.stringify({ t: 'resume_room', code: roomCode })
    );

    // Kurucu bekletilmeden anında matched alır
    const hostMsg = wsHost2.getLastMessage();
    expect(hostMsg.t).toBe('matched');
    expect(hostMsg.matchId).toBe(guestMsg.matchId);
    expect(hostMsg.isFriendly).toBe(true);
  });

  it('7. Kendi odasına katılmak cannot_join_own_room hatası verir', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const ws = new FakeWebSocket();
    sockets.set('user_self', [ws]);

    await matchmaker.webSocketMessage(ws as any, JSON.stringify({ t: 'create_room' }));
    const code = ws.getLastMessage().code;

    await matchmaker.webSocketMessage(ws as any, JSON.stringify({ t: 'join_room', code }));
    const err = ws.getLastMessage();
    expect(err.t).toBe('error');
    expect(err.code).toBe('cannot_join_own_room');
  });

  it('8. Karşılıklı engelleme durumunda katılım engellenir (room_unavailable)', async () => {
    mockUserProfileStub.getBlockedUids = vi.fn(async () => ['user_guest']); // Host, Guest'i engellemiş

    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const wsHost = new FakeWebSocket();
    sockets.set('user_host', [wsHost]);
    await matchmaker.webSocketMessage(wsHost as any, JSON.stringify({ t: 'create_room' }));
    const code = wsHost.getLastMessage().code;

    const wsGuest = new FakeWebSocket();
    sockets.set('user_guest', [wsGuest]);
    await matchmaker.webSocketMessage(wsGuest as any, JSON.stringify({ t: 'join_room', code }));

    const err = wsGuest.getLastMessage();
    expect(err.t).toBe('error');
    expect(err.code).toBe('room_unavailable');
  });

  it('9. Hatalı kod denemelerinde rate limit (dakikada 5) devreye girer', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const wsGuest = new FakeWebSocket();
    sockets.set('user_attacker', [wsGuest]);

    for (let i = 0; i < 5; i++) {
      await matchmaker.webSocketMessage(
        wsGuest as any,
        JSON.stringify({ t: 'join_room', code: '999999' })
      );
      expect(wsGuest.getLastMessage().code).toBe('room_not_found');
    }

    // 6. deneme rate_limited olmalı
    await matchmaker.webSocketMessage(
      wsGuest as any,
      JSON.stringify({ t: 'join_room', code: '999999' })
    );
    const rlErr = wsGuest.getLastMessage();
    expect(rlErr.t).toBe('error');
    expect(rlErr.code).toBe('rate_limited');
  });

  it('10. cancel_room ve removeFromQueue (hesap silme) açık arkadaş odasını temizler', async () => {
    const { state, sockets } = createMockMatchmakerState();
    const matchmaker = new Matchmaker(state as any, mockEnv, createMockContentProvider() as any);

    const wsHost = new FakeWebSocket();
    sockets.set('user_delete', [wsHost]);
    await matchmaker.webSocketMessage(wsHost as any, JSON.stringify({ t: 'create_room' }));
    const code = wsHost.getLastMessage().code;

    // Hesap silme çağrısı
    await matchmaker.removeFromQueue('user_delete');

    // Başka bir oyuncu bu koda katılmayı denerse oda bulunamaz
    const wsGuest = new FakeWebSocket();
    sockets.set('user_guest', [wsGuest]);
    await matchmaker.webSocketMessage(wsGuest as any, JSON.stringify({ t: 'join_room', code }));

    expect(wsGuest.getLastMessage().code).toBe('room_not_found');
  });
});

describe('Arkadaş Düellosu - MatchRoom Ödül ve İstatistik İzolasyonu', () => {
  it('11. Arkadaş maçında (friendly) maç bittiğinde UserProfile.applyMatchReward ve Leaderboard çağrılmaz', async () => {
    const mockProfileStub = {
      applyMatchReward: vi.fn(),
    };
    const mockLeaderboardStub = {
      recordMatchResult: vi.fn(),
    };

    const mockEnv = {
      USER_PROFILE: {
        get: vi.fn(() => mockProfileStub),
        idFromName: vi.fn(() => ({ toString: () => 'mock' })),
      },
      LEADERBOARD: {
        get: vi.fn(() => mockLeaderboardStub),
        idFromName: vi.fn(() => ({ toString: () => 'global' })),
      },
      FAST_TIMERS: 'true',
    } as unknown as Env;

    const store = new Map<string, any>();
    const sockets = new Map<string, FakeWebSocket[]>();
    const state = {
      storage: {
        get: vi.fn(async (key: string) => store.get(key)),
        put: vi.fn(async (key: string, val: any) => store.set(key, val)),
        delete: vi.fn(async (key: string) => store.delete(key)),
        deleteAll: vi.fn(async () => store.clear()),
        setAlarm: vi.fn(async () => {}),
      },
      blockConcurrencyWhile: vi.fn(async (cb: () => Promise<void>) => {
        await cb();
      }),
      getWebSockets: vi.fn((uid?: string) => (uid ? sockets.get(uid) ?? [] : [])),
      getTags: vi.fn((ws: any) => {
        for (const [uid, list] of sockets.entries()) {
          if (list.includes(ws)) return [uid];
        }
        return ['p1'];
      }),
    };

    const room = new MatchRoom(state as any, mockEnv);

    // Arkadaş maçı başlat
    await room.initMatch({
      matchId: 'friend_match_123',
      p1: { uid: 'p1', name: 'Ali' },
      p2: { uid: 'p2', name: 'Veli' },
      questions: mockQuestions,
      questionOrder: mockQuestions.map((q) => q.id),
      matchType: 'friendly',
    });

    const ws1 = new FakeWebSocket();
    const ws2 = new FakeWebSocket();
    sockets.set('p1', [ws1]);
    sockets.set('p2', [ws2]);

    // İki oyuncu da bağlanır
    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // p1 maçı terk eder (forfeit çıkış yolu)
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'leave' }));

    // UserProfile ödülü ve Leaderboard ASLA çağrılmamalıdır
    expect(mockProfileStub.applyMatchReward).not.toHaveBeenCalled();
    expect(mockLeaderboardStub.recordMatchResult).not.toHaveBeenCalled();

    // Gönderilen final mesajında coinsAwarded 0 olmalıdır
    const final1 = ws1.sent.map((s) => JSON.parse(s)).find((m) => m.t === 'final');
    expect(final1).toBeDefined();
    expect(final1.coinsAwarded).toBe(0);
  });
});
