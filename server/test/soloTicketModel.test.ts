import { describe, expect, it, vi } from 'vitest';
import { DatabaseSync } from 'node:sqlite';

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

import { UserProfile } from '../src/userProfile';
import { Matchmaker } from '../src/matchmaker';
import worker, { type Env } from '../src/index';
import type { Question } from '../src/engine';

function createDummyQuestions(): Question[] {
  return Array.from({ length: 8 }, (_, i) => ({
    id: `q-${i}`,
    categoryId: 'c1',
    text: `Soru ${i}`,
    answers: [{ id: `a-${i}`, display: `Cevap ${i}`, aliases: [`a-${i}`] }],
  }));
}

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  let alarmTime: number | null = null;
  const webSockets: any[] = [];
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('PRAGMA')
      ) {
        const stmt = db.prepare(trimmed);
        const rows = stmt.all(...bindings) as T[];
        return {
          toArray: () => rows,
          one: () => rows[0],
          [Symbol.iterator]: () => rows[Symbol.iterator](),
        };
      } else {
        if (bindings.length > 0) {
          const stmt = db.prepare(trimmed);
          stmt.run(...bindings);
        } else {
          db.exec(trimmed);
        }
        return {
          toArray: () => [],
          one: () => undefined as any,
          [Symbol.iterator]: () => [][Symbol.iterator](),
        };
      }
    },
  };

  return {
    rawDb: db,
    storage: {
      sql,
      transactionSync<T>(closure: () => T): T {
        db.exec('BEGIN TRANSACTION');
        try {
          const res = closure();
          db.exec('COMMIT');
          return res;
        } catch (err) {
          try {
            db.exec('ROLLBACK');
          } catch {}
          throw err;
        }
      },
      async setAlarm(t: number) {
        alarmTime = t;
      },
      async getAlarm() {
        return alarmTime;
      },
      async deleteAlarm() {
        alarmTime = null;
      },
      async deleteAll() {
        alarmTime = null;
      },
    },
    acceptWebSocket(ws: any, tags?: string[]) {
      (ws as any).tags = tags ?? [];
      webSockets.push(ws);
    },
    getWebSockets() {
      return webSockets;
    },
    getTags(ws: any) {
      return (ws as any).tags ?? [];
    },
  } as unknown as DurableObjectState & { rawDb: DatabaseSync };
}

function createEnv(overrides?: Partial<Env>) {
  const profilesMap = new Map<string, UserProfile>();
  const ctxMap = new Map<string, any>();

  const userProfileNamespace = {
    idFromName(name: string) {
      return { toString: () => name };
    },
    get(id: { toString: () => string }) {
      const key = id.toString();
      if (!profilesMap.has(key)) {
        const ctx = createMockCtx();
        ctxMap.set(key, ctx);
        profilesMap.set(key, new UserProfile(ctx, fullEnv));
      }
      return profilesMap.get(key)!;
    },
  } as unknown as DurableObjectNamespace<UserProfile>;

  const fullEnv: Env = {
    MATCHMAKER: {
      idFromName: () => ({ toString: () => 'mm' }),
      get: () => ({
        leaveQueue: vi.fn().mockResolvedValue(true),
        removeFromQueue: vi.fn().mockResolvedValue(true),
      }),
    } as any,
    MATCH_ROOM: {
      idFromName: (name: string) => ({ toString: () => name }),
      get: () => ({
        initMatch: vi.fn().mockResolvedValue(undefined),
      }),
    } as any,
    USER_PROFILE: userProfileNamespace,
    ALLOW_DEV_AUTH: 'true',
    START_COINS: '100',
    ENERGY_ENABLED: 'true',
    ENERGY_MAX: '5',
    ENERGY_REGEN_MINUTES: '20',
    ENERGY_COST_PER_MATCH: '1',
    DAILY_MATCH_COIN_CAP: 'unlimited',
    ...overrides,
  };

  return { env: fullEnv, profilesMap, ctxMap };
}

function createMockDOStateForMatchmaker() {
  const storageMap = new Map<string, unknown>();
  const socketsMap = new Map<string, any[]>();
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

describe('Bilet Modeli - issueSoloTicket & Enerji Atomikliği', () => {
  it('1. Bilet üretimi: 1 enerji düşülür ve solo_tickets tablosuna satır yazılır', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'ticket_user_1';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const beforeEnergy = await profile.getEnergyState(uid);
    expect(beforeEnergy.current).toBe(5);

    const now = Date.now();
    const ticket = await profile.issueSoloTicket(uid, now);

    expect(ticket.ok).toBe(true);
    expect(ticket.ticketId).toMatch(/^stk_[A-Za-z0-9_-]{24}$/);
    expect(ticket.matchId).toMatch(/^bot:[A-Za-z0-9_-]{24}$/);
    expect(ticket.issuedAt).toBe(now);
    expect(ticket.energy?.current).toBe(4);

    const ctx = ctxMap.get(uid);
    const row = ctx.rawDb
      .prepare('SELECT ticket_id, match_id, issued_at, expires_at, used FROM solo_tickets WHERE ticket_id = ?')
      .get(ticket.ticketId!) as any;

    expect(row).toBeDefined();
    expect(row.ticket_id).toBe(ticket.ticketId);
    expect(row.match_id).toBe(ticket.matchId);
    expect(row.issued_at).toBe(now);
    expect(row.expires_at).toBe(now + 15 * 60 * 1000);
    expect(row.used).toBe(0);
  });

  it('2. Enerji yetersizse (0 enerji): bilet üretilemez, veritabanına HİÇBİR ŞEY yazılmaz', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'ticket_user_no_energy';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const baseTime = Date.now();
    // 5 maç oynayarak enerjiyi tüket
    for (let i = 0; i < 5; i++) {
      const t = await profile.issueSoloTicket(uid, baseTime + i * 10);
      expect(t.ok).toBe(true);
    }

    const energyAfter5 = await profile.getEnergyState(uid, baseTime + 100);
    expect(energyAfter5.current).toBe(0);

    const ctx = ctxMap.get(uid);
    const ticketsBefore = ctx.rawDb.prepare('SELECT COUNT(*) as c FROM solo_tickets').get() as any;
    expect(ticketsBefore.c).toBe(5);

    // 6. bilet çağrısı - enerji yok
    const failedTicket = await profile.issueSoloTicket(uid, baseTime + 200);
    expect(failedTicket.ok).toBe(false);
    expect(failedTicket.reason).toBe('no_energy');

    // solo_tickets sayısının değişmediğini doğrula
    const ticketsAfter = ctx.rawDb.prepare('SELECT COUNT(*) as c FROM solo_tickets').get() as any;
    expect(ticketsAfter.c).toBe(5);

    // Önceki biletlerin used durumunun değişmediğini doğrula (son bilet used=0 kalmalı)
    const lastTicket = ctx.rawDb
      .prepare('SELECT used FROM solo_tickets ORDER BY issued_at DESC LIMIT 1')
      .get() as any;
    expect(lastTicket.used).toBe(0);
  });

  it('3. Yeni bilet üretildiğinde: önceki kullanılmamış bilet terk edilmiş olarak kapatılır', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'ticket_user_abandon';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const now = Date.now();
    // 1. bilet
    const t1 = await profile.issueSoloTicket(uid, now - 5000);
    expect(t1.ok).toBe(true);

    const ctx = ctxMap.get(uid);
    const t1Row = ctx.rawDb.prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?').get(t1.ticketId!) as any;
    expect(t1Row.used).toBe(0);

    // 2. bilet üretilir (1. bilet kullanılmadan)
    const t2 = await profile.issueSoloTicket(uid, now - 1000);
    expect(t2.ok).toBe(true);

    // 1. bilet used=1 olmalı
    const t1RowAfter = ctx.rawDb
      .prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?')
      .get(t1.ticketId!) as any;
    expect(t1RowAfter.used).toBe(1);

    // 2. bilet used=0 olmalı
    const t2Row = ctx.rawDb.prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?').get(t2.ticketId!) as any;
    expect(t2Row.used).toBe(0);

    // Kullanıcının istatistikleri: played=1, won=0 (kayıp sayıldı)
    const profData = await profile.getProfile(uid, 0, undefined, now);
    expect(profData.stats.played).toBe(1);
    expect(profData.stats.won).toBe(0);
    expect(profData.currentStreak).toBe(0);
    expect(profData.coins).toBe(100); // Jeton verilmedi

    // processed_matches'te t1'in matchId'si solo_abandoned olarak yer almalı
    const matchRow = ctx.rawDb
      .prepare('SELECT outcome FROM processed_matches WHERE match_id = ?')
      .get(t1.matchId!) as any;
    expect(matchRow).toBeDefined();
    expect(matchRow.outcome).toBe('solo_abandoned');
  });

  it('4. Süresi dolan kullanılmamış biletler getProfile çağrıldığında terk edilmiş sayılır', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'ticket_user_expire';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const baseTime = Date.now();
    const t = await profile.issueSoloTicket(uid, baseTime - 16 * 60 * 1000);
    expect(t.ok).toBe(true);

    const ctx = ctxMap.get(uid);
    const rowBefore = ctx.rawDb.prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?').get(t.ticketId!) as any;
    expect(rowBefore.used).toBe(0);

    // 16 dakika sonra getProfile çağrılır
    const prof = await profile.getProfile(uid, 0, undefined, baseTime);
    expect(prof.stats.played).toBe(1);
    expect(prof.stats.won).toBe(0);

    const rowAfter = ctx.rawDb
      .prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?')
      .get(t.ticketId!) as any;
    expect(rowAfter.used).toBe(1);

    const matchRow = ctx.rawDb
      .prepare('SELECT outcome FROM processed_matches WHERE match_id = ?')
      .get(t.matchId!) as any;
    expect(matchRow.outcome).toBe('solo_abandoned');
  });
});

describe('Bilet Modeli - POST /matches/solo & applyBotMatchReward Doğrulamaları', () => {
  it('1. Geçerli bilet + maç sonucu işlenir, bilet used=1 olur, enerji İKİNCİ KEZ DÜŞÜLMEZ', async () => {
    const { env } = createEnv();
    const uid = 'match_user_valid';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const issuedAt = Date.now() - 25000;
    const ticket = await profile.issueSoloTicket(uid, issuedAt);
    expect(ticket.ok).toBe(true);
    expect(ticket.energy?.current).toBe(4);

    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        ticketId: ticket.ticketId,
        matchId: ticket.matchId,
        outcome: 'win',
        myScore: 2,
        oppScore: 1,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(200);
    const data = (await res.json()) as any;
    expect(data.ok).toBe(true);
    expect(data.counted).toBe(true);
    expect(data.coinsAwarded).toBe(30);
    expect(data.coins).toBe(130);
    expect(data.energy.current).toBe(4); // 4 olarak kaldı, ikinci kez düşülmedi!

    const p = await profile.getProfile(uid);
    expect(p.stats.played).toBe(1);
    expect(p.stats.won).toBe(1);
    expect(p.currentStreak).toBe(1);
  });

  it('2. Aynı match_id tekrar yollandığında idempotent 200 döner (bilet used=1 olsa bile)', async () => {
    const { env } = createEnv();
    const uid = 'match_user_idempotent';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const issuedAt = Date.now() - 25000;
    const ticket = await profile.issueSoloTicket(uid, issuedAt);

    const payload = {
      ticketId: ticket.ticketId,
      matchId: ticket.matchId,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 5,
      durationSeconds: 25,
      endedBy: 'normal',
    };

    const req1 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(payload),
    });

    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(200);

    // İkinci istek
    const req2 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify(payload),
    });

    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(200);
    const data2 = (await res2.json()) as any;
    expect(data2.ok).toBe(true);
    expect(data2.counted).toBe(true);
    expect(data2.alreadyProcessed).toBe(true);
    expect(data2.coinsAwarded).toBe(30);

    const p = await profile.getProfile(uid);
    expect(p.stats.played).toBe(1); // Çift sayılmadı
    expect(p.stats.won).toBe(1);
  });

  it('3. Bilet yoksa veya format geçersizse 400 döner', async () => {
    const { env } = createEnv();
    const uid = 'match_user_ticket_err';

    // Bilet eksik
    const req1 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        matchId: 'bot:somevalidid123456789012',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 4,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(400);
    const data1 = (await res1.json()) as any;
    expect(data1.error).toBe('ticket_required');

    // Bilet formatı geçersiz
    const req2 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        ticketId: 'invalid_ticket_id',
        matchId: 'bot:somevalidid123456789012',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 4,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(400);
    const data2 = (await res2.json()) as any;
    expect(data2.error).toBe('ticket_invalid');
  });

  it('4. Başka kullanıcının bileti veya match_id uyuşmazlığında 400 ticket_invalid döner', async () => {
    const { env } = createEnv();
    const userA = 'user_ticket_owner';
    const userB = 'user_ticket_thief';
    const profileA = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(userA)) as unknown as UserProfile;

    const ticketA = await profileA.issueSoloTicket(userA, Date.now() - 25000);

    // UserB, UserA'nın biletini kullanmaya çalışır
    const req1 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${userB}`,
      },
      body: JSON.stringify({
        ticketId: ticketA.ticketId,
        matchId: ticketA.matchId,
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });
    const res1 = await worker.fetch(req1, env);
    expect(res1.status).toBe(400);
    const data1 = (await res1.json()) as any;
    expect(data1.error).toBe('ticket_invalid');

    // UserA kendi biletini ama farklı bir matchId ile kullanmaya çalışır
    const req2 = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${userA}`,
      },
      body: JSON.stringify({
        ticketId: ticketA.ticketId,
        matchId: 'bot:othermatchid123456789012',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 25,
        endedBy: 'normal',
      }),
    });
    const res2 = await worker.fetch(req2, env);
    expect(res2.status).toBe(400);
    const data2 = (await res2.json()) as any;
    expect(data2.error).toBe('ticket_invalid');
  });

  it('5. Kullanılmış bilet için ticket_already_used, süresi dolmuş bilet için ticket_expired fırlatır', async () => {
    const { env } = createEnv();
    const uid = 'ticket_user_states';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    // Kullanılmış bilet testi
    const ticket1 = await profile.issueSoloTicket(uid, Date.now() - 30000);
    await profile.applyBotMatchReward({
      uid,
      ticketId: ticket1.ticketId!,
      matchId: ticket1.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 4,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    // ticket1'i farklı bir maç için tekrar sun
    await expect(
      profile.applyBotMatchReward({
        uid,
        ticketId: ticket1.ticketId!,
        matchId: 'bot:anothernewmatch12345678',
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 4,
        durationSeconds: 25,
        endedBy: 'normal',
      })
    ).rejects.toThrow('ticket_already_used');

    // Süresi dolmuş bilet testi (16 dakika önce üretilmiş)
    const oldTime = Date.now() - 16 * 60 * 1000;
    const ticketExpired = await profile.issueSoloTicket(uid, oldTime);
    await expect(
      profile.applyBotMatchReward({
        uid,
        ticketId: ticketExpired.ticketId!,
        matchId: ticketExpired.matchId!,
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 4,
        durationSeconds: 25,
        endedBy: 'normal',
      })
    ).rejects.toThrow('ticket_expired');
  });

  it('6. 20 saniyeden kısa sürede kazanılan maç 400 match_too_fast döner ve bilet used=0 kalır', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'speed_runner_user';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    // Bilet henüz 5 saniye önce üretildi
    const issuedAt = Date.now() - 5000;
    const ticket = await profile.issueSoloTicket(uid, issuedAt);

    const req = new Request('http://127.0.0.1/matches/solo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer dev:${uid}`,
      },
      body: JSON.stringify({
        ticketId: ticket.ticketId,
        matchId: ticket.matchId,
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 5,
        durationSeconds: 5,
        endedBy: 'normal',
      }),
    });

    const res = await worker.fetch(req, env);
    expect(res.status).toBe(400);
    const data = (await res.json()) as any;
    expect(data.error).toBe('match_too_fast');

    // Bilet used=0 olarak kalmalıdır
    const ctx = ctxMap.get(uid);
    const row = ctx.rawDb
      .prepare('SELECT used FROM solo_tickets WHERE ticket_id = ?')
      .get(ticket.ticketId!) as any;
    expect(row.used).toBe(0);

    // Kullanıcı sayacı artmamıştır
    const p = await profile.getProfile(uid);
    expect(p.stats.played).toBe(0);
  });
});

describe('Bilet Modeli - Jeton Tavanı (DAILY_MATCH_COIN_CAP = unlimited) & Güvenlik Tavanı (1000)', () => {
  it('unlimited modunda eski 300 jeton sınırına takılmaz, tüm jetonlar verilir', async () => {
    const { env } = createEnv({ DAILY_MATCH_COIN_CAP: 'unlimited', ENERGY_ENABLED: 'false' });
    const uid = 'unlimited_coin_user';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    let totalAwarded = 0;
    // 11 galibiyet: her biri 30 coin -> toplam 330 coin (eski 300 tavanını aşar)
    for (let i = 0; i < 11; i++) {
      const ticket = await profile.issueSoloTicket(uid, Date.now() - 30000);
      const res = await profile.applyBotMatchReward({
        uid,
        ticketId: ticket.ticketId!,
        matchId: ticket.matchId!,
        outcome: 'win',
        myScore: 2,
        oppScore: 0,
        correctAnswers: 4,
        durationSeconds: 25,
        endedBy: 'normal',
      });
      expect(res.ok).toBe(true);
      expect(res.coinsAwarded).toBe(30);
      totalAwarded += res.coinsAwarded!;
    }

    expect(totalAwarded).toBe(330);
    const prof = await profile.getProfile(uid);
    expect(prof.coins).toBe(100 + 330); // 100 başlangıç + 330
  });

  it('solo maçlarda günlük güvenlik tavanı 1000 maçtır (SOLO_DAILY_SAFETY_CAP)', async () => {
    const { env, ctxMap } = createEnv({ DAILY_MATCH_COIN_CAP: 'unlimited' });
    const uid = 'safety_cap_user';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    // Şemayı hazırla
    await profile.ensureSchema();

    // Günlük solo maç tablosuna doğrudan 1000 maç yazalım
    const ctx = ctxMap.get(uid);
    const today = new Date().toISOString().slice(0, 10);
    ctx.rawDb
      .prepare('INSERT INTO daily_solo_matches (day_key, count) VALUES (?, ?)')
      .run(today, 1000);

    const ticket = await profile.issueSoloTicket(uid, Date.now() - 30000);
    const res = await profile.applyBotMatchReward({
      uid,
      ticketId: ticket.ticketId!,
      matchId: ticket.matchId!,
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 4,
      durationSeconds: 25,
      endedBy: 'normal',
    });

    expect(res.ok).toBe(true);
    expect(res.counted).toBe(false);
    expect(res.coinsAwarded).toBe(0);
  });
});

describe('Bilet Modeli - Hesap Silme Uyumluluğu', () => {
  it('deleteProfile çağrıldığında solo_tickets tablosundaki kayıtlar silinir', async () => {
    const { env, ctxMap } = createEnv();
    const uid = 'delete_ticket_user';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    await profile.issueSoloTicket(uid, Date.now() - 25000);
    const ctx = ctxMap.get(uid);

    const countBefore = ctx.rawDb.prepare('SELECT COUNT(*) as c FROM solo_tickets').get() as any;
    expect(countBefore.c).toBe(1);

    await profile.deleteProfile(uid);

    const countAfter = ctx.rawDb.prepare('SELECT COUNT(*) as c FROM solo_tickets').get() as any;
    expect(countAfter.c).toBe(0);
  });
});

describe('Matchmaker Fallback & Yarış Durumu (Race Condition) Testleri', () => {
  it('supportsSoloTicket: true olan oyuncu 10 sn içinde eşleşmezse no_opponent + bilet alır', async () => {
    const { env } = createEnv();
    const mockState = createMockDOStateForMatchmaker();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const ws = createMockWs('p_solo_fallback');
    mockState.acceptWebSocket(ws, ['p_solo_fallback', 'ip:127.0.0.1']);

    await mm.webSocketMessage(
      ws,
      JSON.stringify({ t: 'queue', name: 'PlayerSolo', supportsSoloTicket: true })
    );

    // Alarm kurulduğunu doğrula
    expect(mockState.storage.setAlarm).toHaveBeenCalled();

    // 10 saniye sonra alarm tetiklenir
    vi.setSystemTime(Date.now() + 10100);
    try {
      await mm.alarm();

      const noOppMsg = ws.sentMessages.find((m) => m.includes('"no_opponent"'));
      expect(noOppMsg).toBeDefined();
      const parsed = JSON.parse(noOppMsg!);
      expect(parsed.t).toBe('no_opponent');
      expect(parsed.ticketId).toMatch(/^stk_[A-Za-z0-9_-]{24}$/);
      expect(parsed.matchId).toMatch(/^bot:[A-Za-z0-9_-]{24}$/);
      expect(parsed.energy.current).toBe(4);

      // Oyuncu kuyruktan çıkarılmış olmalıdır
      expect((mm as any).queue).toHaveLength(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it('supportsSoloTicket olmayan veya false olan oyuncu 10 sn zamanlayıcısı almaz, kuyrukta bekler', async () => {
    const { env } = createEnv();
    const mockState = createMockDOStateForMatchmaker();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const ws = createMockWs('p_normal');
    mockState.acceptWebSocket(ws, ['p_normal', 'ip:127.0.0.1']);

    await mm.webSocketMessage(
      ws,
      JSON.stringify({ t: 'queue', name: 'PlayerNormal' }) // supportsSoloTicket yok
    );

    // Alarm tetiklendiğinde bile no_opponent gönderilmez
    vi.setSystemTime(Date.now() + 10100);
    try {
      await mm.alarm();
      const noOppMsg = ws.sentMessages.find((m) => m.includes('"no_opponent"'));
      expect(noOppMsg).toBeUndefined();
      expect((mm as any).queue).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('oyuncu cancel gönderdiğinde veya bağlantı koptuğunda zamanlayıcı temizlenir', async () => {
    const { env } = createEnv();
    const mockState = createMockDOStateForMatchmaker();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const ws = createMockWs('p_canceler');
    mockState.acceptWebSocket(ws, ['p_canceler', 'ip:127.0.0.1']);

    await mm.webSocketMessage(
      ws,
      JSON.stringify({ t: 'queue', name: 'Canceler', supportsSoloTicket: true })
    );

    expect((mm as any).queue).toHaveLength(1);

    await mm.webSocketMessage(ws, JSON.stringify({ t: 'cancel' }));
    expect((mm as any).queue).toHaveLength(0);

    // Alarm tetiklense bile hiçbir mesaj gönderilmez
    vi.setSystemTime(Date.now() + 10100);
    try {
      await mm.alarm();
      expect(ws.sentMessages.filter((m) => m.includes('"no_opponent"'))).toHaveLength(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it('yarış durumu (Race Condition): 10. saniyede eşleşme gelirse çift işlem olmaz, eşleşme kazanır', async () => {
    const { env } = createEnv();
    const mockState = createMockDOStateForMatchmaker();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const ws1 = createMockWs('p_race_1');
    const ws2 = createMockWs('p_race_2');
    mockState.acceptWebSocket(ws1, ['p_race_1', 'ip:127.0.0.1']);
    mockState.acceptWebSocket(ws2, ['p_race_2', 'ip:127.0.0.1']);

    // p1 supportsSoloTicket: true ile girer
    await mm.webSocketMessage(
      ws1,
      JSON.stringify({ t: 'queue', name: 'Race1', supportsSoloTicket: true })
    );

    // Tam 10. saniyede p2 gelir ve eşleşir
    vi.setSystemTime(Date.now() + 9999);
    try {
      await mm.webSocketMessage(
        ws2,
        JSON.stringify({ t: 'queue', name: 'Race2' })
      );

      // p1 ve p2 matched mesajı alır
      const matched1 = ws1.sentMessages.find((m) => m.includes('"matched"'));
      const matched2 = ws2.sentMessages.find((m) => m.includes('"matched"'));
      expect(matched1).toBeDefined();
      expect(matched2).toBeDefined();

      // Alarm tetiklendiğinde kuyruk boş olduğundan p1 no_opponent ALMAZ
      await mm.alarm();
      const noOppMsg = ws1.sentMessages.find((m) => m.includes('"no_opponent"'));
      expect(noOppMsg).toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });

  it('enerjisi 0 olan oyuncu kuyrukta fallbacke ulaşırsa no_opponent { error: no_energy } alır', async () => {
    const { env } = createEnv();
    const mockState = createMockDOStateForMatchmaker();
    const mockProvider = {
      source: 'test' as const,
      getQuestions: vi.fn(async () => createDummyQuestions()),
    };

    const mm = new Matchmaker(mockState as any, env, mockProvider);
    const uid = 'p_zero_energy';
    const profile = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid)) as unknown as UserProfile;

    const ws = createMockWs(uid);
    mockState.acceptWebSocket(ws, [uid, 'ip:127.0.0.1']);

    await mm.webSocketMessage(
      ws,
      JSON.stringify({ t: 'queue', name: 'ZeroEnergyPlayer', supportsSoloTicket: true })
    );

    // Enerjiyi sıfırla (5 bilet alarak)
    for (let i = 0; i < 5; i++) {
      await profile.issueSoloTicket(uid, Date.now() + i * 10);
    }
    const energyNow = await profile.getEnergyState(uid);
    expect(energyNow.current).toBe(0);

    // Fallback alarmı tetiklenir
    vi.setSystemTime(Date.now() + 10100);
    try {
      await mm.alarm();

      const noOppMsg = ws.sentMessages.find((m) => m.includes('"no_opponent"'));
      expect(noOppMsg).toBeDefined();
      const parsed = JSON.parse(noOppMsg!);
      expect(parsed.t).toBe('no_opponent');
      expect(parsed.error).toBe('no_energy');
      expect(parsed.ticketId).toBeUndefined();
    } finally {
      vi.useRealTimers();
    }
  });
});
