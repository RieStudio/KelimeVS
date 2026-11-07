import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

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

import { MatchEngine, type Question } from '../src/engine';
import { MatchRoom } from '../src/matchRoom';
import { deserializeMatchState } from '../src/storage';
import type { Env } from '../src/index';

const sampleQuestions: Question[] = [
  {
    id: 'q1',
    categoryId: 'c1',
    text: 'Soru 1',
    answers: [{ id: 'a1', display: 'Ankara', aliases: ['ankara'] }],
  },
  {
    id: 'q2',
    categoryId: 'c1',
    text: 'Soru 2',
    answers: [{ id: 'a2', display: 'İstanbul', aliases: ['istanbul'] }],
  },
  {
    id: 'q3',
    categoryId: 'c1',
    text: 'Soru 3',
    answers: [{ id: 'a3', display: 'İzmir', aliases: ['izmir'] }],
  },
];

function createMockSocket(tag: string, sent: any[] = []) {
  let attachment: any = null;
  let closed = false;
  let closeCode: number | null = null;
  let closeReason: string | null = null;

  return {
    tag,
    sent,
    get readyState() {
      return closed ? 2 : 1;
    },
    send: (data: string) => sent.push(JSON.parse(data)),
    deserializeAttachment: () => attachment,
    serializeAttachment: (val: any) => {
      attachment = val;
    },
    close: (code = 1000, reason = '') => {
      closed = true;
      closeCode = code;
      closeReason = reason;
    },
    get isClosed() {
      return closed;
    },
    get closeCode() {
      return closeCode;
    },
    get closeReason() {
      return closeReason;
    },
  };
}

function createMockRoomCtx() {
  const store = new Map<string, any>();
  const sockets: any[] = [];
  let alarmTime: number | null = null;
  let deleteAlarmCallCount = 0;

  return {
    ctx: {
      storage: {
        async get(key: string) {
          return store.get(key);
        },
        async put(key: string, val: any) {
          store.set(key, val);
        },
        async delete(key: string) {
          store.delete(key);
        },
        async deleteAll() {
          store.clear();
        },
        async setAlarm(time: number) {
          alarmTime = time;
        },
        async getAlarm() {
          return alarmTime;
        },
        async deleteAlarm() {
          alarmTime = null;
          deleteAlarmCallCount++;
        },
      },
      acceptWebSocket(ws: any, tags: string[]) {
        (ws as any)._tags = tags;
        sockets.push(ws);
      },
      getWebSockets(tag?: string) {
        if (!tag) return sockets.filter((s) => !s.isClosed);
        return sockets.filter((s) => !s.isClosed && (s as any)._tags?.includes(tag));
      },
      getTags(ws: any) {
        return (ws as any)._tags ?? [];
      },
      blockConcurrencyWhile: async (fn: () => Promise<void>) => fn(),
    },
    store,
    sockets,
    getAlarmTime: () => alarmTime,
    getDeleteAlarmCallCount: () => deleteAlarmCallCount,
  };
}

describe('MatchRoom Exact-Time Alarm & Self-Heal Tests (Madde 6)', () => {
  const t0 = 10000;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(t0);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('6a) Tam vadesinde alarm: vi.setSystemTime(alarmTime) tam eşitlikte tur roundEnded olur ve nextRoundAtMs kurulur', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as unknown as Env;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_exact',
      p1: { uid: 'p1', name: 'Player 1' },
      p2: { uid: 'p2', name: 'Player 2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    ctx.acceptWebSocket(ws1, ['p1']);
    ctx.acceptWebSocket(ws2, ['p2']);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // 1. Tur başladı: 15s cevap + 400ms grace = 15400ms -> vadesi: t0 + 15400 = 25400
    const alarmTime = getAlarmTime();
    expect(alarmTime).toBe(t0 + 15400);

    // EKSTRA MS YOK: Tam alarm vadesine gidilir (nowMs === turnDeadlineMs)
    vi.setSystemTime(alarmTime!);
    await room.alarm();

    const roomData = (room as any).data;
    expect(roomData.status).toBe('active');

    const state = deserializeMatchState(roomData.engineState);
    expect(state.phase).toBe('roundEnded');
    expect(state.scores['p2']).toBe(1); // p1 süresi doldu, p2 kazandı

    // Takvimde turnDeadlineMs temizlenmiş, nextRoundAtMs kurulmuş olmalı
    expect(roomData.schedule.turnDeadlineMs).toBeUndefined();
    expect(roomData.schedule.nextRoundAtMs).toBe(alarmTime! + 3500);
    expect(getAlarmTime()).toBe(roomData.schedule.nextRoundAtMs);
  });

  it('6b) Self-heal: checkTimeout süre dolmamış gibi davranırsa (roundActive kalırsa) turnDeadlineMs takvime geri yazılır ve alarm kurulur', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as unknown as Env;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_self_heal',
      p1: { uid: 'p1', name: 'Player 1' },
      p2: { uid: 'p2', name: 'Player 2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    ctx.acceptWebSocket(ws1, ['p1']);
    ctx.acceptWebSocket(ws2, ['p2']);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    const alarmTime = getAlarmTime()!;
    expect(alarmTime).toBe(t0 + 15400);

    // checkTimeout'un süre dolmadı dediği senaryoyu simüle et (örneğin motor roundActive dönsün)
    const checkTimeoutSpy = vi.spyOn(MatchEngine, 'checkTimeout').mockImplementation(({ state }) => {
      return { state, events: [] };
    });

    vi.setSystemTime(alarmTime);
    await room.alarm();

    expect(checkTimeoutSpy).toHaveBeenCalled();

    const roomData = (room as any).data;
    const state = deserializeMatchState(roomData.engineState);
    expect(state.phase).toBe('roundActive');

    // Self-heal: takvimde turnDeadlineMs ASLA undefined kalmamalı, kurtarma vadesi atanmalı
    expect(roomData.schedule.turnDeadlineMs).toBeDefined();
    expect(roomData.schedule.turnDeadlineMs).toBe(alarmTime + 50); // targetDeadline <= nowMs olduğundan nowMs + 50
    expect(getAlarmTime()).toBe(roomData.schedule.turnDeadlineMs);
  });

  it('6c) roundEnded fazında geç gelen submit mesajı nextRoundAtMs değerini DEĞİŞTİRMEMELİ ve ertelememeli', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as unknown as Env;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_late_submit',
      p1: { uid: 'p1', name: 'Player 1' },
      p2: { uid: 'p2', name: 'Player 2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    ctx.acceptWebSocket(ws1, ['p1']);
    ctx.acceptWebSocket(ws2, ['p2']);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1 süresi dolar -> roundEnded fazına geçer
    const alarmTime = getAlarmTime()!;
    vi.setSystemTime(alarmTime);
    await room.alarm();

    const roomDataBefore = (room as any).data;
    const initialNextRoundAtMs = roomDataBefore.schedule.nextRoundAtMs;
    expect(initialNextRoundAtMs).toBe(alarmTime + 3500);

    // 1 saniye sonra oyuncudan geç gelen submit ulaşır
    vi.setSystemTime(alarmTime + 1000);
    await room.webSocketMessage(ws1 as any, JSON.stringify({ t: 'submit', text: 'gec_cevap' }));

    const roomDataAfter = (room as any).data;
    // nextRoundAtMs kesinlikle değişmemeli (3.5s yeniden başlamamalı)
    expect(roomDataAfter.schedule.nextRoundAtMs).toBe(initialNextRoundAtMs);
  });

  it('6d) roundEnded fazında geç tetiklenen turnTimeout alarmı nextRoundAtMs değerini ÖTELEYİP BAŞA SARMAMALI', async () => {
    const { ctx, getAlarmTime } = createMockRoomCtx();
    const env = {
      FAST_TIMERS: 'false',
      TURN_GRACE_MS: '400',
    } as unknown as Env;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_late_alarm',
      p1: { uid: 'p1', name: 'Player 1' },
      p2: { uid: 'p2', name: 'Player 2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
    });

    const ws1 = createMockSocket('p1');
    const ws2 = createMockSocket('p2');
    ctx.acceptWebSocket(ws1, ['p1']);
    ctx.acceptWebSocket(ws2, ['p2']);

    await (room as any).handlePlayerConnected('p1');
    await (room as any).handlePlayerConnected('p2');

    // Tur 1 biter -> roundEnded fazı ve nextRoundAtMs kurulur
    const alarmTime = getAlarmTime()!;
    vi.setSystemTime(alarmTime);
    await room.alarm();

    const initialNextRoundAtMs = (room as any).data.schedule.nextRoundAtMs;
    expect(initialNextRoundAtMs).toBe(alarmTime + 3500);

    // 1000 ms sonra geç bir turnTimeout takvimde kalsa ve alarm() çağrılsa bile
    vi.setSystemTime(alarmTime + 1000);
    (room as any).data = {
      ...(room as any).data,
      schedule: {
        ...(room as any).data.schedule,
        turnDeadlineMs: alarmTime + 1000,
      },
    };

    await room.alarm();

    const postAlarmData = (room as any).data;
    // nextRoundAtMs orijinal değerini korumalı, ötelenmemeli
    expect(postAlarmData.schedule.nextRoundAtMs).toBe(initialNextRoundAtMs);
  });

  it('6e) updateAlarm null durumunda ctx.storage.deleteAlarm çağrılmalıdır', async () => {
    const { ctx, getAlarmTime, getDeleteAlarmCallCount } = createMockRoomCtx();
    const env = {
      FAST_TIMERS: 'false',
    } as unknown as Env;

    const room = new MatchRoom(ctx as any, env);
    await room.initMatch({
      matchId: 'm_delete_alarm',
      p1: { uid: 'p1', name: 'Player 1' },
      p2: { uid: 'p2', name: 'Player 2' },
      questions: sampleQuestions,
      questionOrder: ['q1', 'q2', 'q3'],
      matchType: 'ranked',
    });

    expect(getAlarmTime()).toBeDefined();

    // Takvimdeki tüm zamanlayıcıları temizle
    (room as any).data = {
      ...(room as any).data,
      schedule: {},
    };

    await (room as any).updateAlarm();

    // deleteAlarm çağrılmış olmalı ve getAlarmTime null olmalı
    expect(getDeleteAlarmCallCount()).toBeGreaterThan(0);
    expect(getAlarmTime()).toBeNull();
  });
});

