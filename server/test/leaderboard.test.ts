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

import { Leaderboard, getIstanbulWeekInfo } from '../src/leaderboard';
import type { Env } from '../src/index';

function createMockCtx() {
  const db = new DatabaseSync(':memory:');
  let currentAlarm: number | null = null;

  const sql = {
    exec<T extends Record<string, any>>(query: string, ...bindings: any[]) {
      const trimmed = query.trim();
      if (trimmed.toUpperCase().startsWith('SELECT') || trimmed.toUpperCase().startsWith('WITH')) {
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

  const storage = {
    sql,
    getAlarm: async () => currentAlarm,
    setAlarm: async (time: number) => {
      currentAlarm = time;
    },
    deleteAlarm: async () => {
      currentAlarm = null;
    },
  };

  return { storage } as unknown as DurableObjectState;
}

function createEnv(): Env {
  return {
    MATCHMAKER: {} as any,
    MATCH_ROOM: {} as any,
    USER_PROFILE: {} as any,
    LEADERBOARD: {} as any,
  };
}

describe('Leaderboard - getIstanbulWeekInfo (Europe/Istanbul Hafta Hesaplama)', () => {
  it('1. Pazar 23:59:59.999 ile Pazartesi 00:00:00.000 hafta geçişini doğru ayırır', () => {
    // 18 Ekim 2026 Pazar 23:59:59 Istanbul (UTC+3 -> 20:59:59.999 UTC)
    const sunNight = new Date('2026-10-18T20:59:59.999Z');
    const sunInfo = getIstanbulWeekInfo(sunNight);
    expect(sunInfo.weekKey).toBe('2026-W42');

    // 19 Ekim 2026 Pazartesi 00:00:00 Istanbul (UTC+3 -> 20:59:59.999 UTC'den 1 ms sonra: 21:00:00.000Z)
    const monMidnight = new Date('2026-10-18T21:00:00.000Z');
    const monInfo = getIstanbulWeekInfo(monMidnight);
    expect(monInfo.weekKey).toBe('2026-W43');

    // sunInfo'nun endsAtMs değeri tam olarak monMidnight anıdır
    expect(sunInfo.endsAtMs).toBe(monMidnight.getTime());
  });

  it('2. Çarşamba günü haftanın başlangıç ve bitişini doğru verir', () => {
    // 14 Ekim 2026 Çarşamba 12:00:00 UTC
    const wed = new Date('2026-10-14T12:00:00.000Z');
    const info = getIstanbulWeekInfo(wed);
    expect(info.weekKey).toBe('2026-W42');

    // Pazartesi 00:00 Istanbul = 11 Ekim 21:00:00 UTC
    const expectedStart = new Date('2026-10-11T21:00:00.000Z').getTime();
    const expectedEnd = new Date('2026-10-18T21:00:00.000Z').getTime();
    expect(info.startOfWeekMs).toBe(expectedStart);
    expect(info.endsAtMs).toBe(expectedEnd);
  });
});

describe('Leaderboard Durable Object - SQLite, Eşitlik Sıralaması, Anti-Farming & Filtreler', () => {
  it('1. Boş tabloda top boş liste ve me null döner (empty state)', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);

    const res = await lb.getLeaderboard('user_alice');
    expect(res.top).toEqual([]);
    expect(res.me).toBeNull();
    expect(res.weekKey).toBeDefined();
    expect(res.endsAt).toBeGreaterThan(Date.now() - 1000);
  });

  it('2. Takma adı olmayan oyuncu veya 0 galibiyeti olan oyuncu listeye girmez, me null döner', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = new Date('2026-10-14T12:00:00Z').getTime();

    // Takma adı null olan oyuncu maç kazandı
    await lb.recordMatchResult({
      matchId: 'm1',
      winnerUid: 'anon_winner',
      winnerNickname: null,
      loserUid: 'loser_1',
      loserNickname: 'Kaybeden_1',
      finishedAtMs: nowMs,
    });

    const resAnon = await lb.getLeaderboard('anon_winner', nowMs);
    expect(resAnon.top).toHaveLength(0);
    expect(resAnon.me).toBeNull();

    // loser_1 sadece mağlubiyet aldı (wins = 0)
    const resLoser = await lb.getLeaderboard('loser_1', nowMs);
    expect(resLoser.top).toHaveLength(0);
    expect(resLoser.me).toBeNull();
  });

  it('3. Sıralama ve eşitlik kuralları (wins DESC, losses ASC, reached_at ASC)', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const baseTime = new Date('2026-10-14T10:00:00Z').getTime();

    // A: 2 galibiyet, 1 mağlubiyet
    // B: 2 galibiyet, 0 mağlubiyet -> daha az mağlubiyet (B > A)
    // C: 2 galibiyet, 1 mağlubiyet -> A'dan 10 dakika sonra ulaştı (A > C)
    // D: 1 galibiyet -> (D en son)

    // A 1. galibiyet
    await lb.recordMatchResult({
      matchId: 'm_a1',
      winnerUid: 'uid_a',
      winnerNickname: 'Oyuncu_A',
      loserUid: 'uid_dummy1',
      loserNickname: 'Dummy1',
      finishedAtMs: baseTime,
    });
    // A 1 mağlubiyet
    await lb.recordMatchResult({
      matchId: 'm_a_loss',
      winnerUid: 'uid_dummy2',
      winnerNickname: 'Dummy2',
      loserUid: 'uid_a',
      loserNickname: 'Oyuncu_A',
      finishedAtMs: baseTime + 1000,
    });
    // A 2. galibiyet (reached_at = baseTime + 5000)
    await lb.recordMatchResult({
      matchId: 'm_a2',
      winnerUid: 'uid_a',
      winnerNickname: 'Oyuncu_A',
      loserUid: 'uid_dummy3',
      loserNickname: 'Dummy3',
      finishedAtMs: baseTime + 5000,
    });

    // B 2 galibiyet, 0 mağlubiyet
    await lb.recordMatchResult({
      matchId: 'm_b1',
      winnerUid: 'uid_b',
      winnerNickname: 'Oyuncu_B',
      loserUid: 'uid_dummy1',
      loserNickname: 'Dummy1',
      finishedAtMs: baseTime + 2000,
    });
    await lb.recordMatchResult({
      matchId: 'm_b2',
      winnerUid: 'uid_b',
      winnerNickname: 'Oyuncu_B',
      loserUid: 'uid_dummy2',
      loserNickname: 'Dummy2',
      finishedAtMs: baseTime + 8000,
    });

    // C 2 galibiyet, 1 mağlubiyet (2. galibiyete A'dan sonra ulaştı: baseTime + 10000)
    await lb.recordMatchResult({
      matchId: 'm_c_loss',
      winnerUid: 'uid_dummy1',
      winnerNickname: 'Dummy1',
      loserUid: 'uid_c',
      loserNickname: 'Oyuncu_C',
      finishedAtMs: baseTime + 1000,
    });
    await lb.recordMatchResult({
      matchId: 'm_c1',
      winnerUid: 'uid_c',
      winnerNickname: 'Oyuncu_C',
      loserUid: 'uid_dummy4',
      loserNickname: 'Dummy4',
      finishedAtMs: baseTime + 3000,
    });
    await lb.recordMatchResult({
      matchId: 'm_c2',
      winnerUid: 'uid_c',
      winnerNickname: 'Oyuncu_C',
      loserUid: 'uid_dummy5',
      loserNickname: 'Dummy5',
      finishedAtMs: baseTime + 10000,
    });

    // D 1 galibiyet
    await lb.recordMatchResult({
      matchId: 'm_d1',
      winnerUid: 'uid_d',
      winnerNickname: 'Oyuncu_D',
      loserUid: 'uid_dummy6',
      loserNickname: 'Dummy6',
      finishedAtMs: baseTime + 4000,
    });

    const res = await lb.getLeaderboard('uid_a', baseTime + 20000);
    // Dummy'ler de wins>0 ise tabloda yer alabilir, ilk 3 sıraya bakalım:
    // 2 galibiyetliler: B (0 loss), A (1 loss, reached earlier), C (1 loss, reached later)
    const topNicks = res.top.map((r) => r.nickname);
    expect(topNicks.slice(0, 3)).toEqual(['Oyuncu_B', 'Oyuncu_A', 'Oyuncu_C']);

    // Rütbeler
    expect(res.top[0].rank).toBe(1);
    expect(res.top[0].nickname).toBe('Oyuncu_B');
    expect(res.top[0].isMe).toBe(false);

    expect(res.top[1].rank).toBe(2);
    expect(res.top[1].nickname).toBe('Oyuncu_A');
    expect(res.top[1].isMe).toBe(true);

    expect(res.top[2].rank).toBe(3);
    expect(res.top[2].nickname).toBe('Oyuncu_C');
    expect(res.top[2].isMe).toBe(false);

    // me doğrulaması
    expect(res.me).toEqual({ rank: 2, wins: 2 });
  });

  it('4. Anti-farming kuralı: Aynı rakibe karşı haftada en fazla 3 galibiyet yazılır', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const baseTime = new Date('2026-10-14T12:00:00Z').getTime();

    // A, B'yi 1., 2. ve 3. kez yeniyor
    for (let i = 1; i <= 3; i++) {
      const res = await lb.recordMatchResult({
        matchId: `farm_${i}`,
        winnerUid: 'uid_farmer',
        winnerNickname: 'Farmer',
        loserUid: 'uid_alt',
        loserNickname: 'AltAcc',
        finishedAtMs: baseTime + i * 1000,
      });
      expect(res.capped).toBe(false);
    }

    let check = await lb.getLeaderboard('uid_farmer', baseTime + 4000);
    expect(check.me?.wins).toBe(3);

    // 4. galibiyet aynı rakibe karşı -> capped
    const res4 = await lb.recordMatchResult({
      matchId: 'farm_4',
      winnerUid: 'uid_farmer',
      winnerNickname: 'Farmer',
      loserUid: 'uid_alt',
      loserNickname: 'AltAcc',
      finishedAtMs: baseTime + 5000,
    });
    expect(res4.capped).toBe(true);

    check = await lb.getLeaderboard('uid_farmer', baseTime + 6000);
    expect(check.me?.wins).toBe(3); // Galibiyet 3'te kalır!

    // Farklı bir rakibe karşı galibiyet -> artar
    const resDifferent = await lb.recordMatchResult({
      matchId: 'diff_1',
      winnerUid: 'uid_farmer',
      winnerNickname: 'Farmer',
      loserUid: 'uid_other',
      loserNickname: 'OtherPlayer',
      finishedAtMs: baseTime + 7000,
    });
    expect(resDifferent.capped).toBe(false);

    check = await lb.getLeaderboard('uid_farmer', baseTime + 8000);
    expect(check.me?.wins).toBe(4);
  });

  it('5. İdempotentlik: Aynı matchId ikinci kez sayılmaz', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = Date.now();

    const r1 = await lb.recordMatchResult({
      matchId: 'idem_match_1',
      winnerUid: 'user_1',
      winnerNickname: 'Ali',
      loserUid: 'user_2',
      loserNickname: 'Veli',
      finishedAtMs: nowMs,
    });
    expect(r1.alreadyProcessed).toBeUndefined();

    const r2 = await lb.recordMatchResult({
      matchId: 'idem_match_1',
      winnerUid: 'user_1',
      winnerNickname: 'Ali',
      loserUid: 'user_2',
      loserNickname: 'Veli',
      finishedAtMs: nowMs,
    });
    expect(r2.alreadyProcessed).toBe(true);

    const check = await lb.getLeaderboard('user_1', nowMs);
    expect(check.me?.wins).toBe(1);
  });

  it('6. updateNickname kullanıcının mevcut tablodaki adını günceller', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = Date.now();

    await lb.recordMatchResult({
      matchId: 'rename_m1',
      winnerUid: 'u_rename',
      winnerNickname: 'EskiAd',
      loserUid: 'u_opp',
      loserNickname: 'Rakip',
      finishedAtMs: nowMs,
    });

    let data = await lb.getLeaderboard('u_rename', nowMs);
    expect(data.top[0].nickname).toBe('EskiAd');

    await lb.updateNickname('u_rename', 'YeniHarikaAd');

    data = await lb.getLeaderboard('u_rename', nowMs);
    expect(data.top[0].nickname).toBe('YeniHarikaAd');
  });

  it('7. İlk 50 dışındaki kullanıcı için me sırası doğru hesaplanır', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const baseTime = new Date('2026-10-14T12:00:00Z').getTime();

    // 55 farklı kullanıcıya galibiyet yazalım
    // user_1 .. user_50: 10 galibiyet
    // user_51 .. user_55: 1 galibiyet
    for (let i = 1; i <= 50; i++) {
      await lb.recordMatchResult({
        matchId: `top_${i}`,
        winnerUid: `uid_${i}`,
        winnerNickname: `Player_${i}`,
        loserUid: 'dummy_loser',
        loserNickname: 'Loser',
        finishedAtMs: baseTime + i * 10,
      });
    }

    // caller: user_53
    for (let i = 51; i <= 55; i++) {
      await lb.recordMatchResult({
        matchId: `low_${i}`,
        winnerUid: `uid_${i}`,
        winnerNickname: `Low_${i}`,
        loserUid: 'dummy_loser',
        loserNickname: 'Loser',
        finishedAtMs: baseTime + 1000 + i * 10,
      });
    }

    const res = await lb.getLeaderboard('uid_53', baseTime + 5000);
    // top uzunluğu en fazla 50 olmalıdır
    expect(res.top).toHaveLength(50);
    // top listesinde uid_53 olmamalıdır
    expect(res.top.some((e) => e.nickname === 'Low_53')).toBe(false);
    // me nesnesi 53. sırada olduğunu ve 1 galibiyeti olduğunu göstermelidir
    expect(res.me).toEqual({
      rank: 53,
      wins: 1,
    });
  });

  it('8. cleanupOldData 14 günden eski processed_matches ve 8 haftadan eski week_wins temizler', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = new Date('2026-10-18T12:00:00Z').getTime();

    // 20 gün öncesine ait maç
    const oldTime = nowMs - 20 * 86400 * 1000;
    await lb.recordMatchResult({
      matchId: 'very_old_match',
      winnerUid: 'uid_old',
      winnerNickname: 'Oldie',
      loserUid: 'uid_old2',
      loserNickname: 'Oldie2',
      finishedAtMs: oldTime,
    });

    // 10 hafta öncesine ait hafta verisi ekleyelim
    const tenWeeksAgoTime = nowMs - 10 * 7 * 86400 * 1000;
    const oldWeek = getIstanbulWeekInfo(new Date(tenWeeksAgoTime)).weekKey;
    (ctx.storage as any).sql.exec(
      'INSERT INTO week_wins (week_key, uid, nickname, wins, losses, reached_at) VALUES (?, ?, ?, 5, 0, ?)',
      oldWeek,
      'uid_fossil',
      'Fossil',
      tenWeeksAgoTime
    );

    // Temizliği çalıştır
    lb.cleanupOldData(nowMs);

    // Eski processed_matches silinmiş olmalı
    const oldMatches = (ctx.storage as any).sql
      .exec('SELECT match_id FROM processed_matches WHERE match_id = ?', 'very_old_match')
      .toArray();
    expect(oldMatches).toHaveLength(0);

    // 10 hafta önceki week_wins silinmiş olmalı
    const fossilRows = (ctx.storage as any).sql
      .exec('SELECT uid FROM week_wins WHERE week_key = ?', oldWeek)
      .toArray();
    expect(fossilRows).toHaveLength(0);
  });

  it('9. deleteUserData kullanıcının week_wins ve pair_wins satırlarını temizler', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = new Date('2026-10-18T12:00:00Z').getTime();

    // Alice Bob'a karşı kazandı
    await lb.recordMatchResult({
      matchId: 'match_del_1',
      winnerUid: 'alice',
      winnerNickname: 'Alice',
      loserUid: 'bob',
      loserNickname: 'Bob',
      finishedAtMs: nowMs,
    });

    // Bob Charlie'ye karşı kazandı
    await lb.recordMatchResult({
      matchId: 'match_del_2',
      winnerUid: 'bob',
      winnerNickname: 'Bob',
      loserUid: 'charlie',
      loserNickname: 'Charlie',
      finishedAtMs: nowMs + 100,
    });

    // Bob hesabını sildi
    await lb.deleteUserData('bob');

    // Bob week_wins içinde bulunmamalı
    const bobWeekWins = (ctx.storage as any).sql
      .exec('SELECT * FROM week_wins WHERE uid = ?', 'bob')
      .toArray();
    expect(bobWeekWins).toHaveLength(0);

    // pair_wins içinde Bob winner veya loser olarak bulunmamalı
    const bobPairWins = (ctx.storage as any).sql
      .exec('SELECT * FROM pair_wins WHERE winner_uid = ? OR loser_uid = ?', 'bob', 'bob')
      .toArray();
    expect(bobPairWins).toHaveLength(0);

    // Alice'in week_wins kaydı korunmalı
    const aliceWeekWins = (ctx.storage as any).sql
      .exec('SELECT * FROM week_wins WHERE uid = ?', 'alice')
      .toArray();
    expect(aliceWeekWins).toHaveLength(1);
  });

  it('10. Silinen kullanıcıyla (deletedUids) oynayıp kazanan rakibin galibiyeti week_wins tablosuna yazılır ancak pair_wins tablosuna yazılmaz', async () => {
    const ctx = createMockCtx();
    const env = createEnv();
    const lb = new Leaderboard(ctx, env);
    const nowMs = new Date('2026-10-18T12:00:00Z').getTime();

    // Alice kazandı, ancak rakip Bob maç anında silinmiş (deletedUids: ['bob'])
    await lb.recordMatchResult({
      matchId: 'match_deleted_opponent',
      winnerUid: 'alice',
      winnerNickname: 'Alice',
      loserUid: 'bob',
      loserNickname: 'Bob',
      finishedAtMs: nowMs,
      deletedUids: ['bob'],
    });

    // Alice'in galibiyeti week_wins'e yazılmalıdır
    const aliceWins = (ctx.storage as any).sql
      .exec('SELECT wins FROM week_wins WHERE uid = ?', 'alice')
      .toArray();
    expect(aliceWins).toHaveLength(1);
    expect(aliceWins[0].wins).toBe(1);

    // Bob silindiği için week_wins'e mağlubiyet yazılmamalıdır
    const bobWins = (ctx.storage as any).sql
      .exec('SELECT * FROM week_wins WHERE uid = ?', 'bob')
      .toArray();
    expect(bobWins).toHaveLength(0);

    // pair_wins tablosuna silinen Bob'un uid'si yazılmamalıdır
    const pairRows = (ctx.storage as any).sql
      .exec('SELECT * FROM pair_wins WHERE winner_uid = ? OR loser_uid = ?', 'bob', 'bob')
      .toArray();
    expect(pairRows).toHaveLength(0);
  });
});

