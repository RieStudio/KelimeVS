import { describe, it, expect, vi } from 'vitest';
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

import { generateGuestNickname, resolveDisplayName } from '../src/displayName';
import { UserProfile } from '../src/userProfile';
import { Leaderboard } from '../src/leaderboard';
import { Matchmaker } from '../src/matchmaker';
import type { Env } from '../src/index';

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      if (
        trimmed.toUpperCase().startsWith('SELECT') ||
        trimmed.toUpperCase().startsWith('PRAGMA') ||
        trimmed.toUpperCase().startsWith('WITH')
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

  let alarmTime: number | null = null;
  const kv = new Map<string, any>();
  const storage = {
    sql,
    get: async <T>(key: string) => kv.get(key) as T | undefined,
    put: async (key: string, val: any) => {
      kv.set(key, val);
    },
    getAlarm: async () => alarmTime,
    setAlarm: async (time: number) => {
      alarmTime = time;
    },
    deleteAlarm: async () => {
      alarmTime = null;
    },
    deleteAll: async () => {
      kv.clear();
    },
    transactionSync: <T>(fn: () => T): T => fn(),
  };

  return {
    storage,
    db,
    blockConcurrencyWhile: async (fn: any) => fn(),
    getWebSockets: () => [],
    setWebSocketAutoResponse: () => {},
  } as unknown as DurableObjectState & { db: DatabaseSync };
}

function createEnv(overrides?: Partial<Env>): Env {
  return {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    LEADERBOARD: {} as any,
    REPORT_STORE: {} as any,
    START_COINS: '100',
    ALLOW_DEV_AUTH: 'true',
    CONTENT_SOURCE: 'dev',
    ...overrides,
  } as Env;
}

describe('Guest Display Name Consistency (Tek Kaynak Doğrulaması)', () => {
  describe('1. resolveDisplayName Unit Tests', () => {
    it('Misafir kullanıcı (isGuest: true) için deterministik M-#### üretilir', () => {
      const uid = 'guest_user_abc_123';
      const expected = generateGuestNickname(uid);
      expect(expected).toMatch(/^M-[1-9]\d{3}$/);

      // Takma ad yokken
      expect(resolveDisplayName({ uid, isGuest: true })).toBe(expected);
      expect(resolveDisplayName({ uid, nickname: null, isGuest: true })).toBe(expected);
      expect(resolveDisplayName({ uid, nickname: '', isGuest: true })).toBe(expected);
      expect(resolveDisplayName({ uid, nickname: '   ', isGuest: true })).toBe(expected);

      // Takma ad hatalı olarak 'Oyuncu' geçilmiş olsa bile misafir için M-#### düzeltilir
      expect(resolveDisplayName({ uid, nickname: 'Oyuncu', isGuest: true })).toBe(expected);

      // Takma ad zaten geçerli M-#### ise korunur
      expect(resolveDisplayName({ uid, nickname: 'M-5432', isGuest: true })).toBe('M-5432');
    });

    it('Google kullanıcısı (isGuest: false) kendi özel adını korur, ad yoksa "Oyuncu" döner', () => {
      expect(resolveDisplayName({ uid: 'google_u1', nickname: 'Zeynep', isGuest: false })).toBe('Zeynep');
      expect(resolveDisplayName({ uid: 'google_u1', nickname: null, isGuest: false })).toBe('Oyuncu');
      expect(resolveDisplayName({ uid: 'google_u1', nickname: '', isGuest: false })).toBe('Oyuncu');
    });

    it('isGuest belirtilmediğinde: özel ad korunur, "Oyuncu" veya boşlukta uid varsa M-#### üretilir', () => {
      const uid = 'anon_uid_456';
      const expected = generateGuestNickname(uid);

      // Özel ad
      expect(resolveDisplayName({ uid, nickname: 'Mehmet' })).toBe('Mehmet');

      // 'Oyuncu' fallback'i gelmişse ve uid biliniyorsa uid'den M-#### türetir
      expect(resolveDisplayName({ uid, nickname: 'Oyuncu' })).toBe(expected);

      // Ad hiç yoksa ve uid biliniyorsa uid'den M-#### türetir
      expect(resolveDisplayName({ uid, nickname: null })).toBe(expected);
      expect(resolveDisplayName({ uid, nickname: '' })).toBe(expected);

      // Hem ad hem uid yoksa yalnızca o zaman 'Oyuncu' döner
      expect(resolveDisplayName({})).toBe('Oyuncu');
      expect(resolveDisplayName({ nickname: null, uid: null })).toBe('Oyuncu');
    });
  });

  describe('2. Public Profile Yüzeyi (GET /users/:uid/public)', () => {
    it('Misafir kullanıcının profili M-#### döner ve asla "Oyuncu" dönmez', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profile = new UserProfile(ctx, env);

      const guestUid = 'guest_public_test_1';
      await profile.getProfile(guestUid, 0, true);

      const pub = await profile.getPublicProfile();
      expect(pub.kind).toBe('ok');
      if (pub.kind !== 'ok') return;

      expect(pub.profile.isGuest).toBe(true);
      expect(pub.profile.nickname).toBe(generateGuestNickname(guestUid));
      expect(pub.profile.nickname).not.toBe('Oyuncu');
    });

    it('DB içinde takma adı null kalmış misafir profilinde de M-#### üretilir', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profile = new UserProfile(ctx, env);

      const guestUid = 'guest_null_nick_2';
      // profiles tablosuna doğrudan is_guest=1 ve nickname=NULL satırı yaz
      ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS profiles (
          uid TEXT PRIMARY KEY,
          nickname TEXT,
          coins INTEGER NOT NULL,
          played INTEGER NOT NULL DEFAULT 0,
          won INTEGER NOT NULL DEFAULT 0,
          lost INTEGER NOT NULL DEFAULT 0,
          correct_answers INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          equipped_frame TEXT NOT NULL DEFAULT 'classic',
          is_guest INTEGER NOT NULL DEFAULT 1,
          is_system_nickname INTEGER NOT NULL DEFAULT 1
        );
        INSERT INTO profiles (uid, nickname, coins, is_guest, is_system_nickname, created_at)
        VALUES ('${guestUid}', NULL, 100, 1, 1, 1000);
      `);

      const pub = await profile.getPublicProfile();
      expect(pub.kind).toBe('ok');
      if (pub.kind !== 'ok') return;

      expect(pub.profile.isGuest).toBe(true);
      expect(pub.profile.nickname).toBe(generateGuestNickname(guestUid));
      expect(pub.profile.nickname).not.toBe('Oyuncu');
    });
  });

  describe('3. Matchmaking & Maç Mesajları Yüzeyi', () => {
    it('Matchmaker misafir oyuncunun adını M-#### olarak çözümler (sanitizePlayerName ezmesi yaşanmaz)', async () => {
      const ctx = createMockCtx();
      const guestUid = 'guest_mm_user_77';
      const expectedName = generateGuestNickname(guestUid);

      const profileCtx = createMockCtx();
      const env = createEnv();
      const profileDO = new UserProfile(profileCtx, env);
      await profileDO.getProfile(guestUid, 0, true);

      const userProfileNamespace = {
        idFromName(_name: string) {
          return { toString: () => `id_${guestUid}` };
        },
        get(_id: any) {
          return profileDO;
        },
      } as any;

      const mmEnv = createEnv({
        USER_PROFILE: userProfileNamespace,
      });

      const mm = new Matchmaker(ctx, mmEnv);

      // getPlayerInfo doğrudan private metod olduğu için createDirectMatch ile test edelim
      let passedP1Name = '';
      const roomStub = {
        initMatch: async (params: any) => {
          passedP1Name = params.p1.name;
        },
      };

      const matchRoomNamespace = {
        idFromName(_id: string) {
          return { toString: () => 'm1' };
        },
        get(_id: any) {
          return roomStub;
        },
      } as any;

      (mm as any).env.MATCH_ROOM = matchRoomNamespace;

      const directRes = await mm.createDirectMatch({
        p1: { uid: guestUid, name: 'Oyuncu', frame: 'classic' }, // 'Oyuncu' gelse bile uid'den M-#### üretilir
        p2: { uid: 'google_p2', name: 'GoogleOyuncu', frame: 'classic' },
        matchType: 'friendly',
        prevMatchId: '',
        proposerUid: guestUid,
      });

      expect(directRes.ok).toBe(true);
      expect(passedP1Name).toBe(expectedName);
      expect(passedP1Name).not.toBe('Oyuncu');
    });
  });

  describe('4. Maç İsteği (Match Request) Yüzeyi', () => {
    it('Misafir kullanıcı maç isteği aldığında veya gönderdiğinde takma ad M-#### döner', async () => {
      const ctxSender = createMockCtx();
      const ctxReceiver = createMockCtx();
      (ctxReceiver as any).getWebSockets = () => [{ send: () => {} }];
      const env = createEnv();

      const senderDO = new UserProfile(ctxSender, env);
      const receiverDO = new UserProfile(ctxReceiver, env);

      const guestSenderUid = 'guest_sender_101';
      const guestReceiverUid = 'guest_receiver_202';

      await senderDO.getProfile(guestSenderUid, 0, true);
      await receiverDO.getProfile(guestReceiverUid, 0, true);

      // Alıcı DO'suna istek gönderildiğinde dönen receiverNickname M-#### olmalı
      const res = await receiverDO.receiveMatchRequest({
        senderUid: guestSenderUid,
        senderNickname: generateGuestNickname(guestSenderUid),
        senderFrame: 'classic',
        type: 'friendly',
        origin: 'profile',
      });

      expect(res.ok).toBe(true);
      expect(res.receiverNickname).toBe(generateGuestNickname(guestReceiverUid));
      expect(res.receiverNickname).not.toBe('Oyuncu');
    });
  });

  describe('5. Sıralama (Leaderboard) Yüzeyi', () => {
    it('Misafir oyuncu maç kazandığında liderlik tablosuna M-#### adıyla girer', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const lb = new Leaderboard(ctx, env);
      const nowMs = Date.now();

      const guestWinnerUid = 'guest_winner_303';
      const expectedName = generateGuestNickname(guestWinnerUid);

      // 'Oyuncu' veya M-#### takma adı ile sonuç kaydedildiğinde
      await lb.recordMatchResult({
        matchId: 'm_guest_win',
        winnerUid: guestWinnerUid,
        winnerNickname: 'Oyuncu', // Önceden 'Oyuncu' gönderilse bile uid'den M-#### üretilir
        loserUid: 'google_loser',
        loserNickname: 'GoogleKaybeden',
        finishedAtMs: nowMs,
      });

      const res = await lb.getLeaderboard(guestWinnerUid, nowMs);
      expect(res.top.length).toBeGreaterThan(0);
      const entry = res.top.find((e) => e.uid === guestWinnerUid);
      expect(entry).toBeDefined();
      expect(entry?.nickname).toBe(expectedName);
      expect(entry?.nickname).not.toBe('Oyuncu');
    });
  });

  describe('6. Engellenenler Listesi (Blocked Users) Yüzeyi', () => {
    it('Misafir kullanıcı engellendiğinde getBlockedUsers M-#### takma adı döndürür', async () => {
      const ctx = createMockCtx();
      const env = createEnv();
      const profile = new UserProfile(ctx, env);

      const callerUid = 'caller_google_user';
      const guestBlockedUid = 'guest_blocked_404';
      const expectedName = generateGuestNickname(guestBlockedUid);

      await profile.getProfile(callerUid, 0, false);

      // Engelleme sırasında hatalı bir şekilde 'Oyuncu' kaydedilmiş olsa bile
      await profile.blockUser({
        uid: callerUid,
        blockedUid: guestBlockedUid,
        blockedNickname: 'Oyuncu',
      });

      const list = await profile.getBlockedUsers();
      expect(list.length).toBe(1);
      expect(list[0].nickname).toBe(expectedName);
      expect(list[0].nickname).not.toBe('Oyuncu');
    });
  });
});
