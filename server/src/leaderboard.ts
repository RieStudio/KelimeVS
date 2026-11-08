import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index';
import { getIstanbulWeekInfo, type IstanbulWeekInfo, type LeaderboardSeedEntry } from './weekInfo';

export { getIstanbulWeekInfo, type IstanbulWeekInfo, type LeaderboardSeedEntry };

export const LEADERBOARD_TOP_LIMIT = 100;
export const DEFAULT_PAIR_WIN_CAP = 20;

export interface LeaderboardEntry {
  readonly rank: number;
  readonly nickname: string;
  readonly wins: number;
  readonly isMe: boolean;
  readonly frame?: string;
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
  readonly winnerFrame?: string;
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

  private get pairWinCap(): number {
    const raw = this.env?.LEADERBOARD_PAIR_WIN_CAP;
    if (raw === undefined || raw === null || raw.trim() === '') {
      return DEFAULT_PAIR_WIN_CAP;
    }
    const parsed = parseInt(raw, 10);
    if (!Number.isFinite(parsed)) {
      return DEFAULT_PAIR_WIN_CAP;
    }
    return parsed;
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

    // PRAGMA ile week_wins tablosunda frame kolonunun varlığı kontrol edilir, yoksa ALTER çalıştırılır
    const weekWinsCols = this.ctx.storage.sql
      .exec<{ name: string }>('PRAGMA table_info(week_wins)')
      .toArray();
    const hasFrameCol = weekWinsCols.some((c) => c.name === 'frame');
    if (!hasFrameCol) {
      this.ctx.storage.sql.exec(
        "ALTER TABLE week_wins ADD COLUMN frame TEXT NOT NULL DEFAULT 'classic'"
      );
    }

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
   * - Aynı rakibe karşı haftada en fazla varsayılan 20 galibiyet sayılır (LEADERBOARD_PAIR_WIN_CAP ile ayarlanabilir).
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

    // 2. Anti-farming / Pair win sınırı kontrolü (aynı rakibe haftada en fazla varsayılan 20 galibiyet)
    // Silinmiş kullanıcı varsa pair_wins'e yazılmaz.
    const isWinnerDeleted = params.deletedUids?.includes(params.winnerUid) ?? false;
    const isLoserDeleted = params.deletedUids?.includes(params.loserUid) ?? false;
    const shouldSkipPairWins = params.skipPairWins || isWinnerDeleted || isLoserDeleted;

    let isCapped = false;
    if (!shouldSkipPairWins) {
      const cap = this.pairWinCap;
      const pairRows = this.ctx.storage.sql.exec<{ count: number }>(
        'SELECT count FROM pair_wins WHERE week_key = ? AND winner_uid = ? AND loser_uid = ? LIMIT 1',
        weekKey,
        params.winnerUid,
        params.loserUid
      ).toArray();

      const currentPairCount = pairRows.length > 0 ? pairRows[0].count : 0;
      isCapped = cap > 0 && currentPairCount >= cap;

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
    const winnerFrame = params.winnerFrame?.trim() || 'classic';
    if (winnerNick && !isCapped && !isWinnerDeleted) {
      this.ctx.storage.sql.exec(
        `INSERT INTO week_wins (week_key, uid, nickname, wins, losses, reached_at, frame)
         VALUES (?, ?, ?, 1, 0, ?, ?)
         ON CONFLICT(week_key, uid) DO UPDATE SET
           wins = wins + 1,
           nickname = excluded.nickname,
           reached_at = excluded.reached_at,
           frame = excluded.frame`,
        weekKey,
        params.winnerUid,
        winnerNick,
        nowMs,
        winnerFrame
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
   * Kullanıcının avatar çerçevesi değiştiğinde mevcut tablodaki satırlarını günceller.
   */
  async updateFrame(uid: string, frame: string): Promise<void> {
    this.ensureSchema();
    const trimmed = frame.trim();
    if (!trimmed) return;

    this.ctx.storage.sql.exec(
      'UPDATE week_wins SET frame = ? WHERE uid = ?',
      trimmed,
      uid
    );
  }

  /**
   * Yerel test için toplu sahte oyuncu verisi ekler.
   * Güvenlik: Yalnızca 'seed_' ile başlayan UID'leri kabul eder; gerçek kullanıcılara dokunmaz.
   */
  async seedUsers(
    entries: readonly LeaderboardSeedEntry[],
    atMs: number = Date.now(),
    allowedMeUid?: string
  ): Promise<{ inserted: number }> {
    this.ensureSchema();

    const weekInfo = getIstanbulWeekInfo(new Date(atMs));
    const weekKey = weekInfo.weekKey;

    let inserted = 0;
    for (const entry of entries) {
      const isSeed = entry.uid.startsWith('seed_');
      const isAllowedMe = Boolean(allowedMeUid && entry.uid === allowedMeUid);
      if (!isSeed && !isAllowedMe) {
        continue;
      }
      const nickname = entry.nickname.trim();
      if (!nickname) {
        continue;
      }
      const frame = entry.frame.trim() || 'classic';
      const wins = Math.max(0, Math.floor(entry.wins));
      const losses = Math.max(0, Math.floor(entry.losses));
      const reachedAt = entry.reachedAt || atMs;

      this.ctx.storage.sql.exec(
        `INSERT INTO week_wins (week_key, uid, nickname, wins, losses, reached_at, frame)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(week_key, uid) DO UPDATE SET
           nickname = excluded.nickname,
           wins = excluded.wins,
           losses = excluded.losses,
           reached_at = excluded.reached_at,
           frame = excluded.frame`,
        weekKey,
        entry.uid,
        nickname,
        wins,
        losses,
        reachedAt,
        frame
      );
      inserted++;
    }

    return { inserted };
  }

  /**
   * Yerel test için eklenmiş 'seed_' ön ekli kayıtları liderlik tablosundan temizler.
   * Güvenlik: Yalnızca 'seed_%' desenine uyan kayıtları siler, gerçek kullanıcılara dokunmaz.
   */
  async clearSeedUsers(): Promise<{ deleted: number }> {
    this.ensureSchema();

    const countRow = this.ctx.storage.sql
      .exec<{ count: number }>("SELECT COUNT(*) as count FROM week_wins WHERE uid LIKE 'seed_%'")
      .toArray();
    const count = countRow[0]?.count ?? 0;

    this.ctx.storage.sql.exec("DELETE FROM week_wins WHERE uid LIKE 'seed_%'");
    this.ctx.storage.sql.exec(
      "DELETE FROM pair_wins WHERE winner_uid LIKE 'seed_%' OR loser_uid LIKE 'seed_%'"
    );

    return { deleted: count };
  }

  /**
   * Yerel test için eklenmiş belirli bir test kullanıcısını liderlik tablosundan temizler.
   * Güvenlik: Yalnızca parametre olarak verilen uid'yi siler, diğer kullanıcılara dokunmaz.
   */
  async clearMeUser(uid: string): Promise<{ deleted: number }> {
    this.ensureSchema();
    const cleanUid = uid.trim();
    if (!cleanUid) {
      return { deleted: 0 };
    }

    const countRow = this.ctx.storage.sql
      .exec<{ count: number }>('SELECT COUNT(*) as count FROM week_wins WHERE uid = ?', cleanUid)
      .toArray();
    const count = countRow[0]?.count ?? 0;

    this.ctx.storage.sql.exec('DELETE FROM week_wins WHERE uid = ?', cleanUid);
    this.ctx.storage.sql.exec(
      'DELETE FROM pair_wins WHERE winner_uid = ? OR loser_uid = ?',
      cleanUid,
      cleanUid
    );

    return { deleted: count };
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
      frame: string | null;
    }>(
      `WITH ranked AS (
        SELECT
          uid,
          nickname,
          wins,
          losses,
          reached_at,
          frame,
          ROW_NUMBER() OVER (
            ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC
          ) as rank
        FROM week_wins
        WHERE week_key = ? AND wins > 0 AND nickname IS NOT NULL AND TRIM(nickname) != ''
      )
      SELECT rank, uid, nickname, wins, frame FROM ranked ORDER BY rank ASC LIMIT ${LEADERBOARD_TOP_LIMIT}`,
      weekKey
    );

    const topRows = topCursor.toArray();
    const top: LeaderboardEntry[] = topRows.map((r) => ({
      rank: Number(r.rank),
      nickname: String(r.nickname),
      wins: Number(r.wins),
      isMe: callerUid ? r.uid === callerUid : false,
      frame: r.frame || 'classic',
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

