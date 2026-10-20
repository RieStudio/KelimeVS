import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index';

const daysMap: Record<string, number> = {
  Mon: 0,
  Tue: 1,
  Wed: 2,
  Thu: 3,
  Fri: 4,
  Sat: 5,
  Sun: 6,
};

export interface IstanbulWeekInfo {
  readonly weekKey: string;
  readonly startOfWeekMs: number;
  readonly endsAtMs: number;
}

/**
 * Verilen tarihe göre Türkiye (Europe/Istanbul) saat diliminde
 * haftanın başlangıcı (Pazartesi 00:00:00), bitişi (sonraki Pazartesi 00:00:00)
 * ve ISO hafta anahtarını (örn. "2026-W42") hesaplar.
 */
export function getIstanbulWeekInfo(date: Date = new Date()): IstanbulWeekInfo {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    weekday: 'short',
    hourCycle: 'h23',
  });

  const map: Record<string, string> = {};
  for (const p of formatter.formatToParts(date)) {
    map[p.type] = p.value;
  }

  const daysSinceMonday = daysMap[map.weekday] ?? 0;
  const hour = parseInt(map.hour, 10);
  const min = parseInt(map.minute, 10);
  const sec = parseInt(map.second, 10);
  const ms = date.getUTCMilliseconds();

  const elapsedSinceMondayMs =
    (daysSinceMonday * 86400 + hour * 3600 + min * 60 + sec) * 1000 + ms;
  const startOfWeekMs = date.getTime() - elapsedSinceMondayMs;
  const endsAtMs = startOfWeekMs + 7 * 86400 * 1000;

  // ISO 8601 hafta numarası: Haftanın Perşembe gününün takvim yılı ve haftası belirler
  const thursday = new Date(startOfWeekMs + 3 * 86400 * 1000 + 12 * 3600 * 1000);
  const thuMap: Record<string, string> = {};
  for (const p of formatter.formatToParts(thursday)) {
    thuMap[p.type] = p.value;
  }
  const thuYear = parseInt(thuMap.year, 10);
  const thuMonth = parseInt(thuMap.month, 10);
  const thuDay = parseInt(thuMap.day, 10);

  const thuUtc = Date.UTC(thuYear, thuMonth - 1, thuDay);
  const jan1Day = new Date(Date.UTC(thuYear, 0, 1)).getUTCDay();
  const firstThursdayUtc = Date.UTC(thuYear, 0, 1 + ((4 - jan1Day + 7) % 7));
  const weekNumber = 1 + Math.round((thuUtc - firstThursdayUtc) / (7 * 86400 * 1000));
  const weekKey = `${thuYear}-W${String(weekNumber).padStart(2, '0')}`;

  return {
    weekKey,
    startOfWeekMs,
    endsAtMs,
  };
}

export interface LeaderboardEntry {
  readonly rank: number;
  readonly nickname: string;
  readonly wins: number;
  readonly isMe: boolean;
}

export interface LeaderboardMe {
  readonly rank: number;
  readonly wins: number;
}

export interface LeaderboardResponse {
  readonly weekKey: string;
  readonly endsAt: number;
  readonly top: readonly LeaderboardEntry[];
  readonly me: LeaderboardMe | null;
}

export interface RecordMatchResultParams {
  readonly matchId: string;
  readonly winnerUid: string;
  readonly winnerNickname: string | null;
  readonly loserUid: string;
  readonly loserNickname: string | null;
  readonly finishedAtMs?: number;
  readonly deletedUids?: readonly string[];
  readonly skipPairWins?: boolean;
}

export interface RecordMatchResultResult {
  readonly ok: boolean;
  readonly alreadyProcessed?: boolean;
  readonly capped?: boolean;
}

export class Leaderboard extends DurableObject<Env> {
  private initialized = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private ensureSchema(): void {
    if (this.initialized) return;

    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS week_wins (
        week_key TEXT NOT NULL,
        uid TEXT NOT NULL,
        nickname TEXT,
        wins INTEGER NOT NULL DEFAULT 0,
        losses INTEGER NOT NULL DEFAULT 0,
        reached_at INTEGER NOT NULL,
        PRIMARY KEY (week_key, uid)
      );

      CREATE TABLE IF NOT EXISTS pair_wins (
        week_key TEXT NOT NULL,
        winner_uid TEXT NOT NULL,
        loser_uid TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (week_key, winner_uid, loser_uid)
      );

      CREATE TABLE IF NOT EXISTS processed_matches (
        match_id TEXT PRIMARY KEY,
        processed_at INTEGER NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_week_wins_leaderboard ON week_wins (week_key, wins, losses, reached_at);
      CREATE INDEX IF NOT EXISTS idx_processed_matches_at ON processed_matches (processed_at);
    `);

    this.initialized = true;
  }

  /**
   * 14 günden eski işlenmiş maçları ve 8 haftadan eski sıralama verilerini temizler.
   */
  cleanupOldData(nowMs: number = Date.now()): void {
    this.ensureSchema();

    const matchesCutoffMs = nowMs - 14 * 86400 * 1000;
    this.ctx.storage.sql.exec(
      'DELETE FROM processed_matches WHERE processed_at < ?',
      matchesCutoffMs
    );

    const weekCutoffInfo = getIstanbulWeekInfo(new Date(nowMs - 8 * 7 * 86400 * 1000));
    this.ctx.storage.sql.exec(
      'DELETE FROM week_wins WHERE week_key < ?',
      weekCutoffInfo.weekKey
    );
    this.ctx.storage.sql.exec(
      'DELETE FROM pair_wins WHERE week_key < ?',
      weekCutoffInfo.weekKey
    );
  }

  /**
   * Maç sonucunu liderlik tablosuna kaydeder.
   * - matchId idempotenttir.
   * - Aynı rakibe karşı haftada en fazla 3 galibiyet sayılır.
   * - Takma adı olmayan oyuncu tabloya yazılmaz.
   */
  async recordMatchResult(params: RecordMatchResultParams): Promise<RecordMatchResultResult> {
    this.ensureSchema();

    // 1. İdempotentlik kontrolü
    const existing = this.ctx.storage.sql.exec(
      'SELECT match_id FROM processed_matches WHERE match_id = ? LIMIT 1',
      params.matchId
    ).toArray();

    if (existing.length > 0) {
      return { ok: true, alreadyProcessed: true };
    }

    const nowMs = params.finishedAtMs ?? Date.now();
    const weekInfo = getIstanbulWeekInfo(new Date(nowMs));
    const weekKey = weekInfo.weekKey;

    // 2. Anti-farming / Pair win sınırı kontrolü (aynı rakibe en fazla 3 galibiyet)
    // Silinmiş kullanıcı varsa pair_wins'e yazılmaz.
    const isWinnerDeleted = params.deletedUids?.includes(params.winnerUid) ?? false;
    const isLoserDeleted = params.deletedUids?.includes(params.loserUid) ?? false;
    const shouldSkipPairWins = params.skipPairWins || isWinnerDeleted || isLoserDeleted;

    let isCapped = false;
    if (!shouldSkipPairWins) {
      const pairRows = this.ctx.storage.sql.exec<{ count: number }>(
        'SELECT count FROM pair_wins WHERE week_key = ? AND winner_uid = ? AND loser_uid = ? LIMIT 1',
        weekKey,
        params.winnerUid,
        params.loserUid
      ).toArray();

      const currentPairCount = pairRows.length > 0 ? pairRows[0].count : 0;
      isCapped = currentPairCount >= 3;

      // İkili galibiyet sayısını güncelle
      this.ctx.storage.sql.exec(
        `INSERT INTO pair_wins (week_key, winner_uid, loser_uid, count)
         VALUES (?, ?, ?, 1)
         ON CONFLICT(week_key, winner_uid, loser_uid) DO UPDATE SET count = count + 1`,
        weekKey,
        params.winnerUid,
        params.loserUid
      );
    }

    // 3. Kazananı güncelle (silinmemişse, sınır aşılmadıysa ve takma adı varsa)
    const winnerNick = params.winnerNickname?.trim();
    if (winnerNick && !isCapped && !isWinnerDeleted) {
      this.ctx.storage.sql.exec(
        `INSERT INTO week_wins (week_key, uid, nickname, wins, losses, reached_at)
         VALUES (?, ?, ?, 1, 0, ?)
         ON CONFLICT(week_key, uid) DO UPDATE SET
           wins = wins + 1,
           nickname = excluded.nickname,
           reached_at = excluded.reached_at`,
        weekKey,
        params.winnerUid,
        winnerNick,
        nowMs
      );
    }

    // 4. Kaybedeni güncelle (silinmemişse ve takma adı varsa mağlubiyet sayacı eşitlik sırası için artar)
    const loserNick = params.loserNickname?.trim();
    if (loserNick && !isLoserDeleted) {
      this.ctx.storage.sql.exec(
        `INSERT INTO week_wins (week_key, uid, nickname, wins, losses, reached_at)
         VALUES (?, ?, ?, 0, 1, ?)
         ON CONFLICT(week_key, uid) DO UPDATE SET
           losses = losses + 1,
           nickname = excluded.nickname`,
        weekKey,
        params.loserUid,
        loserNick,
        nowMs
      );
    }

    // 5. İşlenen maçı kaydet
    this.ctx.storage.sql.exec(
      'INSERT INTO processed_matches (match_id, processed_at) VALUES (?, ?)',
      params.matchId,
      nowMs
    );

    // 6. Veri temizliği
    this.cleanupOldData(nowMs);

    // 7. Tek alarm: sonraki temizlik alarmı yoksa 24 saat sonrasına kur
    const existingAlarm = await this.ctx.storage.getAlarm();
    if (existingAlarm === null) {
      await this.ctx.storage.setAlarm(nowMs + 24 * 3600 * 1000);
    }

    return { ok: true, capped: isCapped };
  }

  /**
   * Kullanıcının haftalık galibiyet ve ikili galibiyet (pair_wins) verilerini kalıcı olarak siler.
   */
  async deleteUserData(uid: string): Promise<void> {
    this.ensureSchema();
    const effectiveUid = uid.trim();
    if (!effectiveUid) return;

    this.ctx.storage.sql.exec('DELETE FROM week_wins WHERE uid = ?', effectiveUid);
    this.ctx.storage.sql.exec(
      'DELETE FROM pair_wins WHERE winner_uid = ? OR loser_uid = ?',
      effectiveUid,
      effectiveUid
    );
  }

  /**
   * Kullanıcının takma adı değiştiğinde mevcut tablodaki satırlarını günceller.
   */
  async updateNickname(uid: string, nickname: string): Promise<void> {
    this.ensureSchema();
    const trimmed = nickname.trim();
    if (!trimmed) return;

    this.ctx.storage.sql.exec(
      'UPDATE week_wins SET nickname = ? WHERE uid = ?',
      trimmed,
      uid
    );
  }

  /**
   * Haftalık liderlik tablosunu ve istek yapan kullanıcının sırasını getirir.
   */
  async getLeaderboard(callerUid?: string, atMs?: number): Promise<LeaderboardResponse> {
    this.ensureSchema();

    const nowMs = atMs ?? Date.now();
    const weekInfo = getIstanbulWeekInfo(new Date(nowMs));
    const weekKey = weekInfo.weekKey;
    const endsAt = weekInfo.endsAtMs;

    const topCursor = this.ctx.storage.sql.exec<{
      rank: number;
      uid: string;
      nickname: string;
      wins: number;
    }>(
      `WITH ranked AS (
        SELECT
          uid,
          nickname,
          wins,
          losses,
          reached_at,
          ROW_NUMBER() OVER (
            ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC
          ) as rank
        FROM week_wins
        WHERE week_key = ? AND wins > 0 AND nickname IS NOT NULL AND TRIM(nickname) != ''
      )
      SELECT rank, uid, nickname, wins FROM ranked ORDER BY rank ASC LIMIT 50`,
      weekKey
    );

    const topRows = topCursor.toArray();
    const top: LeaderboardEntry[] = topRows.map((r) => ({
      rank: Number(r.rank),
      nickname: String(r.nickname),
      wins: Number(r.wins),
      isMe: callerUid ? r.uid === callerUid : false,
    }));

    let me: LeaderboardMe | null = null;
    if (callerUid && callerUid.trim().length > 0) {
      const meCursor = this.ctx.storage.sql.exec<{
        rank: number;
        wins: number;
      }>(
        `WITH ranked AS (
          SELECT
            uid,
            wins,
            losses,
            reached_at,
            ROW_NUMBER() OVER (
              ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC
            ) as rank
          FROM week_wins
          WHERE week_key = ? AND wins > 0 AND nickname IS NOT NULL AND TRIM(nickname) != ''
        )
        SELECT rank, wins FROM ranked WHERE uid = ? LIMIT 1`,
        weekKey,
        callerUid.trim()
      );
      const meRows = meCursor.toArray();
      if (meRows.length > 0) {
        me = {
          rank: Number(meRows[0].rank),
          wins: Number(meRows[0].wins),
        };
      }
    }

    return {
      weekKey,
      endsAt,
      top,
      me,
    };
  }

  async alarm(): Promise<void> {
    this.ensureSchema();
    const nowMs = Date.now();
    this.cleanupOldData(nowMs);
    await this.ctx.storage.setAlarm(nowMs + 24 * 3600 * 1000);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const callerUid = request.headers.get('X-User-Id') ?? undefined;

    if (request.method === 'DELETE' && (url.pathname === '/user' || url.pathname === '/me')) {
      if (callerUid) {
        await this.deleteUserData(callerUid);
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (request.method === 'GET' && url.pathname === '/leaderboard') {
      const data = await this.getLeaderboard(callerUid);
      return new Response(JSON.stringify(data), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not Found', { status: 404 });
  }
}

